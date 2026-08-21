import 'package:path/path.dart' as p;

/// A file another app handed to DocuAI, already copied into private storage.
///
/// [path] is a real file this app owns, not a content URI. By the time one of
/// these exists the copy has already happened — see `IncomingFiles.kt` — which
/// is what lets the rest of the app treat a shared file exactly like a picked
/// one, with no grant to worry about and nothing that expires.
class IncomingFile {
  const IncomingFile({
    required this.path,
    required this.name,
    required this.sizeBytes,
    this.mimeType,
  });

  /// Absolute, inside the app's cache directory.
  final String path;

  /// The file's own name as the sending app reported it, already reduced to
  /// something safe to write. Carries its extension.
  final String name;

  final int sizeBytes;

  /// What the sending app or the content resolver called it. Often absent, and
  /// often wrong when present — which is why [isArchive] and its neighbours
  /// consult the extension as well.
  final String? mimeType;

  String get extension =>
      p.extension(name).replaceFirst('.', '').toLowerCase();

  /// Whether this should open the archive browser.
  ///
  /// Type *or* extension. WhatsApp reports a ZIP as
  /// `application/octet-stream`, Windows-made archives arrive as
  /// `application/x-zip-compressed`, and a file manager that copied the file
  /// from a share may report nothing at all — while the name has said `.zip`
  /// throughout.
  bool get isArchive =>
      extension == 'zip' ||
      mimeType == 'application/zip' ||
      mimeType == 'application/x-zip-compressed';

  @override
  String toString() => 'IncomingFile($name, $sizeBytes bytes, $mimeType)';
}

/// One hand-over: everything that arrived together.
///
/// A list rather than a single file because a multi-share of photographs is one
/// gesture and should become one document, the way the photo importer already
/// treats a multi-selection.
class IncomingDelivery {
  const IncomingDelivery({required this.files, this.rejected = 0});

  final List<IncomingFile> files;

  /// How many of the shared files could not be copied — a grant already
  /// revoked, a provider that failed, something past the size cap. Counted on
  /// the platform side, because only it knows how many were offered.
  final int rejected;

  bool get isEmpty => files.isEmpty;

  /// True when every file is an image, which is the one case worth treating as
  /// a single document rather than as several.
  bool get isAllImages =>
      files.isNotEmpty &&
      files.every(
        (file) => const <String>{
          'jpg',
          'jpeg',
          'png',
          'webp',
        }.contains(file.extension),
      );
}
