import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/features/search/domain/entities/search_hit.dart';
import 'package:docuai/src/features/search/domain/usecases/search_documents.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeSearchRepository repository;
  late SearchDocuments search;

  setUp(() {
    repository = FakeSearchRepository();
    search = SearchDocuments(repository);
  });

  test('returns nothing and never queries for a too-short term', () async {
    for (final query in <String>['', ' ', 'a', '  b  ']) {
      final result = await search(query);

      expect(result.valueOrNull, isEmpty);
    }

    expect(repository.receivedQueries, isEmpty);
  });

  test('trims the query before forwarding it', () async {
    await search('  invoice  ');

    expect(repository.receivedQueries, <String>['invoice']);
  });

  test('passes the repository results through', () async {
    repository.results = <SearchHit>[
      SearchHit(document: buildDocument(), score: 4.2),
    ];

    final result = await search('invoice');

    expect(result.valueOrNull, hasLength(1));
    expect(result.valueOrNull!.single.score, 4.2);
  });

  test('an empty result set is a success, not a failure', () async {
    repository.results = <SearchHit>[];

    final result = await search('nothing matches this');

    expect(result.isSuccess, isTrue);
    expect(result.valueOrNull, isEmpty);
  });

  test('propagates a repository failure', () async {
    repository.searchFailure = const StorageFailure('Index unreadable.');

    final result = await search('invoice');

    expect(result.failureOrNull, isA<StorageFailure>());
  });

  group('SearchSnippet', () {
    test('validates the highlight range against the snippet text', () {
      const valid = SearchSnippet(
        pageIndex: 0,
        text: 'Total due: 42 EUR',
        highlightStart: 11,
        highlightLength: 2,
      );
      expect(valid.hasValidHighlight, isTrue);
      expect(valid.highlightEnd, 13);

      const overrun = SearchSnippet(
        pageIndex: 0,
        text: 'short',
        highlightStart: 3,
        highlightLength: 90,
      );
      expect(overrun.hasValidHighlight, isFalse);
    });
  });

  group('SearchHit', () {
    test('reports a title-only match when there are no snippets', () {
      final hit = SearchHit(document: buildDocument(), score: 1);

      expect(hit.matchedTitleOnly, isTrue);
      expect(hit.bestSnippet, isNull);
    });
  });
}
