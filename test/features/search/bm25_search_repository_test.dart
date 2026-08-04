import 'dart:io';

import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/search/data/datasources/search_index_local_data_source.dart';
import 'package:docuai/src/features/search/data/repositories/bm25_search_repository.dart';
import 'package:docuai/src/features/search/domain/entities/search_hit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';

/// Run against a real Hive box, for the same reason the document repository
/// tests are: the persisted shape and the scoring are the behaviour, and a
/// mocked box would only assert that the code calls the methods it calls.
void main() {
  late Directory tempDir;
  late Box<dynamic> box;
  late SearchIndexLocalDataSource index;
  late FakeDocumentRepository documents;
  late Bm25SearchRepository repository;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_search_test');
    Hive.init(p.join(tempDir.path, 'hive'));
  });

  setUp(() async {
    box = await Hive.openBox<dynamic>(
      'search_${DateTime.now().microsecondsSinceEpoch}',
    );
    index = SearchIndexLocalDataSource(box);
    documents = FakeDocumentRepository();
    repository = Bm25SearchRepository(index: index, documents: documents);
  });

  tearDown(() async {
    await box.deleteFromDisk();
    documents.dispose();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Document documentWith({
    required String id,
    required String title,
    List<String> pageTexts = const <String>[],
  }) => buildDocument(
    id: id,
    title: title,
    pages: <DocumentPage>[
      for (var i = 0; i < pageTexts.length; i++)
        buildPage(
          id: '$id-p$i',
          index: i,
          text: pageTexts[i],
          ocrStatus: OcrStatus.completed,
        ),
    ],
  );

  Future<void> indexAll(List<Document> library) async {
    for (final document in library) {
      documents.seed(document);
      await repository.indexDocument(document);
    }
  }

  group('search', () {
    test('finds a document by text on one of its pages', () async {
      await indexAll(<Document>[
        documentWith(
          id: 'a',
          title: 'Water bill',
          pageTexts: <String>['Total due 42.00 EUR by 14 August'],
        ),
        documentWith(
          id: 'b',
          title: 'Lecture notes',
          pageTexts: <String>['Photosynthesis converts light into sugar'],
        ),
      ]);

      final result = await repository.search('photosynthesis');

      expect(result.valueOrNull, hasLength(1));
      expect(result.valueOrNull!.single.document.id, 'b');
    });

    test('finds a document by its title alone', () async {
      await indexAll(<Document>[
        documentWith(id: 'a', title: 'Passport'),
      ]);

      final result = await repository.search('passport');

      expect(result.valueOrNull, hasLength(1));
      expect(result.valueOrNull!.single.matchedTitleOnly, isTrue);
    });

    test('ranks a title match above a passing mention', () async {
      await indexAll(<Document>[
        documentWith(
          id: 'mention',
          title: 'Lecture notes',
          pageTexts: <String>[
            'The lecturer mentioned electricity once in passing, alongside a '
                'great deal of other material about unrelated subjects.',
          ],
        ),
        documentWith(
          id: 'titled',
          title: 'Electricity bill',
          pageTexts: <String>['Amount payable this quarter'],
        ),
      ]);

      final hits = (await repository.search('electricity')).valueOrNull!;

      expect(hits.first.document.id, 'titled');
      expect(hits, hasLength(2));
    });

    test('is case-insensitive', () async {
      await indexAll(<Document>[
        documentWith(
          id: 'a',
          title: 'Invoice',
          pageTexts: <String>['PAYMENT RECEIVED'],
        ),
      ]);

      expect((await repository.search('payment')).valueOrNull, hasLength(1));
      expect((await repository.search('PaYmEnT')).valueOrNull, hasLength(1));
    });

    test('a query matching nothing is an empty success', () async {
      await indexAll(<Document>[
        documentWith(id: 'a', title: 'Invoice', pageTexts: <String>['nothing']),
      ]);

      final result = await repository.search('helicopter');

      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull, isEmpty);
    });

    test('an empty index returns nothing rather than failing', () async {
      final result = await repository.search('anything');

      expect(result.isSuccess, isTrue);
      expect(result.valueOrNull, isEmpty);
    });

    test('skips an index entry whose document has been deleted', () async {
      final ghost = documentWith(
        id: 'ghost',
        title: 'Deleted',
        pageTexts: <String>['orphaned text'],
      );
      // Indexed but never seeded: the state left by a delete that failed to
      // de-index.
      await repository.indexDocument(ghost);

      final result = await repository.search('orphaned');

      expect(
        result.valueOrNull,
        isEmpty,
        reason: 'a hit that opens nothing is worse than a missing hit',
      );
    });
  });

  group('snippets', () {
    test('quotes the passage around the match with an exact highlight', () async {
      await indexAll(<Document>[
        documentWith(
          id: 'a',
          title: 'Rental agreement',
          pageTexts: <String>[
            'The tenant shall pay a deposit of two months rent before taking '
                'possession of the property described in schedule one.',
          ],
        ),
      ]);

      final snippet =
          (await repository.search('deposit')).valueOrNull!.single.bestSnippet!;

      expect(snippet.pageIndex, 0);
      expect(snippet.hasValidHighlight, isTrue);
      expect(
        snippet.text.substring(
          snippet.highlightStart,
          snippet.highlightEnd,
        ),
        'deposit',
      );
    });

    test('the highlight survives newlines being flattened', () async {
      await indexAll(<Document>[
        documentWith(
          id: 'a',
          title: 'Notes',
          pageTexts: <String>[
            'first line\nsecond line\nthe keyword appears here\nfourth line',
          ],
        ),
      ]);

      final snippet =
          (await repository.search('keyword')).valueOrNull!.single.bestSnippet!;

      expect(snippet.text, isNot(contains('\n')));
      expect(
        snippet.text.substring(snippet.highlightStart, snippet.highlightEnd),
        'keyword',
      );
    });

    test('marks a truncated excerpt with ellipses without shifting the range',
        () async {
      final long = 'padding ' * 40;
      await indexAll(<Document>[
        documentWith(
          id: 'a',
          title: 'Long',
          pageTexts: <String>['$long needle $long'],
        ),
      ]);

      final snippet =
          (await repository.search('needle')).valueOrNull!.single.bestSnippet!;

      expect(snippet.text, startsWith('…'));
      expect(snippet.text, endsWith('…'));
      expect(
        snippet.text.substring(snippet.highlightStart, snippet.highlightEnd),
        'needle',
      );
    });

    test('offers at most one passage per page, capped across the document',
        () async {
      await indexAll(<Document>[
        documentWith(
          id: 'a',
          title: 'Many pages',
          pageTexts: <String>[
            'match here',
            'match here',
            'match here',
            'match here',
            'match here',
          ],
        ),
      ]);

      final hit = (await repository.search('match')).valueOrNull!.single;

      expect(hit.snippets, hasLength(Bm25SearchRepository.maxSnippetsPerHit));
      expect(
        hit.snippets.map((snippet) => snippet.pageIndex),
        <int>[0, 1, 2],
      );
    });

    test('a title-only match carries no snippets', () async {
      await indexAll(<Document>[
        documentWith(
          id: 'a',
          title: 'Passport',
          pageTexts: <String>['unrelated content'],
        ),
      ]);

      final hit = (await repository.search('passport')).valueOrNull!.single;

      expect(hit.snippets, isEmpty);
      expect(hit.matchedTitleOnly, isTrue);
    });
  });

  group('index maintenance', () {
    test('re-indexing replaces an entry rather than duplicating it', () async {
      final document = documentWith(
        id: 'a',
        title: 'Draft',
        pageTexts: <String>['original text'],
      );
      await indexAll(<Document>[document]);

      final updated = document.copyWith(
        pages: <DocumentPage>[
          buildPage(
            id: 'a-p0',
            index: 0,
            text: 'replacement text',
            ocrStatus: OcrStatus.completed,
          ),
        ],
      );
      documents.seed(updated);
      await repository.indexDocument(updated);

      expect(index.documentCount, 1);
      expect((await repository.search('original')).valueOrNull, isEmpty);
      expect((await repository.search('replacement')).valueOrNull, hasLength(1));
    });

    test('removeFromIndex drops the entry', () async {
      await indexAll(<Document>[
        documentWith(id: 'a', title: 'Gone', pageTexts: <String>['findable']),
      ]);

      await repository.removeFromIndex('a');

      expect(index.documentCount, 0);
      expect((await repository.search('findable')).valueOrNull, isEmpty);
    });

    test('removing an id that was never indexed succeeds', () async {
      final result = await repository.removeFromIndex('never-there');

      expect(result.isSuccess, isTrue);
    });

    test('rebuildIndex replaces the whole index and stamps the version',
        () async {
      await repository.indexDocument(
        documentWith(id: 'stale', title: 'Stale', pageTexts: <String>['old']),
      );

      final library = <Document>[
        documentWith(id: 'a', title: 'Alpha', pageTexts: <String>['alpha text']),
        documentWith(id: 'b', title: 'Beta', pageTexts: <String>['beta text']),
      ];
      for (final document in library) {
        documents.seed(document);
      }

      await repository.rebuildIndex(library);

      expect(index.documentCount, 2);
      expect(index.isCurrentVersion, isTrue);
      expect((await repository.search('old')).valueOrNull, isEmpty);
      expect((await repository.search('alpha')).valueOrNull, hasLength(1));
    });

    test('reports a document-repository failure during search', () async {
      await indexAll(<Document>[
        documentWith(id: 'a', title: 'X', pageTexts: <String>['findable']),
      ]);
      documents.getFailure = const StorageFailure('Box is locked.');

      final result = await repository.search('findable');

      expect(result.failureOrNull, isA<StorageFailure>());
    });
  });

  group('SearchHit', () {
    test('scores are comparable within one result set', () async {
      await indexAll(<Document>[
        documentWith(id: 'a', title: 'Rent', pageTexts: <String>['rent rent']),
        documentWith(
          id: 'b',
          title: 'Other',
          pageTexts: <String>['rent mentioned once among many other words'],
        ),
      ]);

      final hits = (await repository.search('rent')).valueOrNull!;

      expect(hits, hasLength(2));
      expect(hits.first.score, greaterThan(hits.last.score));
      expect(hits.map((SearchHit hit) => hit.score).every((s) => s > 0), isTrue);
    });
  });
}
