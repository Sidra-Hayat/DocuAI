import '../../../../core/error/result.dart';
import '../../../search/domain/repositories/search_repository.dart';
import '../repositories/document_repository.dart';

/// Deletes a document and removes it from the search index.
///
/// The two steps run in this order on purpose: an index entry pointing at a
/// deleted document would surface a search hit that opens nothing, whereas a
/// document briefly missing from the index only means it cannot be found for a
/// moment. If de-indexing fails the delete is still reported as successful —
/// the user's intent was carried out, and Phase 6's index rebuild repairs the
/// stale entry.
class DeleteDocument {
  const DeleteDocument({
    required DocumentRepository documents,
    required SearchRepository search,
  }) : _documents = documents,
       _search = search;

  final DocumentRepository _documents;
  final SearchRepository _search;

  FutureResult<void> call(String documentId) async {
    await _search.removeFromIndex(documentId);
    return _documents.deleteDocument(documentId);
  }
}
