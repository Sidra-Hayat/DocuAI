import 'dart:io';

import 'package:docuai/hive_registrar.g.dart';
import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/features/documents/data/datasources/document_local_data_source.dart';
import 'package:docuai/src/features/documents/data/models/document_model.dart';
import 'package:docuai/src/features/documents/data/repositories/document_repository_impl.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/documents/domain/repositories/document_repository.dart';
import 'package:docuai/src/features/documents/domain/usecases/create_text_document.dart';
import 'package:docuai/src/features/documents/domain/usecases/edit_page_text.dart';
import 'package:docuai/src/features/search/data/datasources/search_index_local_data_source.dart';
import 'package:docuai/src/features/search/data/repositories/bm25_search_repository.dart';
import 'package:docuai/src/features/search/domain/entities/search_hit.dart';
import 'package:docuai/src/features/search/domain/usecases/search_documents.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

/// One search over everything the app holds.
///
/// The claim is that a title, recognised text, a correction, something typed
/// from scratch and a tag are all reachable from the same box — and that where
/// a match happened decides the order before how strongly it scored.
///
/// This is *finding*, not answering. The assistant reads a document and replies;
/// search points at documents and shows why. Nothing here asks a question.
void main() {
  late Directory tempDir;
  late Box<DocumentModel> box;
  late Box<dynamic> indexBox;
  late DocumentRepository documents;
  late Bm25SearchRepository search;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_unified_search');
    Hive.init(p.join(tempDir.path, 'hive'));
    Hive.registerAdapters();
  });

  setUp(() async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    box = await Hive.openBox<DocumentModel>('docs_$stamp');
    indexBox = await Hive.openBox<dynamic>('index_$stamp');
    documents = DocumentRepositoryImpl(
      DocumentLocalDataSource(box: box, paths: StoragePaths(tempDir)),
    );
    search = Bm25SearchRepository(
      index: SearchIndexLocalDataSource(indexBox),
      documents: documents,
    );
  });

  tearDown(() async {
    if (box.isOpen) await box.deleteFromDisk();
    if (indexBox.isOpen) await indexBox.deleteFromDisk();
  });

  tearDownAll(() async {
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } on FileSystemException {
      // Windows may still hold a box file; the OS reclaims it.
    }
  });

  /// A document written straight into storage, then indexed — the state every
  /// document reaches once recognition or an edit has run.
  Future<Document> seed({
    required String id,
    required String title,
    List<String> pageTexts = const <String>[],
    List<String> tags = const <String>[],
    bool asText = false,
  }) async {
    final document = Document(
      id: id,
      title: title,
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
      tags: tags,
      source: asText ? DocumentSource.created : DocumentSource.scanned,
      pages: <DocumentPage>[
        for (var i = 0; i < pageTexts.length; i++)
          DocumentPage(
            id: '$id-p$i',
            imagePath: asText ? null : 'documents/$id/page_$i.jpg',
            index: i,
            text: pageTexts[i],
            ocrStatus: OcrStatus.completed,
            kind: asText ? PageKind.text : PageKind.scanned,
          ),
      ],
    );

    await documents.saveDocument(document);
    await search.indexDocument(document);
    return document;
  }

  Future<List<SearchHit>> find(String query) async =>
      (await SearchDocuments(search)(query)).valueOrNull!;

  Future<List<String>> idsFor(String query) async =>
      (await find(query)).map((hit) => hit.document.id).toList();

  group('one word', () {
    test('finds a document by a word in its recognised text', () async {
      await seed(
        id: 'bill',
        title: 'Electricity bill',
        pageTexts: <String>['Standing charge for the quarter: 54.20 EUR'],
      );

      expect(await idsFor('standing'), <String>['bill']);
    });

    test('finds a document by its title', () async {
      await seed(id: 'lease', title: 'Tenancy agreement');

      expect(await idsFor('tenancy'), <String>['lease']);
    });

    test('finds a document by a tag', () async {
      await seed(id: 'bill', title: 'Untitled', tags: <String>['utilities']);

      final hits = await find('utilities');
      expect(hits.single.document.id, 'bill');
      expect(hits.single.matchedTags, contains('utilities'));
    });

    test('a word in nothing returns nothing', () async {
      await seed(id: 'bill', title: 'Electricity bill');

      expect(await idsFor('kangaroo'), isEmpty);
    });

    test('matching ignores case', () async {
      await seed(
        id: 'bill',
        title: 'Electricity bill',
        pageTexts: <String>['NORTHWIND UTILITIES'],
      );

      expect(await idsFor('northwind'), <String>['bill']);
    });
  });

  group('several words', () {
    test('all of them scattered across a page still matches', () async {
      await seed(
        id: 'lease',
        title: 'Agreement',
        pageTexts: <String>[
          'The deposit is held by the agent. It is returned on inspection.',
        ],
      );

      expect(await idsFor('deposit inspection'), <String>['lease']);
    });

    test('one of them matching is enough to be found', () async {
      await seed(
        id: 'lease',
        title: 'Agreement',
        pageTexts: <String>['The deposit is two months rent.'],
      );

      expect(await idsFor('deposit kangaroo'), <String>['lease']);
    });
  });

  group('phrases and sentences', () {
    setUp(() async {
      await seed(
        id: 'exact',
        title: 'Statement',
        pageTexts: <String>['The total amount due is 248.60 EUR.'],
      );
      await seed(
        id: 'scattered',
        title: 'Notes',
        pageTexts: <String>[
          'The amount was agreed. Payment is due in total by March. '
              'A further amount is due on completion, in total.',
        ],
      );
    });

    test('the document saying it word-for-word ranks above the one that '
        'merely uses the words', () async {
      final hits = await find('total amount due');

      expect(hits.first.document.id, 'exact');
      expect(hits.first.kind, SearchMatchKind.exactPhrase);
      expect(hits.map((hit) => hit.document.id), contains('scattered'));
      expect(hits.last.kind, SearchMatchKind.content);
    });

    test('a partial phrase matches too', () async {
      final hits = await find('amount due');

      expect(hits.first.document.id, 'exact');
      expect(hits.first.kind, SearchMatchKind.exactPhrase);
    });

    test('a phrase split by punctuation or a line break still matches', () async {
      await seed(
        id: 'wrapped',
        title: 'Wrapped',
        pageTexts: <String>['Total amount\ndue: 100.00'],
      );

      final hits = await find('total amount due');
      expect(
        hits.map((hit) => hit.document.id),
        contains('wrapped'),
      );
      expect(
        hits.firstWhere((hit) => hit.document.id == 'wrapped').kind,
        SearchMatchKind.exactPhrase,
      );
    });

    test('words separated by other words are not a phrase', () async {
      // "amount, but due" must not read as "amount due", or the tier means
      // nothing.
      await seed(
        id: 'interrupted',
        title: 'Interrupted',
        pageTexts: <String>['The amount, which was agreed, is due shortly.'],
      );

      final hit = (await find(
        'amount due',
      )).firstWhere((hit) => hit.document.id == 'interrupted');

      expect(hit.kind, SearchMatchKind.content);
    });

    test('a single word is never treated as a phrase', () async {
      final hits = await find('amount');

      expect(
        hits.every((hit) => hit.kind != SearchMatchKind.exactPhrase),
        isTrue,
        reason: 'one word is a term, and promoting it would flatten the tiers',
      );
    });

    test('a whole sentence finds the page it came from', () async {
      final hits = await find('The total amount due is 248.60 EUR.');

      expect(hits.first.document.id, 'exact');
      expect(hits.first.kind, SearchMatchKind.exactPhrase);
    });
  });

  group('ranking order', () {
    setUp(() async {
      await seed(id: 'title-exact', title: 'Deposit');
      await seed(id: 'title-partial', title: 'Deposit and rent summary');
      await seed(
        id: 'phrase',
        title: 'Statement',
        pageTexts: <String>['The deposit is 500.00 EUR.'],
      );
      await seed(
        id: 'body',
        title: 'Letter',
        pageTexts: <String>[
          'A deposit was mentioned. The sum is held until the end.',
        ],
      );
      await seed(id: 'tagged', title: 'Receipt', tags: <String>['deposit']);
    });

    test('title beats everything else for a one-word query', () async {
      final hits = await find('deposit');

      expect(hits.first.document.id, 'title-exact');
      expect(hits.first.kind, SearchMatchKind.exactTitle);
      expect(hits[1].document.id, 'title-partial');
      expect(hits[1].kind, SearchMatchKind.partialTitle);
    });

    test('the tiers come out in the order they are declared', () async {
      final hits = await find('deposit is 500');

      final kinds = hits.map((hit) => hit.kind).toList();
      final sorted = List<SearchMatchKind>.of(kinds)
        ..sort((a, b) => a.priority.compareTo(b.priority));

      expect(kinds, sorted, reason: 'results must never be out of tier order');
    });

    test('a tag match is last, behind anything in the text', () async {
      final hits = await find('deposit');

      expect(hits.last.document.id, 'tagged');
      expect(hits.last.kind, SearchMatchKind.tag);
    });
  });

  group('everywhere text can come from', () {
    test('recognised text', () async {
      await seed(
        id: 'scan',
        title: 'Bill',
        pageTexts: <String>['Meter reading taken on 12/03/2026.'],
      );

      expect(await idsFor('meter reading'), <String>['scan']);
    });

    test('text a person corrected', () async {
      // The correction has to replace what OCR read, in the index as well as
      // on the page — otherwise search answers with the typo.
      final scan = await seed(
        id: 'scan',
        title: 'Bill',
        pageTexts: <String>['T0tal amaunt due 5OO.OO EUR'],
      );

      await EditPageText(documents: documents, search: search)(
        documentId: scan.id,
        pageId: scan.pages.single.id,
        text: 'Total amount due 500.00 EUR',
      );

      expect(await idsFor('amaunt'), isEmpty);
      expect(await idsFor('amount'), <String>['scan']);
    });

    test('text written from scratch', () async {
      final note = (await CreateTextDocument(documents)(
        title: 'Meeting notes',
      )).valueOrNull!;

      await EditPageText(documents: documents, search: search)(
        documentId: note.id,
        pageId: note.pages.single.id,
        text: 'Agreed to renew the boiler contract in March.',
      );

      final hits = await find('boiler contract');
      expect(hits.single.document.id, note.id);
      expect(hits.single.kind, SearchMatchKind.exactPhrase);
    });

    test('a mixed document is searchable through either kind of page', () async {
      final note = await seed(
        id: 'mixed',
        title: 'Lease and notes',
        pageTexts: <String>['Recognised from the scan.'],
      );

      await documents.saveDocument(
        note.copyWith(
          pages: <DocumentPage>[
            note.pages.single,
            const DocumentPage(
              id: 'mixed-t',
              index: 1,
              text: 'Typed afterwards.',
              ocrStatus: OcrStatus.completed,
              kind: PageKind.text,
            ),
          ],
        ),
      );
      await search.indexDocument(
        (await documents.getDocument('mixed')).valueOrNull!,
      );

      expect(await idsFor('recognised'), <String>['mixed']);
      expect(await idsFor('typed'), <String>['mixed']);
    });
  });

  group('several documents at once', () {
    test('every document containing the word is returned', () async {
      await seed(
        id: 'a',
        title: 'One',
        pageTexts: <String>['The deposit is held.'],
      );
      await seed(
        id: 'b',
        title: 'Two',
        pageTexts: <String>['A deposit was paid on Monday.'],
      );
      await seed(
        id: 'c',
        title: 'Three',
        pageTexts: <String>['Nothing relevant at all.'],
      );

      final ids = await idsFor('deposit');

      expect(ids, hasLength(2));
      expect(ids, containsAll(<String>['a', 'b']));
      expect(ids, isNot(contains('c')));
    });
  });

  group('what a result shows', () {
    test('the page a match came from, and a snippet of it', () async {
      await seed(
        id: 'bill',
        title: 'Electricity bill',
        pageTexts: <String>[
          'Nothing on this page.',
          'The standing charge for the quarter is 54.20 EUR.',
        ],
      );

      final hit = (await find('standing charge')).single;

      expect(hit.document.title, 'Electricity bill');
      final snippet = hit.bestSnippet!;
      expect(snippet.pageIndex, 1, reason: 'the page that actually matched');
      expect(snippet.text, contains('standing charge'));
    });

    test('the highlight covers the phrase, not one word of it', () async {
      await seed(
        id: 'bill',
        title: 'Bill',
        pageTexts: <String>['The total amount due is 248.60 EUR.'],
      );

      final snippet = (await find('total amount due')).single.bestSnippet!;

      expect(snippet.hasValidHighlight, isTrue);
      expect(
        snippet.text.substring(snippet.highlightStart, snippet.highlightEnd),
        'total amount due',
      );
    });

    test('the highlight lands on the term when there is no phrase', () async {
      await seed(
        id: 'bill',
        title: 'Bill',
        pageTexts: <String>['The standing charge is 54.20 EUR.'],
      );

      final snippet = (await find('charge')).single.bestSnippet!;

      expect(
        snippet.text
            .substring(snippet.highlightStart, snippet.highlightEnd)
            .toLowerCase(),
        'charge',
      );
    });

    test('a highlight range is always inside the snippet it indexes', () async {
      // A range past the end throws a RangeError inside a build, which takes
      // the whole results list down rather than one row.
      await seed(
        id: 'long',
        title: 'Long',
        pageTexts: <String>[
          '${'padding words ' * 40}the total amount due is here'
              '${' trailing words' * 40}',
        ],
      );

      for (final query in <String>['total amount due', 'padding', 'trailing']) {
        for (final hit in await find(query)) {
          for (final snippet in hit.snippets) {
            expect(snippet.hasValidHighlight, isTrue, reason: query);
          }
        }
      }
    });

    test('a title match with no text still returns a usable row', () async {
      await seed(id: 'empty', title: 'Passport');

      final hit = (await find('passport')).single;

      expect(hit.snippets, isEmpty);
      expect(hit.matchedTitleOnly, isTrue);
      expect(hit.document.title, 'Passport');
    });
  });

  group('queries that ask for nothing', () {
    test('one character is not a search', () async {
      await seed(id: 'bill', title: 'Bill');

      expect(await idsFor('a'), isEmpty);
    });

    test('punctuation alone is not a search', () async {
      await seed(id: 'bill', title: 'Bill');

      expect(await idsFor('...'), isEmpty);
    });
  });
}
