import '../../../../core/error/result.dart';

/// What a picked file turned out to be.
///
/// The distinction that matters is not the file format but what the app can do
/// with it: something that becomes pages of images, or something that becomes
/// text. A PDF and a photograph are the same kind of import once one has been
/// rendered — both end up as page images that recognition reads.
enum ImportedFileKind {
  /// Became one or more page images. Recognition reads them, exactly as it
  /// reads a scan.
  pages,

  /// Became text directly, with no reading to do.
  text,
}

/// A file, converted into something the library can hold.
class ImportedFile {
  const ImportedFile({
    required this.name,
    required this.kind,
    this.imagePaths = const <String>[],
    this.text = '',
    this.truncatedAt,
  });

  /// The file's own name, without its extension — the document's title unless
  /// the user renames it. A file someone chose deliberately is almost always
  /// better named than "Imported 12/08/2026".
  final String name;

  final ImportedFileKind kind;

  /// Temporary JPEGs, in page order. Populated for [ImportedFileKind.pages].
  final List<String> imagePaths;

  /// Populated for [ImportedFileKind.text].
  final String text;

  /// How many pages were kept, when the file had more than the importer reads.
  ///
  /// Null when nothing was left behind, which is the ordinary case. Carried all
  /// the way to the screen on purpose: a two-hundred-page statement that
  /// silently becomes a sixty-page document is one the user believes is
  /// complete, and they would find out after sending it to somebody.
  final int? truncatedAt;

  bool get isEmpty =>
      kind == ImportedFileKind.pages ? imagePaths.isEmpty : text.trim().isEmpty;
}

/// Brings a file from the device into the app.
///
/// Separate from [ImageImportRepository] rather than folded into it, because
/// they are different platform doors: one is the system photo picker, which
/// hands back images and needs no storage permission, and this is the document
/// picker, which hands back anything and has to work out what it got.
abstract interface class FileImportRepository {
  /// Opens the system file picker and converts whatever comes back.
  ///
  /// A dismissed picker is a [Failed] carrying a cancelled `ImportFailure`, so
  /// callers can stay silent about it — the user knows they backed out.
  FutureResult<ImportedFile> pickFile();
}
