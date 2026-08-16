import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../entities/pdf_tool_models.dart';
import '../repositories/pdf_tools_repository.dart';

/// Joins several PDFs into one document, in the order given.
///
/// The validation lives here rather than in the repository for the reason every
/// other use case in this app keeps it: a title that is blank and a list with
/// one file in it are both things the user can fix, and neither is worth a
/// round trip to the file system to discover.
class MergePdfs {
  const MergePdfs(this._repository);

  final PdfToolsRepository _repository;

  /// Falls back to a dated name, like an import does, rather than refusing.
  static String defaultTitle(DateTime now) {
    final day = now.day.toString().padLeft(2, '0');
    final month = now.month.toString().padLeft(2, '0');
    return 'Merged $day/$month/${now.year}';
  }

  /// [sources] is the order the pages will appear in.
  FutureResult<MergeOutcome> call({
    required List<PdfSource> sources,
    required String title,
    ToolProgressCallback? onProgress,
  }) async {
    if (sources.length < 2) {
      return const Failed(
        ValidationFailure(
          'Add at least two PDFs — merging one file would just copy it.',
        ),
      );
    }

    final trimmed = title.trim();

    return _repository.merge(
      sources: sources,
      title: trimmed.isEmpty ? defaultTitle(DateTime.now()) : trimmed,
      onProgress: onProgress,
    );
  }
}

/// Adds one PDF to the list being built.
///
/// Its own use case because picking is where the platform is, and the merge
/// screen should not be reaching for a repository to open a file chooser.
class PickPdf {
  const PickPdf(this._repository);

  final PdfToolsRepository _repository;

  FutureResult<PdfSource> call() => _repository.pickPdf();
}
