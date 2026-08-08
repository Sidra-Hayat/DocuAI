import 'dart:io';

import 'package:docuai/hive_registrar.g.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/core/text/markup.dart';
import 'package:docuai/src/features/assistant/data/datasources/chat_history_local_data_source.dart';
import 'package:docuai/src/features/assistant/data/datasources/passage_extractor.dart';
import 'package:docuai/src/features/assistant/data/datasources/passage_ranker.dart';
import 'package:docuai/src/features/assistant/data/datasources/question_analyzer.dart';
import 'package:docuai/src/features/assistant/data/models/chat_message_model.dart';
import 'package:docuai/src/features/assistant/data/repositories/retrieval_assistant_repository.dart';
import 'package:docuai/src/features/assistant/domain/entities/assistant_answer.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/search/domain/entities/search_hit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';

/// Formatting markers must never reach the reader.
///
/// The constraint that shapes the fix: stripping has to happen at the *last*
/// step, when a string is about to be drawn. `Passage.start` and `end` index
/// into the stored page text, so removing characters any earlier moves every
/// offset behind them — and a citation would still look plausible while
/// pointing at the wrong span. Nothing stored, indexed or ranked changes here.
void main() {
  late Directory tempDir;
  late Box<ChatMessageModel> box;
  late FakeSearchRepository search;
  late FakeDocumentRepository documents;
  late RetrievalAssistantRepository repository;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_markup_answers');
    Hive.init(p.join(tempDir.path, 'hive'));
    Hive.registerAdapters();
  });

  setUp(() async {
    box = await Hive.openBox<ChatMessageModel>(
      'chat_${DateTime.now().microsecondsSinceEpoch}',
    );
    search = FakeSearchRepository();
    documents = FakeDocumentRepository();
    repository = RetrievalAssistantRepository(
      search: search,
      documents: documents,
      history: ChatHistoryLocalDataSource(box),
    );
  });

  tearDown(() async {
    if (box.isOpen) await box.deleteFromDisk();
    documents.dispose();
  });

  tearDownAll(() async {
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } on FileSystemException {
      // Windows may still hold the box file; the OS reclaims it.
    }
  });

  /// No marker character may survive into anything the user reads.
  void expectClean(String shown, {String? reason}) {
    expect(
      RegExp(r'(\*\*|^#{1,3}\s|\n#{1,3}\s|^\s*[-*]\s|\n\s*[-*]\s|^>\s|\n>\s)')
          .hasMatch(shown),
      isFalse,
      reason: reason ?? 'raw markup reached the reader: "$shown"',
    );
  }

  Document noteWith(String text, {String id = 'note', String title = 'Notes'}) =>
      buildDocument(
        id: id,
        title: title,
        source: DocumentSource.created,
        pages: <DocumentPage>[buildTextPage(id: '$id-p0', index: 0, text: text)],
      );

  Future<AssistantAnswer> ask(String question, {String? documentId}) async =>
      (await repository.ask(question, documentId: documentId)
              as Success<AssistantAnswer>)
          .value;

  group('the stripper itself', () {
    test('bold', () {
      expect(Markup.toInlineText('The **total** is due'), 'The total is due');
    });

    test('italic, in both spellings', () {
      expect(Markup.toInlineText('paid *late*'), 'paid late');
      expect(Markup.toInlineText('paid _late_'), 'paid late');
    });

    test('headings at every depth', () {
      expect(Markup.toInlineText('# Invoice'), 'Invoice');
      expect(Markup.toInlineText('## Totals'), 'Totals');
      expect(Markup.toInlineText('### Notes'), 'Notes');
    });

    test('bullets', () {
      expect(Markup.toInlineText('- deposit\n- rent'), 'deposit rent');
      expect(Markup.toInlineText('* deposit'), 'deposit');
    });

    test('numbered lists', () {
      expect(Markup.toInlineText('1. first\n2. second'), 'first second');
    });

    test('quotes', () {
      expect(Markup.toInlineText('> as agreed'), 'as agreed');
    });

    test('mixed markup in one run', () {
      expect(
        Markup.toInlineText(
          '# Invoice\n- **Total** 248.60 EUR\n> *as agreed*\n1. sign it',
        ),
        'Invoice Total 248.60 EUR as agreed sign it',
      );
    });

    test('ordinary recognised text is returned unchanged', () {
      // The path every existing scanned document takes. Anything else here
      // would mean this change altered documents it was never about.
      const recognised =
          'Northwind Utilities Account number: NW-4471902 '
          'Total amount due: 248.60 EUR';

      expect(Markup.toInlineText(recognised), recognised);
    });

    test('a stray asterisk in a scan is not treated as formatting', () {
      expect(Markup.toInlineText('2 * 3 = 6'), '2 * 3 = 6');
      expect(Markup.toInlineText('**unclosed'), '**unclosed');
    });
  });

  group('answers', () {
    test('a quoted answer contains no markers', () async {
      final note = noteWith(
        '# Tenancy\nThe **deposit** is *500.00 EUR* and is refundable.',
      );
      documents.seed(note);
      search.results = <SearchHit>[SearchHit(document: note, score: 5)];

      final answer = await ask('How much is the deposit?');

      expect(answer.kind, AnswerKind.grounded);
      expect(answer.text, contains('500.00 EUR'));
      expectClean(answer.text);
    });

    test('a summary contains no markers', () async {
      documents.seed(
        noteWith(
          '# Tenancy agreement\n'
          '- The **deposit** is 500.00 EUR.\n'
          '- Rent is due on the *first* of each month.\n'
          '> Signed on 12/03/2026.\n'
          '1. Return the keys on the final inspection.',
        ),
      );

      final answer = await ask('Summarise this document', documentId: 'note');

      expect(answer.kind, AnswerKind.summary);
      expectClean(answer.text.replaceAll('• ', ''));
      expect(answer.text, isNot(contains('**')));
    });

    test('an explanation contains no markers', () async {
      final note = noteWith('The **deposit** is *500.00 EUR*.');
      documents.seed(note);
      search.results = <SearchHit>[SearchHit(document: note, score: 5)];

      final answer = await ask(
        'Explain: The **deposit** is *500.00 EUR*.',
        documentId: 'note',
      );

      expect(answer.kind, AnswerKind.explanation);
      expect(answer.text, contains('deposit'));
      expect(answer.text, isNot(contains('**')));
    });

    test('a listed value is not wrapped in decoration', () async {
      documents.seed(
        noteWith('Total amount due: **248.60 EUR**\nPaid on **12/03/2026**'),
      );

      final amounts = await ask('Find amounts', documentId: 'note');
      final dates = await ask('Find important dates', documentId: 'note');

      expect(amounts.text, contains('248.60'));
      expect(amounts.text, isNot(contains('**')));
      expect(dates.text, contains('12/03/2026'));
      expect(dates.text, isNot(contains('**')));
    });
  });

  group('citations', () {
    test('the snippet is clean but still points at the right page', () async {
      documents.seed(
        buildDocument(
          id: 'mixed',
          title: 'Lease',
          pages: <DocumentPage>[
            buildPage(
              id: 'p0',
              index: 0,
              ocrStatus: OcrStatus.completed,
              text: 'Nothing relevant on this page at all.',
            ),
            buildTextPage(
              id: 'p1',
              index: 1,
              text: '## Deposit\nThe **deposit** is 500.00 EUR, refundable.',
            ),
          ],
        ),
      );
      search.results = <SearchHit>[
        SearchHit(document: documents.store['mixed']!, score: 5),
      ];

      final answer = await ask('How much is the deposit?');
      final citation = answer.citations.first;

      expect(citation.documentId, 'mixed');
      expect(
        citation.pageIndex,
        1,
        reason: 'stripping must not move which page a citation names',
      );
      expect(citation.snippet, contains('500.00 EUR'));
      expectClean(citation.snippet);
    });

    test('offsets still index into the stored text', () async {
      // The invariant the whole approach rests on: a passage's range is a
      // window into the *original* page, markers and all. If stripping had
      // happened before extraction these would no longer line up.
      final note = noteWith('# Heading\nThe **deposit** is 500.00 EUR.');
      final passages = PassageExtractor.extract(note);
      final stored = note.pages.single.text;

      for (final passage in passages) {
        expect(passage.end, lessThanOrEqualTo(stored.length));
        expect(
          stored.substring(passage.start, passage.end).trim(),
          passage.text,
          reason: 'a passage no longer matches the text it points at',
        );
      }
    });

    test('the stored document is never rewritten', () async {
      const original = '# Tenancy\nThe **deposit** is *500.00 EUR*.';
      final note = noteWith(original);
      documents.seed(note);
      search.results = <SearchHit>[SearchHit(document: note, score: 5)];

      await ask('How much is the deposit?');
      await ask('Summarise this document', documentId: 'note');

      expect(
        documents.store['note']!.pages.single.text,
        original,
        reason: 'display cleaning must not touch what is on disk',
      );
    });
  });

  group('retrieval is unaffected', () {
    test('a marked-up passage ranks exactly as the plain one does', () async {
      // The tokeniser splits on non-alphanumerics, so `**total**` and `total`
      // have always been the same term. This pins that, because a change here
      // would silently reorder every answer.
      const plain = 'The deposit is 500.00 EUR and is refundable.';
      const marked = 'The **deposit** is *500.00 EUR* and is refundable.';

      final question = QuestionAnalyzer.analyze('deposit refundable');

      double scoreOf(String text) => PassageRanker.rank(
        question: question,
        passages: PassageExtractor.extract(noteWith(text)),
        documentPriors: const <String, double>{'note': 1},
      ).first.score;

      expect(scoreOf(marked), closeTo(scoreOf(plain), 0.000001));
    });

    test('a question still finds a marked-up document', () async {
      final note = noteWith('The **deposit** is *500.00 EUR*.');
      documents.seed(note);
      search.results = <SearchHit>[SearchHit(document: note, score: 5)];

      final answer = await ask('deposit');

      expect(answer.kind, AnswerKind.grounded);
      expect(answer.citations, isNotEmpty);
    });
  });

  group('mixed and awkward input', () {
    test('a scan and a written page in one document both come out clean', () async {
      documents.seed(
        buildDocument(
          id: 'mixed',
          title: 'Lease and notes',
          pages: <DocumentPage>[
            buildPage(
              id: 'p0',
              index: 0,
              ocrStatus: OcrStatus.completed,
              text: 'Recognised text with no markers, total 248.60 EUR.',
            ),
            buildTextPage(
              id: 'p1',
              index: 1,
              text: '## Notes\n- **Check** the total again.',
            ),
          ],
        ),
      );

      final answer = await ask('Summarise this document', documentId: 'mixed');

      expectClean(answer.text.replaceAll('• ', ''));
      for (final citation in answer.citations) {
        expectClean(citation.snippet);
      }
    });

    test('half-typed markup does not lose the words around it', () async {
      final note = noteWith('The **deposit is 500.00 EUR and is refundable.');
      documents.seed(note);
      search.results = <SearchHit>[SearchHit(document: note, score: 5)];

      final answer = await ask('How much is the deposit?');

      expect(answer.text, contains('deposit'));
      expect(answer.text, contains('500.00 EUR'));
    });

    test('a citation window cut mid-marker still renders', () async {
      // The snippet is a fixed-width window into the page, so it can begin or
      // end inside a `**`. That must degrade, not throw.
      final long = 'x' * 300;
      final note = noteWith('$long **Total amount due: 248.60 EUR** $long');
      final passages = PassageExtractor.extract(note);

      for (final passage in passages) {
        expect(
          () => PassageExtractor.citationSnippet(passage),
          returnsNormally,
        );
      }
    });
  });
}
