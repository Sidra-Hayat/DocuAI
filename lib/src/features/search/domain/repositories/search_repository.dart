import '../../../../core/error/result.dart';
import '../../../documents/domain/entities/document.dart';
import '../entities/search_hit.dart';

/// Full-text search over recognised page text.
///
/// Phase 6 implements this as a BM25 inverted index persisted in Hive
/// (`HiveBoxes.searchIndex`). The contract says nothing about that: it is
/// stated in terms of queries and hits so the ranking function can be replaced
/// without touching a caller.
abstract interface class SearchRepository {
  /// Ranked matches for [query], best first.
  ///
  /// An unmatched query is an empty list, not a failure — finding nothing is a
  /// normal outcome that the UI renders as an empty state.
  AsyncResult<List<SearchHit>> search(String query);

  /// Adds or replaces a document's entries in the index.
  ///
  /// Called after OCR completes and after any edit that changes page text.
  /// Idempotent: re-indexing an already-indexed document replaces its entries
  /// rather than duplicating them.
  AsyncResult<void> indexDocument(Document document);

  /// Drops every entry pointing at [documentId]. Succeeds when the id was never
  /// indexed.
  AsyncResult<void> removeFromIndex(String documentId);

  /// Rebuilds the index from scratch over [documents].
  ///
  /// The repair path for an index that has drifted — after a failed de-index,
  /// or after a schema change that makes existing entries unreadable.
  AsyncResult<void> rebuildIndex(List<Document> documents);
}
