import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/utils/clock.dart';
import '../../../documents/domain/entities/document.dart';
import '../../../documents/domain/repositories/document_repository.dart';
import '../repositories/export_repository.dart';

/// Builds a PDF for a document and records where it went.
///
/// Returns the *updated* document rather than the path, so the caller can
/// render the new state — a detail screen that shows "Export" before and
/// "Share PDF" after needs the entity, not a string.
class ExportDocumentAsPdf {
  const ExportDocumentAsPdf({
    required ExportRepository export,
    required DocumentRepository documents,
    Clock clock = systemClock,
  }) : _export = export,
       _documents = documents,
       _now = clock;

  final ExportRepository _export;
  final DocumentRepository _documents;
  final Clock _now;

  FutureResult<Document> call(String documentId) async {
    final loaded = await _documents.getDocument(documentId);
    final Document document;
    switch (loaded) {
      case Failed(:final failure):
        return Failed(failure);
      case Success(:final value):
        document = value;
    }

    if (!document.hasPages) {
      return const Failed(
        ExportFailure('There are no pages to export in this document.'),
      );
    }

    final built = await _export.buildPdf(document);
    final String pdfPath;
    switch (built) {
      case Failed(:final failure):
        return Failed(failure);
      case Success(:final value):
        pdfPath = value;
    }

    return _documents.saveDocument(
      document.copyWith(pdfPath: pdfPath, updatedAt: _now()),
    );
  }
}
