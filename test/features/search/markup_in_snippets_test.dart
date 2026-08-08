import 'dart:io';

import 'package:docuai/hive_registrar.g.dart';
import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/core/text/markup.dart';
import 'package:docuai/src/features/documents/data/datasources/document_local_data_source.dart';
import 'package:docuai/src/features/documents/data/models/document_model.dart';
import 'package:docuai/src/features/documents/data/repositories/document_repository_impl.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/documents/domain/repositories/document_repository.dart';
import 'package:docuai/src/features/search/data/datasources/search_index_local_data_source.dart';
import 'package:docuai/src/features/search/data/repositories/bm25_search_repository.dart';
import 'package:docuai/src/features/search/domain/entities/search_hit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

/// Search results must read as prose, with the match still under the highlight.
///
/// The trap this guards is subtle and silent. A snippet carries
/// `highlightStart`/`highlightLength` *into the string it renders*, so removing
/// characters after those numbers are worked out slides the highlight along the
/// line by exactly the count of markers ahead of it. Nothing crashes; the wrong
/// words are simply emphasised. So the offsets are recalculated against the
/// final displayed text rather than the text they were found in.
void main() {
  late Directory tempDir;
  late Box<DocumentModel> box;
  late Box<dynamic> indexBox;
  late DocumentRepository documents;
  late Bm25SearchRepository search;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_snippet_markup');
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

  Future<Document> seed(
    String pageText, {
    String id = 'note',
    String title = 'Notes',
    List<String> tags = const <String>[],
  }) async {
    final document = Document(
      id: id,
      title: title,
      createdAt: DateTime.utc(2026, 8, 1),
      updatedAt: DateTime.utc(2026, 8, 1),
      tags: tags,
      source: DocumentSource.created,
      pages: <DocumentPage>[
        DocumentPage(
          id: '$id-p0',
          index: 0,
          text: pageText,
          ocrStatus: OcrStatus.completed,
          kind: PageKind.text,
        ),
      ],
    );

    await documents.saveDocument(document);
    await search.indexDocument(document);
    return document;
  }

  Future<SearchSnippet> snippetFor(String query) async {
    final hits = (await search.search(query)).valueOrNull!;
    expect(hits, isNotEmpty, reason: 'nothing matched "$query"');
    final snippet = hits.first.bestSnippet;
    expect(snippet, isNotNull, reason: 'no snippet for "$query"');
    return snippet!;
  }

  /// The text actually under the highlight.
  String highlighted(SearchSnippet snippet) {
    expect(
      snippet.hasValidHighlight,
      isTrue,
      reason: 'the highlight range fell outside "${snippet.text}"',
    );
    return snippet.text.substring(
      snippet.highlightStart,
      snippet.highlightEnd,
    );
  }

  void expectNoMarkers(SearchSnippet snippet) {
    expect(
      snippet.text,
      isNot(contains('**')),
      reason: 'raw markup reached the result list: "${snippet.text}"',
    );
    expect(RegExp(r'(^|\s)#{1,3}\s').hasMatch(snippet.text), isFalse);
    expect(RegExp(r'(^|\s)[-•]\s').hasMatch(snippet.text), isFalse);
  }

  group('bold', () {
    test('is shown as plain words', () async {
      await seed('The **deposit** is 500.00 EUR and refundable.');

      final snippet = await snippetFor('deposit');

      expectNoMarkers(snippet);
      expect(snippet.text, contains('The deposit is 500.00 EUR'));
    });

    test('the highlight lands on the word, not beside it', () async {
      // Two markers sit before the match. Stripping after the offsets were
      // computed would push the highlight two characters to the right.
      await seed('The **deposit** is 500.00 EUR.');

      expect(highlighted(await snippetFor('deposit')), 'deposit');
    });

    test('a match after several bold runs is still located', () async {
      await seed('**One** and **two** and **three** then the deposit.');

      expect(highlighted(await snippetFor('deposit')), 'deposit');
    });
  });

  group('italic', () {
    test('is shown as plain words, highlight intact', () async {
      await seed('Payment was *late* and the deposit was withheld.');

      final snippet = await snippetFor('deposit');

      expect(snippet.text, contains('Payment was late'));
      expect(highlighted(snippet), 'deposit');
    });

    test('underscores behave the same', () async {
      await seed('Payment was _late_ and the deposit was withheld.');

      final snippet = await snippetFor('deposit');

      expect(snippet.text, contains('was late and'));
      expect(highlighted(snippet), 'deposit');
    });
  });

  group('headings', () {
    test('the hashes do not appear', () async {
      await seed('# Tenancy agreement\nThe deposit is 500.00 EUR.');

      final snippet = await snippetFor('deposit');

      expectNoMarkers(snippet);
      expect(snippet.text, contains('Tenancy agreement'));
      expect(highlighted(snippet), 'deposit');
    });

    test('a match inside the heading itself is highlighted', () async {
      await seed('## Deposit summary\nOther text entirely.');

      expect(highlighted(await snippetFor('deposit')), 'Deposit');
    });
  });

  group('bullets and numbered lists', () {
    test('the markers do not appear', () async {
      await seed('- The deposit is 500.00 EUR\n- Rent is monthly');

      final snippet = await snippetFor('deposit');

      expectNoMarkers(snippet);
      expect(highlighted(snippet), 'deposit');
    });

    test('a numbered item loses its marker but keeps its words', () async {
      await seed('1. Return the keys\n2. Reclaim the deposit');

      final snippet = await snippetFor('deposit');

      expect(snippet.text, contains('Return the keys'));
      expect(snippet.text, isNot(contains('1.')));
      expect(highlighted(snippet), 'deposit');
    });

    test('a quote marker is removed', () async {
      await seed('> The deposit is held in escrow.');

      final snippet = await snippetFor('deposit');

      expect(snippet.text.trimLeft(), startsWith('The deposit'));
      expect(highlighted(snippet), 'deposit');
    });
  });

  group('mixed markup', () {
    test('every marker goes and the highlight still lands', () async {
      await seed(
        '# Tenancy\n'
        '- The **deposit** is *500.00 EUR*\n'
        '> Signed on 12/03/2026\n'
        '1. Return the keys',
      );

      final snippet = await snippetFor('deposit');

      expectNoMarkers(snippet);
      expect(highlighted(snippet), 'deposit');
      expect(snippet.text, contains('500.00 EUR'));
    });

    test('a match late in a heavily marked-up page is located', () async {
      await seed(
        '# One\n## Two\n- **a** *b* _c_\n1. **d**\n> **e**\nThe deposit here.',
      );

      expect(highlighted(await snippetFor('deposit')), 'deposit');
    });
  });

  group('exact phrase search', () {
    test('still ranks above scattered words', () async {
      await seed(
        'The **total amount due** is 248.60 EUR.',
        id: 'exact',
        title: 'Statement',
      );
      await seed(
        'The amount was agreed. Payment is due in total by March.',
        id: 'scattered',
        title: 'Letter',
      );

      final hits = (await search.search('total amount due')).valueOrNull!;

      expect(hits.first.document.id, 'exact');
      expect(hits.first.kind, SearchMatchKind.exactPhrase);
    });

    test('the highlight covers the whole phrase, markers removed', () async {
      await seed('The **total amount due** is 248.60 EUR.');

      final snippet = await snippetFor('total amount due');

      expect(highlighted(snippet), 'total amount due');
      expectNoMarkers(snippet);
    });

    test('a phrase whose markers fall inside it still highlights whole', () async {
      // The phrase pattern treats `*` as a separator, so the matched span in
      // the source includes the markers. Both ends map onto the text.
      await seed('The total **amount** due is 248.60 EUR.');

      expect(highlighted(await snippetFor('total amount due')),
          'total amount due');
    });
  });

  group('ranking is untouched', () {
    test('title, content and tag tiers still order as before', () async {
      await seed('nothing here', id: 'title-exact', title: 'Deposit');
      await seed(
        'The **deposit** is 500.00 EUR.',
        id: 'body',
        title: 'Statement',
      );
      await seed(
        'nothing relevant',
        id: 'tagged',
        title: 'Receipt',
        tags: <String>['deposit'],
      );

      final hits = (await search.search('deposit')).valueOrNull!;

      expect(hits.first.kind, SearchMatchKind.exactTitle);
      expect(hits.last.kind, SearchMatchKind.tag);
      expect(
        hits.map((hit) => hit.kind.priority),
        orderedEquals(hits.map((hit) => hit.kind.priority).toList()..sort()),
      );
    });

    test('a marked-up document is found by the same query as a plain one', () async {
      await seed('The **deposit** is 500.00 EUR.', id: 'marked');
      await seed('The deposit is 500.00 EUR.', id: 'plain', title: 'Plain');

      final ids = (await search.search(
        'deposit',
      )).valueOrNull!.map((hit) => hit.document.id);

      expect(ids, containsAll(<String>['marked', 'plain']));
    });
  });

  group('ordinary recognised text', () {
    const recognised =
        'Northwind Utilities\n'
        'Account number: NW-4471902\n'
        'Total amount due: 248.60 EUR';

    test('is displayed exactly as it was recognised', () async {
      await seed(recognised, title: 'Electricity bill');

      final snippet = await snippetFor('northwind');

      // A snippet is a window, so it may be cut short and marked with an
      // ellipsis. What must hold is that every character it does show is one
      // the page had — newlines becoming spaces is the only permitted change.
      expect(
        recognised.replaceAll('\n', ' '),
        contains(snippet.text.replaceAll('…', '')),
      );
      expect(highlighted(snippet), 'Northwind');
    });

    test('a document with no markers is byte-identical through the stripper', () {
      expect(Markup.strip(recognised).text, recognised);
    });

    test('a stray asterisk from a scan is kept', () async {
      await seed('Rate is 2 * 3 per unit for the deposit.');

      final snippet = await snippetFor('deposit');

      expect(snippet.text, contains('2 * 3'));
      expect(highlighted(snippet), 'deposit');
    });
  });

  group('the offset map itself', () {
    test('maps every index without going out of range', () {
      const sources = <String>[
        '',
        'plain text',
        '**bold**',
        '# heading',
        '- bullet\n1. numbered\n> quote',
        '**a** *b* _c_ ****',
        'Total amount due: 248.60 EUR',
      ];

      for (final source in sources) {
        final stripped = Markup.strip(source);

        expect(stripped.offsets, hasLength(source.length + 1));
        for (final offset in stripped.offsets) {
          expect(offset, inInclusiveRange(0, stripped.text.length));
        }
        expect(stripped.offsets.last, stripped.text.length);
      }
    });

    test('offsets never move backwards', () {
      final stripped = Markup.strip('# H\n- **a** and *b* then c');

      for (var i = 1; i < stripped.offsets.length; i++) {
        expect(
          stripped.offsets[i],
          greaterThanOrEqualTo(stripped.offsets[i - 1]),
          reason: 'the map must be monotonic to be usable as a range',
        );
      }
    });

    test('a range that survives stripping maps onto the same words', () {
      const source = 'The **deposit** is due';
      final stripped = Markup.strip(source);

      final start = source.indexOf('deposit');
      final (from, to) = stripped.mapRange(start, start + 'deposit'.length);

      expect(stripped.text.substring(from, to), 'deposit');
    });

    test('an out-of-range request is clamped rather than throwing', () {
      final stripped = Markup.strip('short');

      expect(() => stripped.mapRange(-5, 500), returnsNormally);
    });
  });

  test('every snippet a search produces has a valid highlight', () async {
    // The range is used with `substring` inside a build; one bad value takes
    // down the whole results list rather than a single row.
    await seed(
      '# Tenancy\n- The **deposit** is *500.00 EUR*\n> Signed 12/03/2026',
      id: 'a',
    );
    await seed('Plain recognised text about a deposit.', id: 'b', title: 'B');

    for (final query in <String>[
      'deposit',
      'tenancy',
      'signed',
      '500.00',
      'the deposit is',
    ]) {
      for (final hit in (await search.search(query)).valueOrNull!) {
        for (final snippet in hit.snippets) {
          expect(
            snippet.hasValidHighlight,
            isTrue,
            reason: '"$query" produced an invalid range in "${snippet.text}"',
          );
        }
      }
    }
  });
}
