package com.sidrahayat.docuai

import android.content.Intent
import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Host activity.
 *
 * Carries two channels of its own.
 *
 * The first is a capability check: ML Kit's document scanner is an on-demand
 * Google Play Services module, so it is simply absent on non-GMS devices and on
 * emulator images without the Play Store. The scanner plugin exposes no way to
 * ask about that, and finding out by launching the activity means showing the
 * user a failure where an explanation belongs.
 *
 * The second is [IncomingFiles], which turns a file another app handed over
 * into a file this one owns. See that class for why the copy happens
 * immediately and how the three arrival states are covered.
 *
 * The third is [ExternalOpener], the way back out: a file inside an archive
 * that DocuAI cannot read is handed to an app that can.
 *
 * The fourth is [FilePicker], which is the way *in* for files the user chooses
 * rather than files another app sends: several at once, through the system
 * document picker, for building a ZIP out of things that are not in the library.
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL = "com.sidrahayat.docuai/scanner"
        const val IS_AVAILABLE = "isPlayServicesAvailable"
    }

    private val incoming by lazy { IncomingFiles(applicationContext) }
    private val opener by lazy { ExternalOpener(this) }
    private val picker by lazy { FilePicker(this) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    IS_AVAILABLE -> result.success(isPlayServicesAvailable())
                    else -> result.notImplemented()
                }
            }

        incoming.attach(flutterEngine.dartExecutor.binaryMessenger)
        opener.attach(flutterEngine.dartExecutor.binaryMessenger)
        picker.attach(flutterEngine.dartExecutor.binaryMessenger)

        // The cold-start case. This runs inside `onCreate`, so the intent that
        // started the process is already attached and is read here — long
        // before Dart is listening, which is why IncomingFiles queues what it
        // finds rather than pushing it.
        incoming.handleIntent(intent)
    }

    /**
     * The warm and backgrounded cases.
     *
     * Reached because the activity is `singleTask`: there is only ever one
     * instance, and a second file arriving while it is alive is routed here
     * rather than stacking a new copy of the app — or, as happened before the
     * launch mode was corrected, being planted inside the sending app's task.
     *
     * **The order of these three lines is load-bearing.** `super.onNewIntent`
     * forwards the intent to the Flutter delegate, which — when deep linking is
     * enabled — reads `intent.getData()` and pushes the whole URI to the
     * framework as a route. Handling first means the file has been read and the
     * intent neutralised before the framework is given a chance to see a
     * `content://` URI it will try to navigate to.
     *
     * The manifest also switches that behaviour off, and that is the actual
     * fix; this ordering is the belt to its braces, and it is the right order
     * on its own merits. Nothing in this app registers a `NewIntentListener`,
     * so no plugin loses anything by being handed an intent whose data has
     * already been consumed.
     */
    override fun onNewIntent(intent: Intent) {
        incoming.handleIntent(intent)
        setIntent(intent)
        super.onNewIntent(intent)
    }

    /**
     * The document picker's answer comes back here.
     *
     * `FlutterActivity` routes this to the registered plugins, and every plugin
     * that started an activity is looking for its own request code. [FilePicker]
     * is not a plugin, so it is offered the result first and reports whether it
     * was the one waiting for it; anything else falls through to `super`
     * untouched, which is what keeps the image picker and the ML Kit scanner
     * working.
     */
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (picker.onActivityResult(requestCode, resultCode, data)) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        incoming.detach()
        opener.detach()
        picker.detach()
        super.onDestroy()
    }

    /**
     * Reports only whether Play Services is present and usable right now.
     *
     * Deliberately does not prompt the user to install or update it: that
     * dialog belongs to a deliberate action, not to a capability check that
     * runs when a screen opens.
     */
    private fun isPlayServicesAvailable(): Boolean =
        GoogleApiAvailability
            .getInstance()
            .isGooglePlayServicesAvailable(this) == ConnectionResult.SUCCESS
}
