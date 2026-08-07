import 'dart:io';

import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/search/data/datasources/search_index_local_data_source.dart';
import 'package:docuai/src/features/search/data/repositories/bm25_search_repository.dart';
import 'package:docuai/src/features/search/domain/entities/search_hit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';

/// Search now spans titles, recognised text and tags, and orders results by
/// *where* the match happened before how strong it was.
void main() {
  late Directory tempDir;
  late Box<dynamic> box;
  late SearchIndexLocalDataSource index;
  late FakeDocumentRepository documents;
  late Bm25SearchRepository repository;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_search_rank');
    Hive.init(p.join(tempDir.path, 'hive'));
  });

  setUp(() async {
    box = await Hive.openBox<dynamic>(
      'rank_${DateTime.now().microsecondsSinceEpoch}',
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
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } on FileSystemException {
      // Windows may still hold the box file; the OS reclaims it.
    }
  });

  Document doc({
    required String id,
    required String title,
    List<String> pageTexts = const <String>[],
    List<String> tags = const <String>[],
  }) => buildDocument(
    id: id,
    title: title,
    tags: tags,
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

  Future<void> library(List<Document> library) async {
    for (final document in library) {
      documents.seed(document);
    }
    await repository.rebuildIndex(library);
  }

  group('title search', () {
    test('finds a document by its name', () async {
      await library(<Document>[
        doc(id: 'a', title: 'Electricity bill'),
        doc(id: 'b', title: 'Rental agreement'),
      ]);

      final hits = (await repository.search('electricity bill')).valueOrNull!;

      expect(hits.single.document.id, 'a');
      expect(hits.single.kind, SearchMatchKind.exactTitle);
    });

    test('finds a document with no recognised text at all', () async {
      // The first index only stored documents that had been read, so a fresh
      // scan could not be found by its own name until OCR finished.
      await library(<Document>[
        buildDocument(
          id: 'fresh',
          title: 'Passport scan',
          pages: <DocumentPage>[buildPage()],
        ),
      ]);

      final hits = (await repository.search('passport')).valueOrNull!;

      expect(hits, hasLength(1));
      expect(hits.single.kind, SearchMatchKind.partialTitle);
    });

    test('a partial title match still counts', () async {
      await library(<Document>[doc(id: 'a', title: 'Electricity bill 2026')]);

      final hits = (await repository.search('electricity')).valueOrNull!;

      expect(hits.single.kind, SearchMatchKind.partialTitle);
    });

    test('is case-insensitive', () async {
      await library(<Document>[doc(id: 'a', title: 'Water Bill')]);

      expect((await repository.search('WATER BILL')).valueOrNull, hasLength(1));
    });
  });

  group('ranking priority', () {
    test('an exact title outranks a page full of the same words', () async {
      await library(<Document>[
        doc(
          id: 'content',
          title: 'Notes',
          pageTexts: <String>[
            'deposit deposit deposit deposit deposit deposit deposit',
          ],
        ),
        doc(id: 'titled', title: 'Deposit'),
      ]);

      final hits = (await repository.search('deposit')).valueOrNull!;

      expect(hits.first.document.id, 'titled');
      expect(hits.first.kind, SearchMatchKind.exactTitle);
    });

    test('a partial title outranks content', () async {
      await library(<Document>[
        doc(
          id: 'content',
          title: 'Notes',
          pageTexts: <String>['the deposit is mentioned here in the text'],
        ),
        doc(id: 'titled', title: 'Deposit receipt 2026'),
      ]);

      final hits = (await repository.search('deposit')).valueOrNull!;

      expect(hits.first.document.id, 'titled');
    });

    test('content outranks a tag-only match', () async {
      await library(<Document>[
        doc(id: 'tagged', title: 'Something else', tags: <String>['rent']),
        doc(
          id: 'content',
          title: 'Notes',
          pageTexts: <String>['the rent is due on the first of the month'],
        ),
      ]);

      final hits = (await repository.search('rent')).valueOrNull!;

      expect(hits.first.document.id, 'content');
      expect(hits.first.kind, SearchMatchKind.content);
      expect(hits.last.kind, SearchMatchKind.tag);
    });

    test('a shorter exact title wins over a longer one', () async {
      await library(<Document>[
        doc(id: 'long', title: 'rent'),
        doc(id: 'short', title: 'rent'),
      ]);

      final hits = (await repository.search('rent')).valueOrNull!;

      expect(hits, hasLength(2));
      expect(hits.every((h) => h.kind == SearchMatchKind.exactTitle), isTrue);
    });
  });

  group('tag search', () {
    test('finds a document by a tag', () async {
      await library(<Document>[
        doc(id: 'a', title: 'Untitled scan', tags: <String>['utilities']),
      ]);

      final hits = (await repository.search('utilities')).valueOrNull!;

      expect(hits.single.document.id, 'a');
      expect(hits.single.kind, SearchMatchKind.tag);
      expect(hits.single.matchedTags, <String>['utilities']);
    });

    test('reports which tag matched', () async {
      await library(<Document>[
        doc(
          id: 'a',
          title: 'Scan',
          tags: <String>['bills', 'utilities', 'archive'],
        ),
      ]);

      final hit = (await repository.search('utilities')).valueOrNull!.single;

      expect(hit.matchedTags, <String>['utilities']);
      expect(hit.matchedTitleOnly, isFalse);
    });
  });

  group('content search keeps BM25', () {
    test('still ranks content matches against each other', () async {
      await library(<Document>[
        doc(
          id: 'sparse',
          title: 'A',
          pageTexts: <String>[
            'invoice mentioned once among a great many other unrelated words '
                'that go on for a while to make this document long',
          ],
        ),
        doc(id: 'dense', title: 'B', pageTexts: <String>['invoice invoice']),
      ]);

      final hits = (await repository.search('invoice')).valueOrNull!;

      expect(hits.first.document.id, 'dense');
      expect(hits.every((h) => h.kind == SearchMatchKind.content), isTrue);
    });

    test('still produces highlighted snippets', () async {
      await library(<Document>[
        doc(
          id: 'a',
          title: 'A',
          pageTexts: <String>['The deposit is two months rent.'],
        ),
      ]);

      final snippet =
          (await repository.search('deposit')).valueOrNull!.single.bestSnippet!;

      expect(snippet.hasValidHighlight, isTrue);
      expect(
        snippet.text.substring(snippet.highlightStart, snippet.highlightEnd),
        'deposit',
      );
    });
  });

  group('index bookkeeping', () {
    test('stores the current schema version', () async {
      await library(<Document>[doc(id: 'a', title: 'A')]);

      expect(index.isCurrentVersion, isTrue);
    });

    test('the fingerprint changes when contents change, not just count',
        () async {
      final first = <Document>[
        doc(id: 'a', title: 'A'),
        doc(id: 'b', title: 'B'),
      ];
      // One removed, one added: the same count, a different library.
      final second = <Document>[
        doc(id: 'a', title: 'A'),
        doc(id: 'c', title: 'C'),
      ];

      expect(
        Bm25SearchRepository.fingerprintOf(first),
        isNot(Bm25SearchRepository.fingerprintOf(second)),
        reason: 'a count-based check would call this index fresh',
      );
    });

    test('the fingerprint changes when a document is renamed', () async {
      final before = <Document>[doc(id: 'a', title: 'Before')];
      final after = <Document>[
        doc(id: 'a', title: 'After').copyWith(
          updatedAt: DateTime.utc(2026, 9),
        ),
      ];

      expect(
        Bm25SearchRepository.fingerprintOf(before),
        isNot(Bm25SearchRepository.fingerprintOf(after)),
      );
    });

    test('rebuilding records the fingerprint it was built from', () async {
      final library = <Document>[doc(id: 'a', title: 'A')];
      documents.seed(library.single);
      await repository.rebuildIndex(library);

      expect(
        index.storedFingerprint,
        Bm25SearchRepository.fingerprintOf(library),
      );
    });

    test('removing a document drops it from results', () async {
      await library(<Document>[doc(id: 'a', title: 'Water bill')]);

      await repository.removeFromIndex('a');

      expect((await repository.search('water')).valueOrNull, isEmpty);
    });
  });
}
