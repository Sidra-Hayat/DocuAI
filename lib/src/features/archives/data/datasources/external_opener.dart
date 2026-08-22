import 'dart:io';

import 'package:flutter/services.dart';

/// Offers a file to whichever app on the device can open it.
///
/// The archive browser's answer to a `.xlsx`, a `.mp4` or a nested ZIP: DocuAI
/// cannot show any of them, and a row that does nothing when tapped reads as a
/// broken app rather than as somebody else's file.
///
/// The channel is implemented in `ExternalOpener.kt`, which mints a one-shot
/// content URI through DocuAI's FileProvider and starts a chooser. Nothing but
/// Android has an implementation, and nothing but the app's own cache can be
/// offered — both are enforced on the far side.
class ExternalOpener {
  const ExternalOpener();

  static const MethodChannel channel = MethodChannel(
    'com.sidrahayat.docuai/open_with',
  );

  static const String openMethod = 'openWith';

  /// Returns false when the request could not be made — the file has gone, or
  /// there is no host activity to start a chooser from.
  ///
  /// A device with nothing installed that opens the file still returns true:
  /// the chooser was shown, and it is the chooser that says "no apps can
  /// perform this action". Reporting that here would mean asking the package
  /// manager first, which on Android 11 and later needs a `<queries>` entry per
  /// file type — an unbounded list, for an archive that can hold anything.
  Future<bool> open({required String path, String? mimeType}) async {
    if (!Platform.isAndroid) return false;

    try {
      final opened = await channel.invokeMethod<bool>(openMethod, <String, String?>{
        'path': path,
        'mimeType': mimeType,
      });
      return opened ?? false;
    } on MissingPluginException {
      // No host activity — a widget test, or a background isolate. Reported as
      // "could not", which degrades the UI honestly.
      return false;
    } on PlatformException {
      return false;
    }
  }
}
