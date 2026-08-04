import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/result.dart';
import '../../../documents/domain/entities/document.dart';
import '../../domain/entities/search_hit.dart';
import '../../domain/repositories/search_repository.dart';

/// Stand-in for the real index until Phase 6 builds it.
///
/// Every method succeeds and does nothing. This exists so that use cases which
/// legitimately depend on the index — `DeleteDocument` de-registers a document,
/// `RecognizeDocumentText` registers one — can be wired up and exercised now,
/// instead of being bypassed in the UI and then retrofitted later.
///
/// Searching returns no hits, which is honest: nothing has been indexed.
/// Phase 6 replaces the single [searchRepositoryProvider] override and every
/// caller keeps working.
class UnindexedSearchRepository implements SearchRepository {
  const UnindexedSearchRepository();

  @override
  FutureResult<List<SearchHit>> search(String query) async =>
      const Success(<SearchHit>[]);

  @override
  FutureResult<void> indexDocument(Document document) async =>
      const Success<void>(null);

  @override
  FutureResult<void> removeFromIndex(String documentId) async =>
      const Success<void>(null);

  @override
  FutureResult<void> rebuildIndex(List<Document> documents) async =>
      const Success<void>(null);
}

/// Phase 6 overrides this with the BM25 implementation.
final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => const UnindexedSearchRepository(),
);
