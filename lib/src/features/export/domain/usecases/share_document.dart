import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../documents/domain/entities/document.dart';
import '../repositories/export_repository.dart';
import 'export_document_as_pdf.dart';

/// Shares a document as a PDF, building one first if it does not exist yet.
///
/// From the user's side "Share" is a single action; whether an export already
/// happened is an implementation detail they should never have to think about.
/// Reusing an existing PDF also keeps the common case fast — rendering is the
/// slow part, and a document whose pages have not changed does not need it
/// again.
class ShareDocument {
  const ShareDocument({
    required ExportRepository export,
    required ExportDocumentAsPdf exportAsPdf,
  }) : _export = export,
       _exportAsPdf = exportAsPdf;

  final ExportRepository _export;
  final ExportDocumentAsPdf _exportAsPdf;

  FutureResult<void> call(Document document) async {
    var pdfPath = document.pdfPath;

    if (pdfPath == null) {
      final exported = await _exportAsPdf(document.id);
      switch (exported) {
        case Failed(:final failure):
          return Failed(failure);
        case Success(:final value):
          pdfPath = value.pdfPath;
      }
    }

    if (pdfPath == null) {
      return const Failed(
        ExportFailure('The PDF could not be prepared for sharing.'),
      );
    }

    return _export.shareFile(pdfPath, subject: document.title);
  }
}

/// Builds the document as a Word file and offers it to the share sheet.
///
/// Rebuilt every time rather than cached on the document. Composing a PDF
/// re-encodes every page image, which is why that one is kept; this is string
/// building, so a stored path would buy nothing and could only ever be wrong.
/// It is also the simplest possible answer to "never export stale content".
class ShareDocumentAsDocx {
  const ShareDocumentAsDocx(this._export);

  final ExportRepository _export;

  FutureResult<void> call(Document document) async {
    final built = await _export.buildDocx(document);

    return switch (built) {
      Failed(:final failure) => Failed(failure),
      Success(:final value) => _export.shareFile(value, subject: document.title),
    };
  }
}
