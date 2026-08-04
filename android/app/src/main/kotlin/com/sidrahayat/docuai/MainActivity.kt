package com.sidrahayat.docuai

import com.google.android.gms.common.ConnectionResult
import com.google.android.gms.common.GoogleApiAvailability
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Host activity.
 *
 * Carries one channel of its own: ML Kit's document scanner is an on-demand
 * Google Play Services module, so it is simply absent on non-GMS devices and on
 * emulator images without the Play Store. The scanner plugin exposes no way to
 * ask about that, and finding out by launching the activity means showing the
 * user a failure where an explanation belongs.
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL = "com.sidrahayat.docuai/scanner"
        const val IS_AVAILABLE = "isPlayServicesAvailable"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    IS_AVAILABLE -> result.success(isPlayServicesAvailable())
                    else -> result.notImplemented()
                }
            }
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
