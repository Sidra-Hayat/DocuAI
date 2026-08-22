import 'dart:io';

import 'package:flutter/services.dart';

/// One file the user picked, already copied into the app's cache.
class PickedFile {
  const PickedFile({
    required this.path,
    required this.name,
    required this.sizeBytes,
    this.mimeType,
  });

  /// Absolute path inside the app's own cache directory.
  final String path;

  /// The file's own name, with its extension, as the picker reported it.
  final String name;

  final int sizeBytes;

  final String? mimeType;
}

/// What one trip to the picker produced.
class PickedFiles {
  const PickedFiles({required this.files, this.rejected = 0});

  const PickedFiles.none() : files = const <PickedFile>[], rejected = 0;

  final List<PickedFile> files;

  /// How many the user selected that could not be brought in — a provider that
  /// would not open, something past the size cap, a selection longer than one
  /// pick will take.
  ///
  /// Counted rather than dropped. A user who ticks twelve files and sees ten
  /// rows appear will conclude the app is unreliable, and the true answer —
  /// "two of those could not be read" — is one only this layer knows.
  final int rejected;

  bool get isEmpty => files.isEmpty && rejected == 0;
}

/// Several files at once, out of the system document picker.
///
/// The implementation is `FilePicker.kt`, which runs `ACTION_OPEN_DOCUMENT`
/// with `EXTRA_ALLOW_MULTIPLE` and copies whatever comes back into the app's
/// cache. Two things follow from that and are worth stating here, where the
/// rest of the app reads:
///
///  * **No storage permission is involved, at any API level.** The picker is a
///    system UI; what it returns is a grant to the files the user pointed at,
///    and nothing else on the device becomes readable.
///  * **What comes back is a path, not a URI.** The grant is spent on the far
///    side, immediately, because it does not survive into the isolate that
///    writes the archive.
///
/// This exists because neither of the app's two existing pickers can do it:
/// `flutter_file_dialog` returns exactly one path, and `image_picker` returns
/// pictures. A ZIP of one file at a time is not the feature.
class PickedFilesChannel {
  const PickedFilesChannel();

  static const MethodChannel channel = MethodChannel(
    'com.sidrahayat.docuai/pick_files',
  );

  static const String pickMethod = 'pickFiles';

  /// Opens the picker and waits for the user.
  ///
  /// Returns an empty result when they backed out, which is not an error and
  /// must not be reported as one — the user knows they dismissed it.
  ///
  /// [mimeTypes] narrows what the picker offers. Left null, anything openable
  /// can be chosen, which is the right default for an archive: a ZIP is a bag,
  /// and refusing to put a spreadsheet in one would be this app inventing a
  /// restriction the format does not have.
  Future<PickedFiles> pick({List<String>? mimeTypes}) async {
    if (!Platform.isAndroid) return const PickedFiles.none();

    try {
      final reply = await channel.invokeMapMethod<String, Object?>(
        pickMethod,
        <String, Object?>{'mimeTypes': mimeTypes},
      );

      if (reply == null) return const PickedFiles.none();

      final raw = (reply['files'] as List<Object?>? ?? const <Object?>[])
          .whereType<Map<Object?, Object?>>();

      return PickedFiles(
        files: <PickedFile>[
          for (final entry in raw)
            if (entry['path'] is String)
              PickedFile(
                path: entry['path']! as String,
                name: entry['name'] as String? ?? 'file',
                // Reported by the far side as it copies rather than read from
                // the provider's size column, which is allowed to lie.
                sizeBytes: (entry['sizeBytes'] as num? ?? 0).toInt(),
                mimeType: entry['mimeType'] as String?,
              ),
        ],
        rejected: (reply['rejected'] as num? ?? 0).toInt(),
      );
    } on MissingPluginException {
      // No host activity — a widget test, or a background isolate. Degrades to
      // "nothing was picked", which is honest and leaves the caller working.
      return const PickedFiles.none();
    } on PlatformException {
      return const PickedFiles.none();
    }
  }
}
