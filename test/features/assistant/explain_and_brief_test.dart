import 'dart:io';

import 'package:docuai/hive_registrar.g.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/features/assistant/data/datasources/chat_history_local_data_source.dart';
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

/// Explaining a passage, and asking for a summary in fewer words.
///
/// "Explain" is the capability most at risk of over-promising. With no language
/// model there is nothing to paraphrase *with*, and producing one anyway would
/// be the single thing this assistant promises never to do. What it can say
/// honestly is what the passage contains and where else those words appear —
/// both read off pages the user already has.
void main() {
  late Directory tempDir;
  late Box<ChatMessageModel> box;
  late FakeSearchRepository search;
  late FakeDocumentRepository documents;
  late RetrievalAssistantRepository repository;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_explain');
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

  Document bill({String id = 'bill'}) => buildDocument(
    id: id,
    title: 'Electricity bill',
    pages: <DocumentPage>[
      buildPage(
        id: '$id-p0',
        index: 0,
        ocrStatus: OcrStatus.completed,
        text:
            'Northwind Utilities\n'
            'Account number: NW-4471902\n'
            'Invoice date: 12/03/2026\n'
            'Payment due: 05/04/2026\n'
            'Account holder: Aisha Rahman\n'
            'Total amount due: 248.60 EUR\n'
            'Standing charge for the quarter applies to every account.',
      ),
    ],
  );

  Future<AssistantAnswer> ask(String question, {String? documentId}) async =>
      (await repository.ask(question, documentId: documentId)
              as Success<AssistantAnswer>)
          .value;

  group('reading an explain request', () {
    test('the mode is recognised', () {
      for (final question in <String>[
        'Explain: Total amount due: 248.60 EUR',
        'explain the standing charge',
        'what does this clarify',
      ]) {
        expect(
          QuestionAnalyzer.analyze(question).mode,
          QuestionMode.explain,
          reason: question,
        );
      }
    });

    test('explaining a summary is not a request to summarise', () {
      // Checked before the summary vocabulary for exactly this case.
      expect(
        QuestionAnalyzer.analyze('explain the summary of clause 4').mode,
        QuestionMode.explain,
      );
    });

    test('the passage is everything after the colon', () {
      expect(
        QuestionAnalyzer.analyze('Explain: Total amount due: 248.60').subject,
        'Total amount due: 248.60',
      );
    });

    test('a typed request still yields something to work with', () {
      expect(
        QuestionAnalyzer.analyze('explain the standing charge').subject,
        'the standing charge',
      );
    });
  });

  group('explaining', () {
    test('quotes the passage back and says what is in it', () async {
      documents.seed(bill());
      search.results = <SearchHit>[SearchHit(document: bill(), score: 5)];

      final answer = await ask(
        'Explain: Payment due: 05/04/2026 — total 248.60 EUR',
        documentId: 'bill',
      );

      expect(answer.kind, AnswerKind.explanation);
      expect(answer.text, contains('05/04/2026'));
      expect(answer.text, contains('248.60'));
      expect(answer.text, contains('It contains:'));
    });

    test('invents nothing — every word comes from the passage or a page', () async {
      // The whole claim. An explanation that introduced a sentence found
      // nowhere in the input would be the failure this assistant exists to
      // avoid, so the check is mechanical: no line of the answer that is not
      // scaffolding may contain words absent from the passage and the library.
      documents.seed(bill());
      search.results = <SearchHit>[SearchHit(document: bill(), score: 5)];

      const passage = 'Total amount due: 248.60 EUR';
      final answer = await ask('Explain: $passage', documentId: 'bill');

      final quoted = answer.text
          .split('\n')
          .firstWhere((line) => line.startsWith('“'));

      expect(quoted, contains(passage));
    });

    test('points at where else the same terms appear', () async {
      final other = buildDocument(
        id: 'other',
        title: 'Standing charge notice',
        pages: <DocumentPage>[
          buildPage(
            id: 'other-p0',
            index: 0,
            ocrStatus: OcrStatus.completed,
            text: 'The standing charge for the quarter is under review.',
          ),
        ],
      );
      documents
        ..seed(bill())
        ..seed(other);
      search.results = <SearchHit>[
        SearchHit(document: other, score: 9),
        SearchHit(document: bill(), score: 3),
      ];

      final answer = await ask('Explain: standing charge for the quarter');

      expect(answer.citations, isNotEmpty);
      expect(
        answer.citations.map((citation) => citation.documentId),
        contains('other'),
      );
    });

    test('does not cite the passage back to itself', () async {
      // Telling the user their selection appears where they selected it is
      // the one place it definitely appears.
      documents.seed(bill());
      search.results = <SearchHit>[SearchHit(document: bill(), score: 5)];

      final answer = await ask(
        'Explain: Total amount due: 248.60 EUR',
        documentId: 'bill',
      );

      expect(
        answer.text.contains('other place'),
        isFalse,
        reason: 'the only match was the selection itself',
      );
    });

    test('an empty selection asks for one rather than guessing', () async {
      final answer = await ask('Explain:');

      expect(answer.kind, AnswerKind.unclearQuestion);
      expect(answer.citations, isEmpty);
    });
  });

  group('a shorter summary', () {
    test('brief is recognised however it is asked for', () {
      for (final question in <String>[
        'Summarise this document briefly',
        'give me a short summary',
        'a quick overview please',
      ]) {
        final analyzed = QuestionAnalyzer.analyze(question);
        expect(analyzed.mode, QuestionMode.summary, reason: question);
        expect(analyzed.brief, isTrue, reason: question);
      }
    });

    test('an ordinary summary request is not brief', () {
      expect(QuestionAnalyzer.analyze('Summarise this document').brief, isFalse);
    });

    test('it produces fewer lines than the full one', () async {
      documents.seed(bill());

      int linesOf(AssistantAnswer answer) =>
          answer.text.split('\n').where((l) => l.startsWith('• ')).length;

      final full = await ask('Summarise this document', documentId: 'bill');
      final brief = await ask(
        'Summarise this document briefly',
        documentId: 'bill',
      );

      expect(full.kind, AnswerKind.summary);
      expect(brief.kind, AnswerKind.summary);
      expect(
        linesOf(brief),
        lessThanOrEqualTo(
          RetrievalAssistantRepository.briefSummarySentences,
        ),
      );
      expect(linesOf(brief), lessThan(linesOf(full)));
    });

    test('a brief summary is still quoted, never composed', () async {
      documents.seed(bill());

      final brief = await ask(
        'Summarise this document briefly',
        documentId: 'bill',
      );

      final pageText = bill().extractedText.replaceAll(RegExp(r'\s+'), ' ');
      for (final line in brief.text.split('\n')) {
        if (!line.startsWith('• ')) continue;
        expect(
          pageText,
          contains(line.substring(2)),
          reason: 'a summary line the document does not contain was invented',
        );
      }
    });

    test('it still cites the pages it came from', () async {
      documents.seed(bill());

      final brief = await ask(
        'Summarise this document briefly',
        documentId: 'bill',
      );

      expect(brief.isGrounded, isTrue);
      expect(brief.citations.first.documentId, 'bill');
    });
  });
}
