import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../documents/domain/entities/document.dart';
import '../entities/pdf_tool_models.dart';
import '../repositories/pdf_tools_repository.dart';

/// Makes a smaller copy of a document's pages.
///
/// The original is never touched — the result is a new document, and the
/// outcome carries both sizes so the screen can show what was actually gained
/// rather than claiming a saving it has not measured.
class CompressDocument {
  const CompressDocument(this._repository);

  final PdfToolsRepository _repository;

  FutureResult<CompressionOutcome> call({
    required Document document,
    required CompressionLevel level,
    ToolProgressCallback? onProgress,
  }) async {
    if (!document.hasImagePages) {
      return const Failed(
        ValidationFailure(
          'This document is written text rather than scanned pages, so there '
          'is nothing to compress. Share it as a Word file instead.',
        ),
      );
    }

    return _repository.compress(
      document: document,
      level: level,
      onProgress: onProgress,
    );
  }
}

/// Makes a smaller copy of a PDF that is not in the library yet.
///
/// Its own use case rather than a flag on [CompressDocument]: the inputs are
/// genuinely different — one is a record the app owns, the other a file it has
/// been given read access to — and folding them together would mean a
/// nullable pair of parameters where exactly one must be set.
class CompressPdfFile {
  const CompressPdfFile(this._repository);

  final PdfToolsRepository _repository;

  FutureResult<CompressionOutcome> call({
    required PdfSource source,
    required CompressionLevel level,
    ToolProgressCallback? onProgress,
  }) => _repository.compressPdfFile(
    source: source,
    level: level,
    onProgress: onProgress,
  );
}
