import 'package:docuai/src/core/constants/app_constants.dart';
import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/features/search/domain/entities/search_hit.dart';
import 'package:docuai/src/features/search/presentation/providers/search_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeSearchRepository search;
  late ProviderContainer container;

  /// Comfortably past the debounce, so a scheduled query has certainly run.
  final pastDebounce = AppConstants.searchDebounce + const Duration(milliseconds: 120);

  setUp(() {
    search = FakeSearchRepository();
    container = ProviderContainer(
      overrides: [searchRepositoryProvider.overrideWithValue(search)],
    );
  });

  // A closure, not a tear-off: `container.dispose` would be evaluated here, at
  // registration time, before setUp has assigned the late field.
  tearDown(() => container.dispose());

  SearchQueryController controller() =>
      container.read(searchQueryControllerProvider.notifier);

  SearchState state() => container.read(searchQueryControllerProvider);

  test('starts empty, with no query and no results', () {
    expect(state().query, isEmpty);
    expect(state().hasQuery, isFalse);
    expect(state().results.value, isEmpty);
  });

  test('does not query until the term is long enough', () async {
    controller().onQueryChanged('i');
    await Future<void>.delayed(pastDebounce);

    expect(search.receivedQueries, isEmpty);
    expect(state().hasQuery, isFalse);
  });

  test('debounces typing into a single query', () async {
    controller()
      ..onQueryChanged('in')
      ..onQueryChanged('inv')
      ..onQueryChanged('invo')
      ..onQueryChanged('invoice');

    await Future<void>.delayed(pastDebounce);

    expect(
      search.receivedQueries,
      <String>['invoice'],
      reason: 'every keystroke must not become a query',
    );
  });

  test('keeps the typed text visible while the query is in flight', () {
    controller().onQueryChanged('invoice');

    expect(state().query, 'invoice');
  });

  test('publishes results once the query completes', () async {
    search.results = <SearchHit>[
      SearchHit(document: buildDocument(), score: 3.2),
    ];

    await controller().run('invoice');

    expect(state().results.value, hasLength(1));
  });

  test('surfaces a repository failure as an error state', () async {
    search.searchFailure = const StorageFailure('Index unreadable.');

    await controller().run('invoice');

    expect(state().results.hasError, isTrue);
    expect(state().results.error, isA<StorageFailure>());
  });

  test('a slow earlier query cannot overwrite a newer one', () async {
    search.results = <SearchHit>[
      SearchHit(document: buildDocument(id: 'old'), score: 1),
    ];
    final slow = controller().run('old query');

    search.results = <SearchHit>[
      SearchHit(document: buildDocument(id: 'new'), score: 1),
    ];
    await controller().run('new query');
    await slow;

    expect(
      state().results.value!.single.document.id,
      'new',
      reason: 'results must match the query the user can currently see',
    );
  });

  test('shortening the query back below the minimum clears the results', () async {
    search.results = <SearchHit>[
      SearchHit(document: buildDocument(), score: 1),
    ];
    await controller().run('invoice');
    expect(state().results.value, hasLength(1));

    controller().onQueryChanged('i');

    expect(state().results.value, isEmpty);
    expect(state().hasQuery, isFalse);
  });

  test('clear resets the query and the results', () async {
    search.results = <SearchHit>[
      SearchHit(document: buildDocument(), score: 1),
    ];
    await controller().run('invoice');

    controller().clear();

    expect(state().query, isEmpty);
    expect(state().results.value, isEmpty);
  });

  test('clearing cancels a debounced query that has not fired', () async {
    controller()
      ..onQueryChanged('invoice')
      ..clear();

    await Future<void>.delayed(pastDebounce);

    expect(search.receivedQueries, isEmpty);
  });
}
