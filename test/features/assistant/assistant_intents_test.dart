import 'dart:io';

import 'package:docuai/hive_registrar.g.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/features/assistant/data/datasources/chat_history_local_data_source.dart';
import 'package:docuai/src/features/assistant/data/models/chat_message_model.dart';
import 'package:docuai/src/features/assistant/data/repositories/retrieval_assistant_repository.dart';
import 'package:docuai/src/features/assistant/domain/entities/assistant_answer.dart';
import 'package:docuai/src/features/assistant/domain/entities/assistant_intent.dart';
import 'package:docuai/src/features/assistant/domain/usecases/ask_assistant.dart';
import 'package:docuai/src/features/assistant/presentation/assistant_intent_codec.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/search/domain/entities/search_hit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';

/// Actions are actions, and questions are questions.
///
/// The defect these tests exist for: every quick action used to be sent as the
/// English it was labelled with, and the engine — which is built to find words
/// on pages — duly went and found them. Tapping Explain answered
///
/// ```
/// This passage says:
/// “this document”
/// ```
///
/// because "this document" is what is left of "Explain this document" once the
/// verb is stripped, and a page in the library contained those words. The
/// answer was retrieval working perfectly on a question nobody asked.
///
/// So the checks below come in two halves. An action must never be parsed, and
/// a typed question must still be — the retrieval-first pipeline is the thing
/// that makes this assistant honest, and none of this replaces it.
void main() {
  late Directory tempDir;
  late Box<ChatMessageModel> box;
  late FakeSearchRepository search;
  late FakeDocumentRepository documents;
  late RetrievalAssistantRepository repository;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_intents');
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

  /// A written report with headings — the case from the screenshots.
  Document report({String id = 'report'}) => buildDocument(
    id: id,
    title: 'Flutter Project Report',
    source: DocumentSource.created,
    pages: <DocumentPage>[
      buildTextPage(
        id: '$id-p0',
        index: 0,
        text:
            '# Flutter Project Report\n'
            'Prepared by Sidra Hayat on 12/03/2026.\n'
            '## Project setup\n'
            'The project was created with the Flutter command line tools.\n'
            '## UI design\n'
            'The interface follows Material 3 with a dark charcoal theme.\n'
            '## Flashlight integration\n'
            'The torch is toggled through a platform channel.\n'
            '## Permissions\n'
            'Camera permission is requested at first use.\n'
            '## Android testing\n'
            'The application was tested on a Pixel 6 running Android 14.',
      ),
    ],
  );

  /// A scanned bill with no headings at all.
  Document bill({String id = 'bill'}) => buildDocument(
    id: id,
    title: 'Electricity bill',
    pages: <DocumentPage>[
      buildPage(
        id: '$id-p0',
        index: 0,
        ocrStatus: OcrStatus.completed,
        text:
            'Northwind Utilities issues this statement every quarter.\n'
            'Account number: NW-4471902\n'
            'Invoice date: 12/03/2026\n'
            'Payment due: 05/04/2026\n'
            'Account holder: Aisha Rahman\n'
            'Supply address: 14 Marlowe Street\n'
            'Total amount due: 248.60 EUR\n'
            'The standing charge for the quarter applies to every account.',
      ),
    ],
  );

  Future<AssistantAnswer> run(
    AssistantIntent intent, {
    String? documentId,
  }) async =>
      (await repository.run(intent, documentId: documentId)
              as Success<AssistantAnswer>)
          .value;

  Future<AssistantAnswer> ask(String question, {String? documentId}) async =>
      (await repository.ask(question, documentId: documentId)
              as Success<AssistantAnswer>)
          .value;

  /// The shape of the bug, wherever it might reappear: the request read back as
  /// though the document had said it.
  void expectDoesNotEchoTheQuestion(AssistantAnswer answer, String phrase) {
    expect(
      answer.text.toLowerCase(),
      isNot(contains('“$phrase')),
      reason: 'the query was quoted back as if it were content',
    );
    expect(
      answer.text,
      isNot(startsWith('This passage says:\n“$phrase')),
      reason: 'the query was quoted back as if it were content',
    );
  }

  group('explaining a document', () {
    test('does not search for the words of the request', () async {
      documents.seed(report());
      search.results = <SearchHit>[SearchHit(document: report(), score: 9)];

      final answer = await run(const ExplainDocument(), documentId: 'report');

      expectDoesNotEchoTheQuestion(answer, 'this document');
      expect(
        search.receivedQueries,
        isEmpty,
        reason: 'an action about the open document has nothing to search for',
      );
    });

    test('describes the document from its own headings', () async {
      documents.seed(report());

      final answer = await run(const ExplainDocument(), documentId: 'report');

      expect(answer.kind, AnswerKind.explanation);
      expect(answer.text, contains('Flutter Project Report'));
      expect(answer.text, contains('What it covers:'));

      for (final heading in <String>[
        'Project setup',
        'UI design',
        'Flashlight integration',
        'Permissions',
        'Android testing',
      ]) {
        expect(answer.text, contains(heading), reason: heading);
      }
    });

    test('does not list the title as one of its own topics', () async {
      documents.seed(report());

      final answer = await run(const ExplainDocument(), documentId: 'report');

      final topics = answer.text
          .split('\n')
          .where((line) => line.startsWith('• '))
          .map((line) => line.substring(2))
          .toList();

      expect(
        topics,
        isNot(contains('Flutter Project Report')),
        reason: 'it is called X, and then covers X — said twice',
      );
      expect(topics, contains('Project setup'));
    });

    test('reports the facts the document carries', () async {
      documents.seed(report());

      final answer = await run(const ExplainDocument(), documentId: 'report');

      expect(answer.text, contains('It also contains:'));
      expect(answer.text, contains('12/03/2026'));
    });

    test('works on a scan, which has no headings to read', () async {
      documents.seed(bill());

      final answer = await run(const ExplainDocument(), documentId: 'bill');

      expect(answer.kind, AnswerKind.explanation);
      expect(answer.text, contains('Electricity bill'));
      expect(answer.text, contains('What it covers:'));
      expect(answer.citations, isNotEmpty);
    });

    test('cites the pages it was built from', () async {
      documents.seed(report());

      final answer = await run(const ExplainDocument(), documentId: 'report');

      expect(answer.isGrounded, isTrue);
      expect(answer.citations.first.documentId, 'report');
    });

    test('says so when there is not enough text to explain', () async {
      documents.seed(
        buildDocument(
          id: 'blank',
          title: 'Blank scan',
          pages: <DocumentPage>[buildPage(id: 'blank-p0', index: 0, text: '')],
        ),
      );

      final answer = await run(const ExplainDocument(), documentId: 'blank');

      expect(answer.isGrounded, isFalse);
      expect(answer.text, isNot(contains('This passage says')));
    });

    test('asks for a document when the conversation is about none', () async {
      final answer = await run(const ExplainDocument());

      expect(answer.kind, AnswerKind.needsDocument);
      expect(answer.citations, isEmpty);
    });
  });

  group('summarising', () {
    test('summarises the open document', () async {
      documents.seed(bill());

      final answer = await run(const SummarizeDocument(), documentId: 'bill');

      expect(answer.kind, AnswerKind.summary);
      expect(answer.citations.first.documentId, 'bill');

      // Every line was lifted off the page, as the summariser has always
      // promised.
      final pageText = bill().extractedText.replaceAll(RegExp(r'\s+'), ' ');
      for (final line in answer.text.split('\n')) {
        if (!line.startsWith('• ')) continue;
        expect(pageText, contains(line.substring(2)));
      }
    });

    test('a short summary is shorter', () async {
      documents.seed(bill());

      int bullets(AssistantAnswer answer) =>
          answer.text.split('\n').where((line) => line.startsWith('• ')).length;

      final full = await run(const SummarizeDocument(), documentId: 'bill');
      final short = await run(
        const SummarizeDocument(brief: true),
        documentId: 'bill',
      );

      expect(bullets(short), lessThan(bullets(full)));
    });

    test('never searches for the words of the button', () async {
      documents.seed(bill());

      await run(const SummarizeDocument(), documentId: 'bill');

      expect(search.receivedQueries, isEmpty);
    });
  });

  group('finding information', () {
    test('names are extracted, not searched for', () async {
      documents.seed(bill());

      final answer = await run(
        const FindInformation(InformationKind.names),
        documentId: 'bill',
      );

      expect(answer.kind, AnswerKind.extraction);
      expect(answer.text, contains('Aisha Rahman'));
      expectDoesNotEchoTheQuestion(answer, 'find names');
      expect(search.receivedQueries, isEmpty);
    });

    test('dates are extracted, not searched for', () async {
      documents.seed(bill());

      final answer = await run(
        const FindInformation(InformationKind.dates),
        documentId: 'bill',
      );

      expect(answer.kind, AnswerKind.extraction);
      expect(answer.text, contains('12/03/2026'));
      expect(answer.text, contains('05/04/2026'));
      expectDoesNotEchoTheQuestion(answer, 'important dates');
      expect(search.receivedQueries, isEmpty);
    });

    test('amounts are extracted', () async {
      documents.seed(bill());

      final answer = await run(
        const FindInformation(InformationKind.amounts),
        documentId: 'bill',
      );

      expect(answer.text, contains('248.60'));
    });

    test('places are a real capability, not an empty one', () async {
      documents.seed(bill());

      final answer = await run(
        const FindInformation(InformationKind.locations),
        documentId: 'bill',
      );

      expect(answer.kind, AnswerKind.extraction);
      expect(answer.text, contains('Marlowe Street'));
    });

    test('important information gathers every kind at once', () async {
      documents.seed(bill());

      final answer = await run(
        const FindInformation(InformationKind.important),
        documentId: 'bill',
      );

      expect(answer.kind, AnswerKind.extraction);
      expect(answer.text, contains('Dates'));
      expect(answer.text, contains('Amounts'));
      expect(answer.text, contains('248.60'));
      expect(answer.text, contains('12/03/2026'));
      expectDoesNotEchoTheQuestion(answer, 'important information');
    });

    test('says where it looked when it finds nothing', () async {
      documents.seed(
        buildDocument(
          id: 'prose',
          title: 'A note',
          source: DocumentSource.created,
          pages: <DocumentPage>[
            buildTextPage(
              id: 'prose-p0',
              index: 0,
              text: 'Remember to water the plants before leaving.',
            ),
          ],
        ),
      );

      final answer = await run(
        const FindInformation(InformationKind.amounts),
        documentId: 'prose',
      );

      expect(answer.kind, AnswerKind.noMatch);
      expect(answer.text, contains('A note'));
    });
  });

  group('scoping', () {
    test('an action reads only the document it is about', () async {
      final other = buildDocument(
        id: 'other',
        title: 'Rental agreement',
        pages: <DocumentPage>[
          buildPage(
            id: 'other-p0',
            index: 0,
            ocrStatus: OcrStatus.completed,
            text: 'Deposit of 900.00 EUR held by Marcus Webb until 01/01/2027.',
          ),
        ],
      );
      documents
        ..seed(bill())
        ..seed(other);

      final answer = await run(
        const FindInformation(InformationKind.names),
        documentId: 'bill',
      );

      expect(answer.text, contains('Aisha Rahman'));
      expect(
        answer.text,
        isNot(contains('Marcus Webb')),
        reason: 'the conversation was about the bill, not the library',
      );
      expect(
        answer.citations.map((citation) => citation.documentId),
        everyElement('bill'),
      );
    });
  });

  group('typed questions still use retrieval', () {
    test('an ordinary question goes through search', () async {
      documents.seed(bill());
      search.results = <SearchHit>[SearchHit(document: bill(), score: 7)];

      final answer = await ask('What is the total amount?');

      expect(
        search.receivedQueries,
        isNotEmpty,
        reason: 'the retrieval-first pipeline is not replaced by any of this',
      );
      expect(answer.kind, AnswerKind.grounded);
      expect(answer.text, contains('248.60'));
    });

    test('a question about a shape still finds its passage', () async {
      documents.seed(bill());
      search.results = <SearchHit>[SearchHit(document: bill(), score: 7)];

      final answer = await ask('When is the payment due?');

      expect(answer.kind, AnswerKind.grounded);
      expect(answer.text, contains('05/04/2026'));
    });

    test('nothing found says nothing found, and quotes no query', () async {
      documents.seed(bill());
      search.results = <SearchHit>[SearchHit(document: bill(), score: 1)];

      final answer = await ask('helicopter rotor maintenance schedule');

      expect(answer.kind, AnswerKind.noMatch);
      expect(answer.text, RetrievalAssistantRepository.notFoundMessage);
      expect(answer.citations, isEmpty);
    });
  });

  group('typed requests that only name the document', () {
    test('"Explain this document" explains the document', () async {
      documents.seed(report());
      search.results = <SearchHit>[SearchHit(document: report(), score: 9)];

      final answer = await ask('Explain this document', documentId: 'report');

      expect(answer.kind, AnswerKind.explanation);
      expect(answer.text, contains('What it covers:'));
      expectDoesNotEchoTheQuestion(answer, 'this document');
    });

    test('"Explain this" does too', () async {
      documents.seed(report());

      final answer = await ask('Explain this', documentId: 'report');

      expect(answer.kind, AnswerKind.explanation);
      expectDoesNotEchoTheQuestion(answer, 'this');
    });

    test(
      '"What is this document about?" is understood, not searched literally',
      () async {
        documents.seed(bill());

        final answer = await ask(
          'What is this document about?',
          documentId: 'bill',
        );

        expect(
          answer.kind,
          anyOf(AnswerKind.summary, AnswerKind.explanation),
          reason: 'a request to understand the document, not to find a phrase',
        );
        expect(answer.citations.first.documentId, 'bill');
      },
    );

    test(
      'typed "Find important information" is a digest, not a search',
      () async {
        // The request is made entirely of request words. There is no term on any
        // page to look for, which is why it used to retrieve whichever passage
        // happened to contain "information".
        documents.seed(bill());
        search.results = <SearchHit>[SearchHit(document: bill(), score: 4)];

        final answer = await ask(
          'Find important information',
          documentId: 'bill',
        );

        expect(answer.kind, AnswerKind.extraction);
        expect(answer.text, contains('248.60'));
        expectDoesNotEchoTheQuestion(answer, 'important information');
      },
    );

    test('"Explain its features" does not quote the request back', () async {
      // The second screenshot. There is nothing about features in this
      // document, so the honest answer is that there is nothing — never
      // “its features”.
      documents.seed(bill());
      search.results = <SearchHit>[SearchHit(document: bill(), score: 2)];

      final answer = await ask('Explain its features', documentId: 'bill');

      expectDoesNotEchoTheQuestion(answer, 'its features');
      expect(
        answer.text.toLowerCase(),
        isNot(contains('its features')),
        reason: 'the words of the question must not appear as the answer',
      );
    });

    test('a genuine selection is still explained as a passage', () async {
      documents.seed(bill());
      search.results = <SearchHit>[SearchHit(document: bill(), score: 5)];

      final answer = await run(
        const ExplainSelection('Total amount due: 248.60 EUR'),
        documentId: 'bill',
      );

      expect(answer.kind, AnswerKind.explanation);
      expect(answer.text, startsWith('This passage says:'));
      expect(answer.text, contains('248.60'));
    });

    test(
      'a selection that names only the document explains the document',
      () async {
        documents.seed(report());

        final answer = await run(
          const ExplainSelection('this document'),
          documentId: 'report',
        );

        expect(answer.text, contains('What it covers:'));
        expectDoesNotEchoTheQuestion(answer, 'this document');
      },
    );
  });

  group('the transcript', () {
    test('an action is recorded as an ordinary pair of turns', () async {
      documents.seed(report());

      final useCase = AskAssistant(
        repository,
        idGenerator: _sequentialIds().iterator.moveNextValue,
      );

      await useCase.run(
        const ExplainDocument(),
        conversationId: 'thread-1',
        documentId: 'report',
      );

      final turns = await repository
          .watchHistory(conversationId: 'thread-1')
          .first;

      expect(turns, hasLength(2));
      expect(turns.first.isFromUser, isTrue);
      expect(
        turns.first.text,
        'Explain this document',
        reason:
            'a thread showing an answer with no request above it is not a '
            'record of anything',
      );
      expect(turns.last.isFromUser, isFalse);
      expect(turns.last.text, contains('What it covers:'));
      expect(turns.last.citations, isNotEmpty);
    });

    test('a conversation reopens with its action turns intact', () async {
      documents.seed(bill());

      final useCase = AskAssistant(
        repository,
        idGenerator: _sequentialIds().iterator.moveNextValue,
      );

      await useCase.run(
        const FindInformation(InformationKind.dates),
        conversationId: 'thread-2',
        documentId: 'bill',
      );
      await useCase(
        'What is the total amount?',
        conversationId: 'thread-2',
        documentId: 'bill',
      );

      final turns = await repository
          .watchHistory(conversationId: 'thread-2')
          .first;

      expect(turns, hasLength(4));
      expect(turns[0].text, 'Find important dates');
      expect(turns[2].text, 'What is the total amount?');

      final threads = await repository.watchConversations().first;
      expect(threads, hasLength(1));
      expect(threads.single.messageCount, 4);
    });
  });

  group('carrying an intent through a route', () {
    test('every action survives the round trip', () {
      const intents = <AssistantIntent>[
        SummarizeDocument(),
        SummarizeDocument(brief: true),
        ExplainDocument(),
        FindInformation(InformationKind.important),
        FindInformation(InformationKind.names),
        FindInformation(InformationKind.dates),
        FindInformation(InformationKind.amounts),
        FindInformation(InformationKind.locations),
        FindInformation(InformationKind.references),
        FindInformation(InformationKind.contacts),
      ];

      for (final intent in intents) {
        final query = AssistantIntentCodec.encode(intent);
        final decoded = AssistantIntentCodec.decode(
          action: query[AssistantIntentCodec.actionKey],
          selection: query[AssistantIntentCodec.selectionKey],
        );

        expect(
          decoded?.transcriptLabel,
          intent.transcriptLabel,
          reason: intent.transcriptLabel,
        );
      }
    });

    test('a selection travels as text rather than as a token', () {
      const selection = 'Total amount due: 248.60 EUR';
      final query = AssistantIntentCodec.encode(
        const ExplainSelection(selection),
      );

      expect(query[AssistantIntentCodec.selectionKey], selection);
      expect(query.containsKey(AssistantIntentCodec.actionKey), isFalse);

      final decoded = AssistantIntentCodec.decode(
        selection: query[AssistantIntentCodec.selectionKey],
      );
      expect((decoded! as ExplainSelection).text, selection);
    });

    test('an unknown action opens the conversation rather than failing', () {
      expect(AssistantIntentCodec.decode(action: 'teleport'), isNull);
      expect(AssistantIntentCodec.decode(), isNull);
    });
  });
}

/// Ids for the transcript, so the turns are distinguishable.
Iterable<String> _sequentialIds() sync* {
  var next = 0;
  while (true) {
    yield 'id-${next++}';
  }
}

extension on Iterator<String> {
  String moveNextValue() {
    moveNext();
    return current;
  }
}
