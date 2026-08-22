package com.sidrahayat.docuai

import android.app.Activity
import android.content.Intent
import android.webkit.MimeTypeMap
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

/**
 * Hands a file DocuAI cannot read to whichever app can.
 *
 * The archive browser needs this. A ZIP is a bag of whatever its author put in
 * it — a spreadsheet, a video, another ZIP — and the alternative to this is a
 * row that does nothing when tapped, which reads as the app being broken rather
 * than as the file being someone else's business.
 *
 * ACTION_VIEW rather than ACTION_SEND, and the difference matters. SEND is what
 * a share sheet does: it offers to *give a copy* to WhatsApp or Drive. VIEW is
 * "open this", which is what the user meant — for a `.xlsx` that is a
 * spreadsheet app, for a nested ZIP an archive manager.
 *
 * The file is exposed through a `FileProvider` under a URI that is granted to
 * the chosen app for one read, and revoked when it is done. DocuAI's storage
 * stays private: no permission is granted to a directory, only to the one file,
 * and only to the app the user picked out of the chooser.
 */
class ExternalOpener(private val activity: Activity) {

    private companion object {
        const val CHANNEL = "com.sidrahayat.docuai/open_with"
        const val OPEN = "openWith"

        /** Must match the authority declared for the provider in the manifest. */
        const val AUTHORITY = "com.sidrahayat.docuai.fileprovider"
    }

    private var channel: MethodChannel? = null

    fun attach(messenger: BinaryMessenger) {
        val created = MethodChannel(messenger, CHANNEL)
        created.setMethodCallHandler { call, result -> onMethodCall(call, result) }
        channel = created
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            OPEN -> result.success(
                open(
                    path = call.argument<String>("path"),
                    mimeType = call.argument<String>("mimeType"),
                ),
            )
            else -> result.notImplemented()
        }
    }

    /**
     * Returns false when the request could not be made at all — a file that is
     * no longer there, a path outside this app's cache, a chooser the system
     * refused to start.
     *
     * A boolean rather than an exception: every one of those is an ordinary
     * answer the user needs telling in a sentence, not a failure for the Dart
     * side to unpack. It is *not* a report of whether an app exists that can
     * open the file — the chooser answers that itself, on screen, and asking
     * the package manager first would need a `<queries>` declaration for every
     * type an archive might hold.
     */
    private fun open(path: String?, mimeType: String?): Boolean {
        if (path.isNullOrEmpty()) return false

        val file = File(path)
        if (!file.exists()) return false

        // Only ever a file this app wrote into its own cache. A path from
        // anywhere else would fail here rather than at the provider, which
        // reports it as a configuration error nobody can act on.
        val cacheRoot = activity.cacheDir.canonicalPath
        if (!file.canonicalPath.startsWith(cacheRoot + File.separator)) return false

        val uri = try {
            FileProvider.getUriForFile(activity, AUTHORITY, file)
        } catch (error: IllegalArgumentException) {
            return false
        }

        val type = mimeType?.takeIf { it.isNotBlank() }
            ?: guessType(file.name)
            // Not null: a VIEW intent with no type matches almost nothing, and
            // the generic type at least reaches the file managers.
            ?: "application/octet-stream"

        val view = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, type)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        // Always a chooser, never a direct launch. "Open with another app" is a
        // question, and a device with a default handler already set would
        // otherwise answer it silently with an app the user did not pick.
        val chooser = Intent.createChooser(view, null).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        return try {
            activity.startActivity(chooser)
            true
        } catch (error: Exception) {
            false
        }
    }

    private fun guessType(name: String): String? {
        val extension = name.substringAfterLast('.', "").lowercase(Locale.ROOT)
        if (extension.isEmpty()) return null
        return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
    }
}
