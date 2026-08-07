import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/error/result.dart';
import '../../../documents/presentation/providers/document_providers.dart';
import '../../data/datasources/search_index_local_data_source.dart';
import '../../data/repositories/bm25_search_repository.dart';
import '../../domain/entities/search_hit.dart';
import '../../domain/repositories/search_repository.dart';
import '../../domain/usecases/search_documents.dart';

// ---- Dependencies ----------------------------------------------------------

final searchIndexDataSourceProvider = Provider<SearchIndexLocalDataSource>(
  (ref) => SearchIndexLocalDataSource(ref.watch(searchIndexBoxProvider)),
);

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => Bm25SearchRepository(
    index: ref.watch(searchIndexDataSourceProvider),
    documents: ref.watch(documentRepositoryProvider),
  ),
);

final searchDocumentsProvider = Provider<SearchDocuments>(
  (ref) => SearchDocuments(ref.watch(searchRepositoryProvider)),
);

/// Brings the index into agreement with the library before the first query.
///
/// Two things put it out of step, and neither is a bug:
///
///  * documents created before this phase existed were never indexed, and a
///    document with no recognised text still has a searchable title and tags;
///  * a delete whose de-index failed leaves an entry pointing at nothing.
///
/// Comparing counts is cheap, and rebuilding a personal library takes
/// milliseconds, so the repair runs when the search screen opens rather than
/// being deferred to a maintenance action nobody would find.
final searchIndexReadyProvider = FutureProvider<void>((ref) async {
  final index = ref.watch(searchIndexDataSourceProvider);
  final repository = ref.watch(searchRepositoryProvider);

  final loaded = await ref.watch(documentRepositoryProvider).getDocuments();
  if (loaded case Success(:final value)) {
    // A fingerprint rather than a count. Deleting one document and adding
    // another leaves the count unchanged while the contents are not, and a
    // count-based check would leave that index stale forever.
    final stale =
        !index.isCurrentVersion ||
        index.storedFingerprint != Bm25SearchRepository.fingerprintOf(value);

    if (stale) await repository.rebuildIndex(value);
  }
});

// ---- Screen state ----------------------------------------------------------

class SearchState {
  const SearchState({
    this.query = '',
    this.results = const AsyncData<List<SearchHit>>(<SearchHit>[]),
  });

  final String query;
  final AsyncValue<List<SearchHit>> results;

  /// True once the query is long enough to have been run.
  bool get hasQuery => query.trim().length >= SearchDocuments.minQueryLength;

  SearchState copyWith({String? query, AsyncValue<List<SearchHit>>? results}) =>
      SearchState(
        query: query ?? this.query,
        results: results ?? this.results,
      );
}

class SearchQueryController extends Notifier<SearchState> {
  Timer? _debounce;

  /// Guards against an earlier, slower query overwriting a later one's results.
  int _generation = 0;

  @override
  SearchState build() {
    ref.onDispose(() => _debounce?.cancel());
    return const SearchState();
  }

  void onQueryChanged(String query) {
    _debounce?.cancel();
    state = state.copyWith(query: query);

    if (query.trim().length < SearchDocuments.minQueryLength) {
      _generation++;
      state = state.copyWith(
        results: const AsyncData<List<SearchHit>>(<SearchHit>[]),
      );
      return;
    }

    _debounce = Timer(AppConstants.searchDebounce, () => run(query));
  }

  void clear() {
    _debounce?.cancel();
    _generation++;
    state = const SearchState();
  }

  Future<void> run(String query) async {
    final generation = ++_generation;
    state = state.copyWith(results: const AsyncLoading<List<SearchHit>>());

    final result = await ref.read(searchDocumentsProvider)(query);

    // A slower earlier query must not land on top of a newer one's results.
    if (generation != _generation) return;

    state = state.copyWith(
      results: result.fold(
        onSuccess: AsyncData<List<SearchHit>>.new,
        onFailure: (failure) => AsyncError<List<SearchHit>>(
          failure,
          StackTrace.current,
        ),
      ),
    );
  }
}

final searchQueryControllerProvider =
    NotifierProvider<SearchQueryController, SearchState>(SearchQueryController.new);
