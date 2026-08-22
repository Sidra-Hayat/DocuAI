import '../../../../core/error/result.dart';
import '../../../pdf_tools/domain/entities/pdf_tool_models.dart';
import '../entities/zip_build.dart';

/// What one trip to the system file picker produced.
class ZipSourceSelection {
  const ZipSourceSelection({required this.sources, this.rejected = 0});

  const ZipSourceSelection.none()
    : sources = const <ZipSource>[],
      rejected = 0;

  final List<ZipSource> sources;

  /// How many chosen files could not be brought in. Reported, never dropped
  /// silently — see [ZipSkippedSource] for why this app counts these.
  final int rejected;

  bool get isEmpty => sources.isEmpty && rejected == 0;
}

/// Building a ZIP out of documents and files, and handing it on.
///
/// The counterpart of `ArchiveRepository`, which reads one. They are kept
/// apart deliberately: reading an archive means defending against a file a
/// stranger wrote, and writing one means producing something a stranger will
/// read. Almost nothing is shared but the file format, and a single interface
/// would have made the reader's rules look like they applied here too.
///
/// Like every repository in this app: nothing throws, everything returns a
/// [Result], and paths that cross this boundary are absolute only where the
/// file does not belong to the library.
abstract interface class ZipBuilderRepository {
  /// Opens the system document picker for several files at once.
  ///
  /// A dismissed picker is a [ZipSourceSelection.none], not a failure. The user
  /// backed out on purpose and telling them so is noise.
  FutureResult<ZipSourceSelection> pickFiles();

  /// Writes [sources] into a ZIP inside the app's cache.
  ///
  /// Documents are rendered to PDF on the way in; files go in as they are.
  /// Anything that cannot be produced is left out and named in
  /// [ZipBuildOutcome.skipped] rather than failing the whole archive — one
  /// unreadable file out of twelve should not cost the user the other eleven.
  ///
  /// [isCancelled] is polled throughout. A cancelled build returns an
  /// [ImportFailure] marked `cancelled`, and leaves no file behind anywhere.
  FutureResult<ZipBuildOutcome> build({
    required List<ZipSource> sources,
    required String archiveName,
    ToolProgressCallback? onProgress,
    bool Function()? isCancelled,
  });

  /// Opens the Android share sheet for an archive this repository built.
  ///
  /// Takes the absolute path from [ZipBuildOutcome.path]. Absolute, unlike the
  /// document export's relative paths, because this file lives in the cache
  /// rather than in the library — it is not something the app keeps.
  FutureResult<void> share(String archivePath);
}
