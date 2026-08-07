import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../scanner/domain/repositories/scanner_repository.dart';
import '../../../search/domain/repositories/search_repository.dart';
import '../entities/document.dart';
import '../repositories/document_repository.dart';

/// Captures pages and appends them to an existing document.
///
/// Composes the scanner with the library, the same shape as `ScanNewDocument`.
/// Keeping the composition in a use case is what stops the scanner needing to
/// know how documents are stored, or the library needing to know how pages are
/// captured.
class AddPagesToDocument {
  const AddPagesToDocument({
    required ScannerRepository scanner,
    required DocumentRepository documents,
    required SearchRepository search,
  }) : _scanner = scanner,
       _documents = documents,
       _search = search;

  final ScannerRepository _scanner;
  final DocumentRepository _documents;
  final SearchRepository _search;

  static const int defaultPageLimit = 20;

  FutureResult<Document> call(
    String documentId, {
    int pageLimit = defaultPageLimit,
  }) async {
    final scanned = await _scanner.scanPages(pageLimit: pageLimit);
    final List<String> imagePaths;
    switch (scanned) {
      case Failed(:final failure):
        return Failed(failure);
      case Success(:final value):
        imagePaths = value;
    }

    if (imagePaths.isEmpty) {
      return const Failed(
        ScanFailure('No pages were captured.', cancelled: true),
      );
    }

    final saved = await _documents.addPages(
      documentId: documentId,
      sourceImagePaths: imagePaths,
    );

    return _reindex(saved);
  }

  /// Keeps search in step. Best-effort: the pages are already safely stored,
  /// so a failure here costs discoverability until the next rebuild, not data.
  Future<Result<Document>> _reindex(Result<Document> saved) async {
    if (saved case Success(:final value)) {
      await _search.indexDocument(value);
    }
    return saved;
  }
}

/// Removes one page from a document.
class DeleteDocumentPage {
  const DeleteDocumentPage({
    required DocumentRepository documents,
    required SearchRepository search,
  }) : _documents = documents,
       _search = search;

  final DocumentRepository _documents;
  final SearchRepository _search;

  FutureResult<Document> call({
    required String documentId,
    required String pageId,
  }) async {
    final saved = await _documents.deletePage(
      documentId: documentId,
      pageId: pageId,
    );

    // The removed page's text leaves the document, so the index would keep
    // returning a document for words no longer in it.
    if (saved case Success(:final value)) {
      await _search.indexDocument(value);
    }
    return saved;
  }
}

/// Puts a document's pages in a new order.
///
/// No search re-index: reordering changes which page text appears on, not
/// which words the document contains, and the index is document-level.
class ReorderDocumentPages {
  const ReorderDocumentPages(this._documents);

  final DocumentRepository _documents;

  FutureResult<Document> call({
    required String documentId,
    required List<String> orderedPageIds,
  }) => _documents.reorderPages(
    documentId: documentId,
    orderedPageIds: orderedPageIds,
  );
}

/// Re-captures one page in place.
class ReplaceDocumentPage {
  const ReplaceDocumentPage({
    required ScannerRepository scanner,
    required DocumentRepository documents,
    required SearchRepository search,
  }) : _scanner = scanner,
       _documents = documents,
       _search = search;

  final ScannerRepository _scanner;
  final DocumentRepository _documents;
  final SearchRepository _search;

  FutureResult<Document> call({
    required String documentId,
    required String pageId,
  }) async {
    // One page at a time: replacing a page with several would leave the caller
    // deciding which of them wins, and the scanner has no notion of that.
    final scanned = await _scanner.scanPages(pageLimit: 1);
    final List<String> imagePaths;
    switch (scanned) {
      case Failed(:final failure):
        return Failed(failure);
      case Success(:final value):
        imagePaths = value;
    }

    if (imagePaths.isEmpty) {
      return const Failed(
        ScanFailure('No page was captured.', cancelled: true),
      );
    }

    final saved = await _documents.replacePage(
      documentId: documentId,
      pageId: pageId,
      sourceImagePath: imagePaths.first,
    );

    // The replaced page's old text is gone and its new text is not yet read,
    // so what the index holds for this document is now wrong either way.
    if (saved case Success(:final value)) {
      await _search.indexDocument(value);
    }
    return saved;
  }
}
