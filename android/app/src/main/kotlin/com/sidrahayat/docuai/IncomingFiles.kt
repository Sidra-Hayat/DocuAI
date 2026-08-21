package com.sidrahayat.docuai

import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Files handed to DocuAI by another app, made into ordinary files on disk.
 *
 * Android delivers a *content URI*, not a path, and that URI is readable only
 * for as long as the grant attached to the intent lives. Nothing further up can
 * work with one: the ZIP reader wants a file handle, the PDF rasteriser runs in
 * an isolate, and both would fail on a URI that had already been revoked. So
 * the URI is read once, here, the moment it arrives, and copied into the app's
 * own cache directory — after which the rest of the app is dealing with a file
 * it owns, and nothing depends on the sending app any more.
 *
 * Written as a MethodChannel rather than pulled in as a plugin, for the same
 * reason MainActivity already carries one for Play Services: this is a page of
 * platform glue, and a dependency for it would be a dependency that can break
 * the Android build later — as `file_picker` did for this project.
 *
 * **Delivery.** A file can arrive in three states of the app, and all three
 * land here:
 *
 *  - *Cold start.* The process does not exist. Android creates the activity
 *    with the intent already attached, `configureFlutterEngine` runs, and
 *    [handleIntent] is called with it before Dart has had a chance to listen.
 *    The result is queued in [pending] and drained by the first `takePending`.
 *  - *Warm resume.* The activity is alive and on screen. `singleTask` routes
 *    the new intent to `onNewIntent`, which calls [handleIntent]. Dart is
 *    listening by then, so the delivery goes straight down the channel.
 *  - *From the background.* The same path as a warm resume: the task is brought
 *    forward and `onNewIntent` fires. Should Android build a fresh activity
 *    instead — it may, if the task had been evicted — the cold-start path
 *    handles it. Neither path is allowed to assume the other did not happen.
 */
class IncomingFiles(private val context: Context) {

    private companion object {
        const val CHANNEL = "com.sidrahayat.docuai/incoming"

        /** Dart asks for whatever arrived before it was listening. */
        const val TAKE_PENDING = "takePending"

        /** Native pushes everything that arrives afterwards. */
        const val ON_FILES = "onIncomingFiles"

        /** Where copies live, under the app's private cache directory. */
        const val INCOMING_DIR = "incoming"

        /**
         * The largest single file that will be copied in.
         *
         * Not a judgement about what is worth opening — it is about the cache
         * directory. A copy is a second full-size copy of the user's file on a
         * device that may be nearly full, and a multi-gigabyte video shared by
         * mistake should be refused rather than allowed to fill the disk before
         * anything has looked at it.
         */
        const val MAX_BYTES = 512L * 1024 * 1024

        /**
         * How long a copy is kept.
         *
         * Old copies are swept when a new file arrives rather than when a
         * screen closes: a delivery can end anywhere — the user backs out, the
         * archive is corrupt, the process is killed mid-read — and a cleanup
         * step at each of those is one that will be missed at the next. Six
         * hours is long enough that nothing is deleted out from under a screen
         * still showing it.
         */
        const val KEEP_MILLIS = 6L * 60 * 60 * 1000
    }

    /**
     * Copying runs off the main thread. A ZIP arriving from Downloads can be
     * hundreds of megabytes, and reading it inside `onNewIntent` would hold the
     * main thread for the whole copy — an ANR on exactly the files this feature
     * exists for.
     */
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private var channel: MethodChannel? = null

    /** True once Dart has asked for its backlog and is therefore listening. */
    private var listening = false

    /** Deliveries that arrived before Dart was ready. */
    private val pending = mutableListOf<Map<String, Any?>>()

    fun attach(messenger: io.flutter.plugin.common.BinaryMessenger) {
        val created = MethodChannel(messenger, CHANNEL)
        created.setMethodCallHandler { call, result -> onMethodCall(call, result) }
        channel = created
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        listening = false
        io.shutdown()
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            TAKE_PENDING -> {
                listening = true
                val drained = pending.toList()
                pending.clear()
                result.success(drained)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Reads whatever the intent is carrying and delivers it to Dart.
     *
     * Returns true when the intent was one of ours, so a plain launcher start
     * is left alone.
     */
    fun handleIntent(intent: Intent?): Boolean {
        if (intent == null) return false

        val uris: List<Uri> = when (intent.action) {
            Intent.ACTION_VIEW -> listOfNotNull(intent.data)
            Intent.ACTION_SEND -> listOfNotNull(intent.readExtraStream())
            Intent.ACTION_SEND_MULTIPLE -> intent.readExtraStreams()
            else -> emptyList()
        }

        if (uris.isEmpty()) return false

        val declaredType = intent.type

        // Cleared from the intent so that a configuration change — a rotation,
        // a theme switch — cannot replay the same file. The activity is
        // recreated with the intent it was started with, and without this the
        // user's archive would reopen every time the screen turned.
        intent.action = Intent.ACTION_MAIN
        intent.data = null
        intent.removeExtra(Intent.EXTRA_STREAM)

        io.execute {
            sweepOldCopies()

            val copied = uris.mapNotNull { uri -> copyIn(uri, declaredType) }
            val delivery = mapOf(
                "files" to copied,
                // Said explicitly rather than inferred from a short list: a
                // three-file share where two failed to copy is not the same
                // thing as a two-file share, and only this side knows which
                // of them happened.
                "rejected" to (uris.size - copied.size),
            )

            main.post { deliver(delivery) }
        }

        return true
    }

    private fun deliver(delivery: Map<String, Any?>) {
        val target = channel
        if (target == null || !listening) {
            pending.add(delivery)
            return
        }
        target.invokeMethod(ON_FILES, delivery)
    }

    /**
     * Copies one URI into the cache and describes what landed.
     *
     * Returns null when the file could not be read or was refused — a revoked
     * grant, a provider that has gone away, something larger than [MAX_BYTES].
     * Those are counted and reported to Dart as `rejected`; there is nothing
     * useful to say per file that the user does not already know.
     */
    private fun copyIn(uri: Uri, declaredType: String?): Map<String, Any?>? {
        val resolver = context.contentResolver
        val name = displayName(resolver, uri)
        val mimeType = resolver.typeOrNull(uri) ?: declaredType ?: guessType(name)

        val directory = File(context.cacheDir, INCOMING_DIR).apply { mkdirs() }

        // Stamped, so two shares of the same file in one session cannot write
        // over each other — and so a file still open on screen is never the one
        // being replaced.
        val target = File(directory, System.currentTimeMillis().toString() + "_" + name)

        return try {
            var total = 0L

            resolver.openInputStream(uri).use { input ->
                if (input == null) return null

                target.outputStream().use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read <= 0) break

                        total += read
                        if (total > MAX_BYTES) {
                            // Checked as it copies rather than from the size
                            // column, which a provider is free to report
                            // wrongly or not at all. Stopping here means the
                            // partial copy is deleted below, having cost one
                            // buffer past the limit.
                            throw IllegalStateException("larger than MAX_BYTES")
                        }
                        output.write(buffer, 0, read)
                    }
                }
            }

            mapOf(
                "path" to target.absolutePath,
                "name" to name,
                "mimeType" to mimeType,
                "sizeBytes" to total,
            )
        } catch (error: Exception) {
            // A half-written copy is worse than none: it would open as a
            // corrupt archive and be reported as the user's file being damaged.
            target.delete()
            null
        }
    }

    /**
     * The file's own name, reduced to something safe to write.
     *
     * The display name comes from whichever app owns the file, and is not
     * trusted. A provider is free to report `../../databases/documents.hive`,
     * and this is the first place that would be turned into a path. Every
     * separator is stripped and the result forced to a bare file name, so the
     * copy can only ever land in the directory chosen for it.
     */
    private fun displayName(resolver: ContentResolver, uri: Uri): String {
        val reported = queryDisplayName(resolver, uri) ?: uri.lastPathSegment

        val cleaned = (reported ?: "shared")
            .replace('\\', '/')
            .substringAfterLast('/')
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .trimStart('.')
            .take(120)

        return cleaned.ifEmpty { "shared" }
    }

    private fun queryDisplayName(resolver: ContentResolver, uri: Uri): String? {
        if (uri.scheme != ContentResolver.SCHEME_CONTENT) return null

        return try {
            resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    if (!cursor.moveToFirst()) return@use null
                    val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (column < 0) null else cursor.getString(column)
                }
        } catch (error: Exception) {
            null
        }
    }

    private fun ContentResolver.typeOrNull(uri: Uri): String? = try {
        getType(uri)
    } catch (error: Exception) {
        null
    }

    /** Last resort, when neither the intent nor the provider names a type. */
    private fun guessType(name: String): String? {
        val extension = name.substringAfterLast('.', "").lowercase(Locale.ROOT)
        if (extension.isEmpty()) return null
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
    }

    /**
     * Deletes copies old enough that nothing can still be looking at them.
     *
     * Best effort throughout. A file that refuses to delete is one that will be
     * offered for deletion again on the next share, which is a better outcome
     * than an exception on a background thread taking down a copy that was
     * about to succeed.
     */
    private fun sweepOldCopies() {
        try {
            val directory = File(context.cacheDir, INCOMING_DIR)
            val cutoff = System.currentTimeMillis() - KEEP_MILLIS
            directory.listFiles()?.forEach { file ->
                if (file.lastModified() < cutoff) file.delete()
            }
        } catch (error: Exception) {
            // Nothing to do, and nobody to tell.
        }
    }
}

/**
 * `EXTRA_STREAM` from a single share, read through the typed accessor on the
 * versions that have one.
 *
 * The untyped `getParcelableExtra` is deprecated from API 33 and, worse, will
 * happily hand back something that is not a Uri at all. The typed call refuses
 * that at the platform.
 */
@Suppress("DEPRECATION")
private fun Intent.readExtraStream(): Uri? =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
    } else {
        getParcelableExtra(Intent.EXTRA_STREAM) as? Uri
    }

@Suppress("DEPRECATION")
private fun Intent.readExtraStreams(): List<Uri> {
    val extras = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
    } else {
        getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)
    }
    return extras?.filterNotNull() ?: emptyList()
}
