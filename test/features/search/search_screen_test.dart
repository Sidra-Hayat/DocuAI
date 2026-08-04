import 'dart:io';

import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/features/search/domain/entities/search_hit.dart';
import 'package:docuai/src/features/search/presentation/providers/search_providers.dart';
import 'package:docuai/src/features/search/presentation/screens/search_screen.dart';
import 'package:docuai/src/features/search/presentation/widgets/search_result_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

/// Fixes the screen in one state so each branch can be rendered without a real
/// index behind it.
class _StubSearchController extends SearchQueryController {
  _StubSearchController(this._initial);

  final SearchState _initial;

  @override
  SearchState build() => _initial;
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_search_screen');
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<void> pumpSearch(
    WidgetTester tester, {
    SearchState state = const SearchState(),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storagePathsProvider.overrideWithValue(StoragePaths(tempDir)),
          // The index reconciliation is exercised in the repository tests; here
          // it only needs to not reach for a Hive box that does not exist.
          searchIndexReadyProvider.overrideWith((ref) async {}),
          searchQueryControllerProvider.overrideWith(
            () => _StubSearchController(state),
          ),
        ],
        child: const MaterialApp(home: SearchScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('invites a search before anything is typed', (tester) async {
    await pumpSearch(tester);

    expect(find.text('Search your documents'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byType(SearchResultTile), findsNothing);
  });

  testWidgets('renders a tile per hit', (tester) async {
    await pumpSearch(
      tester,
      state: SearchState(
        query: 'invoice',
        results: AsyncData<List<SearchHit>>(<SearchHit>[
          SearchHit(
            document: buildDocument(id: 'a', title: 'Water bill'),
            score: 4,
            snippets: const <SearchSnippet>[
              SearchSnippet(
                pageIndex: 0,
                text: 'Total due 42.00 EUR',
                highlightStart: 6,
                highlightLength: 3,
              ),
            ],
          ),
          SearchHit(
            document: buildDocument(id: 'b', title: 'Rental agreement'),
            score: 2,
          ),
        ]),
      ),
    );

    expect(find.byType(SearchResultTile), findsNWidgets(2));
    expect(find.text('Water bill'), findsOneWidget);
    expect(find.text('Page 1'), findsOneWidget);
    expect(find.text('Matched the title'), findsOneWidget);
  });

  testWidgets('names the query when nothing matched', (tester) async {
    await pumpSearch(
      tester,
      state: const SearchState(
        query: 'helicopter',
        results: AsyncData<List<SearchHit>>(<SearchHit>[]),
      ),
    );

    expect(find.text('No matches for "helicopter"'), findsOneWidget);
    expect(
      find.textContaining('text has been recognised'),
      findsOneWidget,
      reason: 'an unread document is invisible to search and nothing else '
          'on this screen would explain why',
    );
  });

  testWidgets('shows a spinner while the query runs', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storagePathsProvider.overrideWithValue(StoragePaths(tempDir)),
          searchIndexReadyProvider.overrideWith((ref) async {}),
          searchQueryControllerProvider.overrideWith(
            () => _StubSearchController(
              const SearchState(
                query: 'invoice',
                results: AsyncLoading<List<SearchHit>>(),
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: SearchScreen()),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('explains an unreadable index', (tester) async {
    await pumpSearch(
      tester,
      state: SearchState(
        query: 'invoice',
        results: AsyncError<List<SearchHit>>(
          Exception('corrupt'),
          StackTrace.empty,
        ),
      ),
    );

    expect(find.text('Search is unavailable'), findsOneWidget);
  });

  // Split rather than pumped twice in one body: re-pumping with different
  // overrides keeps the notifier Riverpod already built for the first scope,
  // so the second state never reaches the widget.
  testWidgets('offers no clear button before anything is typed', (tester) async {
    await pumpSearch(tester);

    expect(find.byIcon(Icons.close), findsNothing);
  });

  testWidgets('offers a clear button once something is typed', (tester) async {
    await pumpSearch(tester, state: const SearchState(query: 'inv'));

    expect(find.byIcon(Icons.close), findsOneWidget);
  });
}
