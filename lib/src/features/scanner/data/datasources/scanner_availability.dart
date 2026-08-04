import 'dart:io';

import 'package:flutter/services.dart';

/// Asks the host activity whether Google Play Services is usable.
///
/// ML Kit's document scanner ships as an on-demand Play Services module, so on
/// a non-GMS device — or an emulator image without the Play Store — it is not
/// merely slow to start, it cannot run at all. Screens check this so the
/// scanner button can explain itself instead of failing when tapped.
///
/// The channel is implemented in `MainActivity.kt`; there is no equivalent on
/// other platforms, which is why anything but Android answers `false` without
/// making a call.
class ScannerAvailability {
  const ScannerAvailability();

  static const MethodChannel channel = MethodChannel(
    'com.sidrahayat.docuai/scanner',
  );

  static const String isAvailableMethod = 'isPlayServicesAvailable';

  Future<bool> isAvailable() async {
    if (!Platform.isAndroid) return false;

    try {
      return await channel.invokeMethod<bool>(isAvailableMethod) ?? false;
    } on MissingPluginException {
      // The engine is running without the host activity — a widget test, or a
      // background isolate. Treated as unavailable, which is the safe answer:
      // it degrades the UI rather than promising a scanner that is not there.
      return false;
    } on PlatformException {
      return false;
    }
  }
}
