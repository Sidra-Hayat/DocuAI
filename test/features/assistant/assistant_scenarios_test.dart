import 'dart:io';

import 'package:docuai/hive_registrar.g.dart';
import 'package:docuai/src/features/assistant/data/datasources/chat_history_local_data_source.dart';
import 'package:docuai/src/features/assistant/data/models/chat_message_model.dart';
import 'package:docuai/src/features/assistant/data/repositories/retrieval_assistant_repository.dart';
import 'package:docuai/src/features/assistant/domain/entities/assistant_answer.dart';
import 'package:docuai/src/features/assistant/domain/entities/assistant_intent.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/search/domain/entities/search_hit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';

/// The fifteen things a person actually does with the assistant.
///
/// Written from the outside in: each test is a scenario someone would describe
/// in a sentence, and it asserts what they would see. Two properties run
/// through all of them and matter more than any individual wording —
///
///  * **nothing is invented.** Every claim in every answer is either a value
///    read off a page or a count of such values. [expectQuotesOnlyTheLibrary]
///    checks that mechanically for the answers that quote.
///  * **an answer that is not there says so.** A weak match must never be
///    dressed up as a finding.
///
/// The assistant has no language model and these tests are written on the
/// assumption that it never will pretend to: what it offers instead is the
/// document's own words, arranged into sentences a person can read.
void main() {
  late Directory tempDir;
  late Box<ChatMessageModel> box;
  late FakeSearchRepository search;
  late FakeDocumentRepository documents;
  late RetrievalAssistantRepository repository;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_scenarios');
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

  // ---- The library ---------------------------------------------------------

  Document bill() => buildDocument(
    id: 'bill',
    title: 'Electricity bill August',
    pages: <DocumentPage>[
      buildPage(
        id: 'bill-p0',
        index: 0,
        ocrStatus: OcrStatus.completed,
        text:
            'Northwind Utilities\n'
            'Quarterly electricity statement for the supply address below.\n'
            'Account number: NW-4471902\n'
            'Account holder: Aisha Rahman\n'
            'Supply address: 14 Marlowe Street\n'
            'Invoice date: 12/03/2026\n'
            'Payment due: 05/04/2026\n'
            'Electricity charges for the quarter: 198.40 EUR\n'
            'Standing charge: 50.20 EUR\n'
            'Total amount due: 248.60 EUR\n'
            'Please pay by direct debit or call 0800 114 4477.',
      ),
    ],
  );

  Document rental() => buildDocument(
    id: 'rental',
    title: 'Rental agreement',
    pages: <DocumentPage>[
      buildPage(
        id: 'rental-p0',
        index: 0,
        ocrStatus: OcrStatus.completed,
        text:
            'This tenancy agreement is made between Marcus Webb, the '
            'landlord, and Aisha Rahman, the tenant.\n'
            'The deposit is 900.00 EUR, held for the duration of the '
            'tenancy.\n'
            'The tenancy begins on 01/09/2025 and ends on 31/08/2026.',
      ),
    ],
  );

  Document report() => buildDocument(
    id: 'report',
    title: 'Flutter Project Report',
    source: DocumentSource.created,
    pages: <DocumentPage>[
      buildTextPage(
        id: 'report-p0',
        index: 0,
        text:
            '# Flutter Project Report\n'
            'Prepared by Sidra Hayat on 12/03/2026.\n'
            '## Project setup\n'
            'The project was created with the Flutter command line tools.\n'
            '## UI design\n'
            'The interface follows Material 3 with a dark charcoal theme.\n'
            '## Permissions\n'
            'Camera permission is requested at first use.\n'
            '## Android testing\n'
            'The application was tested on a Pixel 6 running Android 14.',
      ),
    ],
  );

  void seedLibrary() {
    documents
      ..seed(bill())
      ..seed(rental())
      ..seed(report());
    search.results = <SearchHit>[
      SearchHit(document: bill(), score: 9),
      SearchHit(document: rental(), score: 4),
    ];
  }

  Future<AssistantAnswer> run(AssistantIntent intent, {String? documentId}) =>
      repository
          .run(intent, documentId: documentId)
          .then((result) => result.valueOrNull!);

  Future<AssistantAnswer> ask(String question, {String? documentId}) =>
      repository
          .ask(question, documentId: documentId)
          .then((result) => result.valueOrNull!);

  String flatten(String text) => text.replaceAll(RegExp(r'\s+'), ' ');

  /// Every quoted line in the answer appears verbatim in the library.
  ///
  /// The mechanical form of "nothing is invented". Lines that are the app's own
  /// scaffolding — the sentence introducing a list, the count at the end — are
  /// skipped; anything bulleted or quoted has to be somewhere on a page.
  void expectQuotesOnlyTheLibrary(AssistantAnswer answer) {
    final corpus = flatten(
      <Document>[
        bill(),
        rental(),
        report(),
      ].map((document) => document.extractedText).join('\n'),
    );

    for (final line in answer.text.split('\n')) {
      final quoted = line.startsWith('• ')
          ? line.substring(2)
          : line.startsWith('“') && line.endsWith('”')
          ? line.substring(1, line.length - 1)
          : null;
      if (quoted == null || quoted.isEmpty) continue;

      expect(
        corpus,
        contains(flatten(quoted)),
        reason: 'the assistant produced a line no document contains: $quoted',
      );
    }
  }

  // ---- 1–5: understanding a document ---------------------------------------

  group('1. "Summarise this document"', () {
    test('gives the document’s own main points, introduced', () async {
      seedLibrary();

      final answer = await run(const SummarizeDocument(), documentId: 'bill');

      expect(answer.text, startsWith('The main points of'));
      expect(answer.text, contains('Total amount due: 248.60 EUR'));
      expectQuotesOnlyTheLibrary(answer);
    });

    test('cites the document and page it read', () async {
      seedLibrary();

      final answer = await run(const SummarizeDocument(), documentId: 'bill');

      expect(answer.citations.single.documentTitle, 'Electricity bill August');
      expect(answer.citations.single.pageLabel, 'Page 1');
    });
  });

  group('2. "Give me a short summary"', () {
    test('is shorter than the full one and still quoted', () async {
      seedLibrary();

      int bullets(AssistantAnswer answer) =>
          answer.text.split('\n').where((line) => line.startsWith('• ')).length;

      final full = await run(const SummarizeDocument(), documentId: 'bill');
      final short = await run(
        const SummarizeDocument(brief: true),
        documentId: 'bill',
      );

      expect(short.text, startsWith('“Electricity bill August” in short:'));
      expect(bullets(short), lessThan(bullets(full)));
      expectQuotesOnlyTheLibrary(short);
    });

    test('typed, it is recognised as a request for less', () async {
      seedLibrary();

      final answer = await ask('Give me a short summary', documentId: 'bill');

      expect(answer.kind, AnswerKind.summary);
      expect(answer.text, contains('in short'));
    });
  });

  group('3. "What is this document about?"', () {
    test('answers what it is, not a list of details', () async {
      seedLibrary();

      final answer = await ask(
        'What is this document about?',
        documentId: 'bill',
      );

      expect(answer.kind, AnswerKind.explanation);
      expect(answer.text, startsWith('This document is about'));
      expectQuotesOnlyTheLibrary(answer);
      expect(answer.citations.single.documentId, 'bill');
    });

    test('"What is this about?" reaches the same place', () async {
      seedLibrary();

      final answer = await ask('What is this about?', documentId: 'bill');

      expect(answer.kind, AnswerKind.explanation);
      expect(answer.text, startsWith('This document is about'));
    });
  });

  group('4. "Explain this document"', () {
    test('a written document is described by its own sections', () async {
      seedLibrary();

      final answer = await run(const ExplainDocument(), documentId: 'report');

      expect(
        answer.text,
        startsWith(
          'This document covers Project setup, UI design, Permissions and '
          'Android testing.',
        ),
      );
    });

    test('a scan is described by its own opening line', () async {
      seedLibrary();

      final answer = await run(const ExplainDocument(), documentId: 'bill');

      expect(answer.text, startsWith('This document is about “'));
      expectQuotesOnlyTheLibrary(answer);
    });

    test('it counts the facts rather than reprinting them', () async {
      seedLibrary();

      final answer = await run(const ExplainDocument(), documentId: 'bill');

      expect(answer.text, contains('It records two dates'));
      expect(answer.text, contains('three amounts'));
    });

    test('never quotes the words of the request', () async {
      seedLibrary();

      final answer = await ask('Explain this document', documentId: 'bill');

      expect(answer.text.toLowerCase(), isNot(contains('“this document')));
      expect(answer.text, isNot(contains('This passage says')));
    });
  });

  group('5. "What are the main points?"', () {
    test('is a summary, not an explanation', () async {
      seedLibrary();

      final answer = await ask('What are the main points?', documentId: 'bill');

      expect(answer.kind, AnswerKind.summary);
      expectQuotesOnlyTheLibrary(answer);
    });
  });

  // ---- 6–9: asking for facts -----------------------------------------------

  group('6. "What is the total amount?"', () {
    test('answers with the line that carries it', () async {
      seedLibrary();

      final answer = await ask('What is the total amount?', documentId: 'bill');

      expect(answer.kind, AnswerKind.grounded);
      expect(answer.text, contains('248.60'));
      expect(answer.citations.single.documentId, 'bill');
    });

    test('the retrieval-first pipeline is what answered it', () async {
      seedLibrary();

      await ask('What is the total amount?');

      expect(
        search.receivedQueries,
        isNotEmpty,
        reason: 'a typed question still goes through search first',
      );
    });
  });

  group('7. "Who is mentioned in this document?"', () {
    test('lists the names on the page', () async {
      seedLibrary();

      final answer = await ask(
        'Who is mentioned in this document?',
        documentId: 'bill',
      );

      expect(answer.kind, AnswerKind.extraction);
      expect(answer.text, contains('Aisha Rahman'));
      expect(answer.citations.single.documentId, 'bill');
    });

    test('a name is never assembled across a line break', () async {
      // "…Report" ending one line above "Prepared by…" is not a person. The
      // pattern used to join them, and reported "Report Prepared" as a name.
      seedLibrary();

      final answer = await ask(
        'Who is mentioned in this document?',
        documentId: 'report',
      );

      expect(answer.text, isNot(contains('Report Prepared')));
      expect(answer.text, contains('Sidra Hayat'));
    });
  });

  group('8. "What dates are mentioned?"', () {
    test('lists the dates on the page', () async {
      seedLibrary();

      final answer = await ask('What dates are mentioned?', documentId: 'bill');

      expect(answer.kind, AnswerKind.extraction);
      expect(answer.text, contains('12/03/2026'));
      expect(answer.text, contains('05/04/2026'));
    });

    test('an address is not a date', () async {
      // "14 Marlowe Street" was read as a date, because the month pattern
      // matched the "Mar" that begins "Marlowe".
      seedLibrary();

      final answer = await ask('What dates are mentioned?', documentId: 'bill');

      expect(answer.text, isNot(contains('Marlowe')));
    });

    test('"When is it due?" still wants one date, not all of them', () async {
      seedLibrary();

      final answer = await ask('When is it due?', documentId: 'bill');

      expect(
        answer.kind,
        AnswerKind.grounded,
        reason: 'a singular question is a question, not a listing',
      );
      expect(answer.text, contains('05/04/2026'));
    });
  });

  group('9. "Find the important information"', () {
    test('gathers every kind of fact, grouped', () async {
      seedLibrary();

      final answer = await run(
        const FindInformation(InformationKind.important),
        documentId: 'bill',
      );

      expect(answer.kind, AnswerKind.extraction);
      for (final heading in <String>['Dates', 'Amounts', 'Names']) {
        expect(answer.text, contains(heading), reason: heading);
      }
      expect(answer.text, contains('248.60'));
      expect(answer.citations.single.documentId, 'bill');
    });

    test(
      'typed, it is a digest rather than a search for "information"',
      () async {
        seedLibrary();

        final answer = await ask(
          'Find the important information',
          documentId: 'bill',
        );

        expect(answer.kind, AnswerKind.extraction);
        expect(answer.text.toLowerCase(), isNot(contains('“information')));
      },
    );
  });

  // ---- 10–11: requests that name nothing -----------------------------------

  group('10. "What does this section mean?"', () {
    test('explains the document rather than hunting for "section"', () async {
      seedLibrary();

      final answer = await ask(
        'What does this section mean?',
        documentId: 'bill',
      );

      expect(answer.kind, AnswerKind.explanation);
      expect(answer.text, startsWith('This document is about'));
    });
  });

  group('11. "Find this sentence"', () {
    test(
      'says plainly that it found nothing, quoting no part of the request',
      () async {
        // There is no sentence attached to this request, and no page contains the
        // word. Saying so is the honest answer; echoing the request is not.
        seedLibrary();

        final answer = await ask('Find this sentence', documentId: 'bill');

        expect(answer.isGrounded, isFalse);
        expect(answer.text, RetrievalAssistantRepository.notFoundMessage);
      },
    );
  });

  // ---- 12–14: the boundaries of what is known ------------------------------

  group('12. an answer that is not in the documents', () {
    test('is reported as not found, with no citation', () async {
      seedLibrary();

      final answer = await ask(
        'What is the wifi password?',
        documentId: 'bill',
      );

      expect(answer.kind, AnswerKind.noMatch);
      expect(answer.text, RetrievalAssistantRepository.notFoundMessage);
      expect(answer.citations, isEmpty);
      expect(answer.isGrounded, isFalse);
    });

    test('a weak match is not dressed up as an answer', () async {
      seedLibrary();

      final answer = await ask(
        'helicopter rotor maintenance',
        documentId: 'bill',
      );

      expect(answer.isGrounded, isFalse);
      expect(answer.text, isNot(contains('helicopter')));
    });
  });

  group('13. a question about one specific document', () {
    test('answers from that document and no other', () async {
      seedLibrary();

      final answer = await ask(
        'How much is the deposit?',
        documentId: 'rental',
      );

      expect(answer.text, contains('900.00'));
      expect(
        answer.citations.map((citation) => citation.documentId),
        everyElement('rental'),
      );
      expect(
        search.receivedQueries,
        isEmpty,
        reason: 'the user already said where to look',
      );
    });
  });

  group('14. a question across the whole library', () {
    test('may draw on more than one document, and cites each', () async {
      seedLibrary();

      final answer = await ask('Who is Aisha Rahman?');

      expect(answer.isGrounded, isTrue);
      expect(answer.citations, isNotEmpty);
      expect(
        answer.citations.every((citation) => citation.documentTitle.isNotEmpty),
        isTrue,
        reason: 'every source names the document it came from',
      );
      expectQuotesOnlyTheLibrary(answer);
    });
  });

  // ---- 15: explaining a selection ------------------------------------------

  group('15. explaining selected text', () {
    test('uses the selection itself as the source', () async {
      seedLibrary();

      final answer = await run(
        const ExplainSelection('Standing charge: 50.20 EUR'),
        documentId: 'bill',
      );

      expect(answer.kind, AnswerKind.explanation);
      expect(answer.text, startsWith('“Standing charge: 50.20 EUR”'));
      expect(answer.text, contains('What it records:'));
      expect(answer.text, contains('50.20'));
    });

    test('does not read the selection back as a discovery', () async {
      seedLibrary();

      final answer = await run(
        const ExplainSelection('Standing charge: 50.20 EUR'),
        documentId: 'bill',
      );

      expect(answer.text, isNot(contains('This passage says')));
    });

    test('never searches for the selection instead of using it', () async {
      seedLibrary();

      final answer = await run(
        const ExplainSelection('Total amount due: 248.60 EUR'),
        documentId: 'bill',
      );

      expect(answer.text, contains('248.60'));
    });
  });

  // ---- Search and Assistant stay different jobs ----------------------------

  group('Search finds; the Assistant understands', () {
    test('a document-shaped action never runs a search', () async {
      seedLibrary();

      await run(const SummarizeDocument(), documentId: 'bill');
      await run(const ExplainDocument(), documentId: 'bill');
      await run(
        const FindInformation(InformationKind.dates),
        documentId: 'bill',
      );

      expect(
        search.receivedQueries,
        isEmpty,
        reason: 'understanding one open document is not a retrieval problem',
      );
    });

    test('a typed question does', () async {
      seedLibrary();

      await ask('What is the standing charge?');

      expect(search.receivedQueries, isNotEmpty);
    });
  });
}
