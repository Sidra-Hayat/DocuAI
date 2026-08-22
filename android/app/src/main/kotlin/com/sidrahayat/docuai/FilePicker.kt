package com.sidrahayat.docuai

import android.app.Activity
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Lets the user pick several files at once, and turns them into files this app
 * owns.
 *
 * Written for "Create a ZIP", where picking one file at a time is not a
 * limitation but a different feature: an archive of a dozen downloads built
 * through twelve round trips to the picker is one nobody would build twice.
 *
 * **ACTION_OPEN_DOCUMENT, and no storage permission of any kind.** The Storage
 * Access Framework shows Downloads, Recents, the phone's own storage and every
 * installed cloud provider, and hands back a URI the user chose themselves.
 * That is the whole point of it: it needs no `READ_EXTERNAL_STORAGE`, no
 * `READ_MEDIA_*`, and emphatically no `MANAGE_EXTERNAL_STORAGE` — an app asking
 * for that to build a ZIP would be asking to read the user's entire disk to do
 * a job the system is offering to do for it.
 *
 * `EXTRA_ALLOW_MULTIPLE` is the flag that makes the picker's selection mode
 * available. It is a request rather than a guarantee — a provider is free to
 * return a single item — which is why the result is read from `clipData` *and*
 * `data`, since a one-file selection comes back through the latter.
 *
 * **Why a channel and not a package.** The same reason `IncomingFiles` gives:
 * this is a page of platform glue, and the obvious package for it —
 * `file_picker` — is the one that has already broken this project's Android
 * build once. `flutter_file_dialog`, which the app does use, returns exactly
 * one path and has no multi-select to offer.
 *
 * The copy-into-cache below is deliberately a second implementation rather than
 * a refactor of the one in [IncomingFiles]. They look alike and are not the
 * same: that one reads an intent somebody else built and must survive a hostile
 * display name, this one reads a selection the user made in a system UI. Fusing
 * them would couple the file-sharing entry point to the ZIP builder, and the
 * shared thing would have to serve both sets of rules.
 */
class FilePicker(private val activity: Activity) {

    private companion object {
        const val CHANNEL = "com.sidrahayat.docuai/pick_files"
        const val PICK = "pickFiles"

        /** Distinctive enough not to collide with a plugin's own codes. */
        const val REQUEST_CODE = 0x21C9

        /** Where copies live, under the app's private cache directory. */
        const val PICKED_DIR = "docuai_picked"

        /**
         * The largest single file that will be copied in.
         *
         * The same figure [IncomingFiles] uses, for the same reason: a copy is
         * a second full-size copy of the user's file on a device that may be
         * nearly full, and something enormous picked by mistake should be
         * refused before it fills the cache rather than after.
         */
        const val MAX_BYTES = 512L * 1024 * 1024

        /** How many files one pick will accept. */
        const val MAX_FILES = 200

        /** How long a copy is kept. See [IncomingFiles] for the reasoning. */
        const val KEEP_MILLIS = 6L * 60 * 60 * 1000
    }

    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private var channel: MethodChannel? = null

    /**
     * The call waiting for a picker that is currently open, if any.
     *
     * One at a time. A second `pickFiles` while the chooser is up would leave
     * the first call with nothing ever to answer it, and a Dart future that
     * never completes is a screen that never comes back.
     */
    private var pending: MethodChannel.Result? = null

    fun attach(messenger: BinaryMessenger) {
        val created = MethodChannel(messenger, CHANNEL)
        created.setMethodCallHandler { call, result -> onMethodCall(call, result) }
        channel = created
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        // An activity going away with a picker open would otherwise strand the
        // call. Answered as an empty selection, which reads to the user as
        // "nothing was picked" — which is true.
        pending?.success(emptyResult())
        pending = null
        io.shutdown()
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            PICK -> start(result, call.argument<List<String>>("mimeTypes"))
            else -> result.notImplemented()
        }
    }

    private fun start(result: MethodChannel.Result, mimeTypes: List<String>?) {
        if (pending != null) {
            result.error("busy", "A file picker is already open.", null)
            return
        }

        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            // Only things that can actually be opened as a stream. Without this
            // the picker offers directories and virtual documents, neither of
            // which can be copied into a ZIP.
            addCategory(Intent.CATEGORY_OPENABLE)
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)

            // A ZIP can hold anything, so the filter is open by default. The
            // Dart side may still narrow it, and when it does both keys are
            // set: `type` is what old providers read and EXTRA_MIME_TYPES is
            // what the modern picker reads.
            if (mimeTypes.isNullOrEmpty()) {
                type = "*/*"
            } else {
                type = if (mimeTypes.size == 1) mimeTypes.first() else "*/*"
                putExtra(Intent.EXTRA_MIME_TYPES, mimeTypes.toTypedArray())
            }
        }

        pending = result

        try {
            activity.startActivityForResult(intent, REQUEST_CODE)
        } catch (error: Exception) {
            // No document provider on the device at all. Rare, but a bare
            // AOSP build or a heavily locked-down work profile can be one.
            pending = null
            result.error(
                "unavailable",
                "This phone has no file picker available.",
                null,
            )
        }
    }

    /**
     * Returns true when the result was ours, so the host activity can leave
     * everything else to the plugins.
     */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false

        val result = pending ?: return true
        pending = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            // Backing out of the picker is not a failure. It is reported as an
            // empty selection and the Dart side stays silent about it.
            result.success(emptyResult())
            return true
        }

        val uris = data.readSelectedUris()
        if (uris.isEmpty()) {
            result.success(emptyResult())
            return true
        }

        val accepted = uris.take(MAX_FILES)
        val overflow = uris.size - accepted.size

        io.execute {
            sweepOldCopies()

            val copied = accepted.mapNotNull { uri -> copyIn(uri) }
            val payload = mapOf(
                "files" to copied,
                // Said explicitly rather than inferred from a short list: a
                // twelve-file pick where two could not be read is not the same
                // thing as a ten-file pick, and only this side knows which
                // happened.
                "rejected" to (accepted.size - copied.size) + overflow,
            )

            main.post { result.success(payload) }
        }

        return true
    }

    private fun emptyResult(): Map<String, Any?> =
        mapOf("files" to emptyList<Map<String, Any?>>(), "rejected" to 0)

    /**
     * Copies one picked URI into the cache and describes what landed.
     *
     * Returns null when it could not be read or was refused. The URI grant
     * attached to the picker's result does not outlive this activity's task,
     * and certainly does not survive into the isolate that writes the archive
     * — so it is spent here, once, and everything above deals in ordinary
     * files afterwards.
     */
    private fun copyIn(uri: Uri): Map<String, Any?>? {
        val resolver = activity.contentResolver
        val name = displayName(resolver, uri)
        val mimeType = resolver.typeOrNull(uri) ?: guessType(name)

        val directory = File(activity.cacheDir, PICKED_DIR).apply { mkdirs() }

        // Stamped, so picking the same file twice in one session cannot write
        // over a copy something else is still holding.
        val target = File(directory, System.nanoTime().toString() + "_" + name)

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
                            // Measured as it copies rather than trusted from
                            // the size column, which a provider is free to
                            // report wrongly or not at all.
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
            // A half-written copy would go into the archive as a truncated
            // file, and the recipient would find out rather than the user.
            target.delete()
            null
        }
    }

    /**
     * The file's own name, reduced to something safe to write.
     *
     * The display name comes from whichever app owns the file and is not
     * trusted, for the reason [IncomingFiles] sets out: a provider is free to
     * report `../../databases/documents.hive`, and this is the first place that
     * would be turned into a path.
     */
    private fun displayName(resolver: ContentResolver, uri: Uri): String {
        val reported = queryDisplayName(resolver, uri) ?: uri.lastPathSegment

        val cleaned = (reported ?: "file")
            .replace('\\', '/')
            .substringAfterLast('/')
            .replace(Regex("[^A-Za-z0-9._-]"), "_")
            .trimStart('.')
            .take(120)

        return cleaned.ifEmpty { "file" }
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

    private fun guessType(name: String): String? {
        val extension = name.substringAfterLast('.', "").lowercase(Locale.ROOT)
        if (extension.isEmpty()) return null
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
    }

    /** Deletes copies old enough that no screen can still be holding one. */
    private fun sweepOldCopies() {
        try {
            val directory = File(activity.cacheDir, PICKED_DIR)
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
 * Everything the user selected.
 *
 * `clipData` carries a multiple selection and `data` carries a single one, and
 * which arrives is the picker's choice rather than ours — a provider that
 * ignores `EXTRA_ALLOW_MULTIPLE` returns one file through `data` even though
 * the flag was set. Reading both is what makes a one-file pick work.
 */
private fun Intent.readSelectedUris(): List<Uri> {
    val clip = clipData
    if (clip != null && clip.itemCount > 0) {
        return (0 until clip.itemCount).mapNotNull { index ->
            clip.getItemAt(index).uri
        }
    }
    return listOfNotNull(data)
}
