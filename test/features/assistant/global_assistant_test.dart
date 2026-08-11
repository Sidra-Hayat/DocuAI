import 'dart:io';

import 'package:docuai/hive_registrar.g.dart';
import 'package:docuai/src/features/assistant/data/datasources/chat_history_local_data_source.dart';
import 'package:docuai/src/features/assistant/data/models/chat_message_model.dart';
import 'package:docuai/src/features/assistant/data/repositories/retrieval_assistant_repository.dart';
import 'package:docuai/src/features/assistant/domain/entities/assistant_answer.dart';
import 'package:docuai/src/features/assistant/domain/entities/assistant_intent.dart';
import 'package:docuai/src/features/assistant/domain/entities/chat_message.dart';
import 'package:docuai/src/features/assistant/presentation/widgets/answer_copy.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/search/data/datasources/search_index_local_data_source.dart';
import 'package:docuai/src/features/search/data/repositories/bm25_search_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';

/// The assistant asked from the Assistant tab, with nothing open.
///
/// Run against the **real** BM25 repository over a real Hive index, not a fake
/// search. That is deliberate and it is the whole point of the file: the bug
/// these tests were written for — the global assistant saying it could not find
/// things that were plainly in the library — lived in the seam between the
/// analyzer, the ranker and the retrieval routing. A fake search returns
/// whatever the test tells it to and would have agreed that everything worked.
///
/// Two rules run through all of it:
///
///  * **a question asked in a sentence behaves like the button that means the
///    same thing.** The quick actions are shortcuts, not a second, cleverer
///    assistant, and every parity test below asserts exactly that.
///  * **nothing is invented.** An answer either quotes the library or says it
///    found nothing. There is no third option, and [expectGrounded] checks the
///    quoting mechanically.
void main() {
  late Directory tempDir;
  late Box<ChatMessageModel> chatBox;
  late Box<dynamic> indexBox;
  late FakeDocumentRepository documents;
  late Bm25SearchRepository search;
  late RetrievalAssistantRepository repository;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_global');
    Hive.init(p.join(tempDir.path, 'hive'));
    Hive.registerAdapters();
  });

  setUp(() async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    chatBox = await Hive.openBox<ChatMessageModel>('chat_$stamp');
    indexBox = await Hive.openBox<dynamic>('index_$stamp');
    documents = FakeDocumentRepository();
    search = Bm25SearchRepository(
      index: SearchIndexLocalDataSource(indexBox),
      documents: documents,
    );
    repository = RetrievalAssistantRepository(
      search: search,
      documents: documents,
      history: ChatHistoryLocalDataSource(chatBox),
    );
  });

  tearDown(() async {
    if (chatBox.isOpen) await chatBox.deleteFromDisk();
    if (indexBox.isOpen) await indexBox.deleteFromDisk();
    documents.dispose();
  });

  tearDownAll(() async {
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } on FileSystemException {
      // Windows may still hold the box files; the OS reclaims them.
    }
  });

  Document documentWith({
    required String id,
    required String title,
    required List<String> pageTexts,
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

  Future<void> index(List<Document> library) async {
    for (final document in library) {
      documents.seed(document);
      await search.indexDocument(document);
    }
  }

  /// An internship report, a utility bill and a tenancy agreement.
  ///
  /// Three documents of genuinely different shapes, because that is what breaks
  /// retrieval: the report has headings and prose, the bill is almost entirely
  /// `Label: value` fields, and the agreement is prose with names buried in it.
  Future<void> seedLibrary() => index(<Document>[
    documentWith(
      id: 'report',
      title: 'Internship report',
      pageTexts: <String>[
        '# Flashlight Controller\n'
            'A Flutter application that controls the device torch.\n'
            '## Project setup\n'
            'The project was created with Flutter 3.41 on 04/02/2026.\n'
            '## Permissions\n'
            'Camera permission is requested before the torch is switched on.\n'
            '## Android testing\n'
            'Testing was carried out by Daniel Okafor on a Pixel 7.\n'
            'Supervisor: Priya Nair\n'
            'Contact the supervisor at priya.nair@university.edu',
      ],
    ),
    documentWith(
      id: 'bill',
      title: 'Electricity bill August',
      pageTexts: <String>[
        'Northwind Utilities quarterly electricity statement.\n'
            'Account number: NW-4471902\n'
            'Account holder: Marcus Webb\n'
            'Invoice date: 12/03/2026\n'
            'Payment due: 05/04/2026\n'
            'Total amount due: 248.60 EUR\n'
            'Call 0800 900 1234 to pay by card.',
      ],
    ),
    documentWith(
      id: 'lease',
      title: 'Rental agreement',
      pageTexts: <String>[
        'This tenancy agreement is made between the landlord and the tenant.\n'
            'The tenant is Aisha Rahman and the landlord is Gregor Lantz.\n'
            'The monthly rent is 1150.00 EUR payable on the first of the '
            'month.\n'
            'The property is 14 Marlowe Street, Bristol.\n'
            'The agreement begins on 01/09/2026.',
      ],
    ),
  ]);

  /// Asserts the answer is a real finding drawn from the library.
  ///
  /// Not merely "kind is grounded": it also requires at least one citation, so
  /// an answer that asserted something without saying where it came from would
  /// fail here rather than pass as a success.
  void expectGrounded(AssistantAnswer answer) {
    expect(
      answer.kind,
      isIn(<AnswerKind>[
        AnswerKind.grounded,
        AnswerKind.extraction,
        AnswerKind.summary,
        AnswerKind.explanation,
      ]),
      reason: 'answered nothing: ${answer.text}',
    );
    expect(
      answer.citations,
      isNotEmpty,
      reason: 'claimed something without saying where: ${answer.text}',
    );
  }

  Future<AssistantAnswer> askGlobally(String question) async {
    final result = await repository.ask(question);
    return result.valueOrNull!;
  }

  group('a question typed on the Assistant tab searches the whole library', () {
    test('1. "Find names" returns the people in the documents', () async {
      await seedLibrary();

      final answer = await askGlobally('Find names');

      expectGrounded(answer);
      expect(answer.text, contains('Aisha Rahman'));
      expect(answer.text, contains('Marcus Webb'));
    });

    test('2. "Who is mentioned?" behaves like Find names', () async {
      await seedLibrary();

      final answer = await askGlobally('Who is mentioned?');

      expectGrounded(answer);
      expect(answer.text, contains('Aisha Rahman'));
    });

    test('3. "What are the important dates?" finds dates library-wide', () async {
      await seedLibrary();

      final answer = await askGlobally('What are the important dates?');

      expectGrounded(answer);
      expect(answer.text, contains('12/03/2026'));
      expect(answer.text, contains('01/09/2026'));
    });

    test('4. "Find the email address." finds contact details', () async {
      await seedLibrary();

      final answer = await askGlobally('Find the email address.');

      expectGrounded(answer);
      expect(answer.text, contains('priya.nair@university.edu'));
    });

    test('5. "How much do I owe?" finds the amounts', () async {
      await seedLibrary();

      final answer = await askGlobally('How much do I owe?');

      expectGrounded(answer);
      expect(answer.text, contains('248.60'));
    });

    test('6. an answer cites the documents it was drawn from', () async {
      await seedLibrary();

      final answer = await askGlobally('Find names');

      expect(
        answer.citations.map((citation) => citation.documentId),
        containsAll(<String>['lease', 'bill']),
        reason: 'a library-wide finding must cite every document it used',
      );
    });

    test('7. every citation names a document and a page', () async {
      await seedLibrary();

      final answer = await askGlobally('What are the important dates?');

      for (final citation in answer.citations) {
        expect(citation.documentTitle, isNotEmpty);
        expect(citation.pageIndex, greaterThanOrEqualTo(0));
      }
    });
  });

  group('naming a document scopes the question to it', () {
    test('8. "What is the internship report about?" answers from that '
        'document', () async {
      await seedLibrary();

      final answer = await askGlobally(
        'What is the internship report about?',
      );

      expectGrounded(answer);
      expect(
        answer.citations.map((citation) => citation.documentId).toSet(),
        <String>{'report'},
      );
    });

    test('9. "Summarise the rental agreement" summarises that one', () async {
      await seedLibrary();

      final answer = await askGlobally('Summarise the rental agreement');

      expectGrounded(answer);
      expect(
        answer.citations.map((citation) => citation.documentId).toSet(),
        <String>{'lease'},
      );
    });

    test('10. a person named in a question grounds on the right document',
        () async {
      await seedLibrary();

      final answer = await askGlobally('What documents mention Aisha?');

      expectGrounded(answer);
      expect(
        answer.citations.first.documentId,
        'lease',
        reason: 'Aisha appears only in the tenancy agreement',
      );
    });

    test('11. naming a document that is not there says so, without '
        'answering from a different one', () async {
      await seedLibrary();

      final answer = await askGlobally('Summarise the insurance policy');

      expect(answer.kind, isNot(AnswerKind.summary));
      // Names what it looked for, so the user can see it was understood and
      // simply is not there. "policy" is an identifier word — as in "policy
      // number" — so the distinctive term is what gets reported back.
      expect(answer.text.toLowerCase(), contains('insurance'));
      expect(
        answer.citations,
        isEmpty,
        reason: 'a document that does not exist must not be summarised from '
            'whichever one ranked highest',
      );
    });
  });

  group('a question about the open document stays inside it', () {
    test('12. the same words asked inside a document only use that document',
        () async {
      await seedLibrary();

      final result = await repository.ask('Find names', documentId: 'report');
      final answer = result.valueOrNull!;

      expectGrounded(answer);
      expect(answer.text, contains('Daniel Okafor'));
      expect(
        answer.text,
        isNot(contains('Aisha Rahman')),
        reason: 'scoped to the report, so the tenancy names are out of scope',
      );
    });

    test('13. "What is this document about?" leads with what it is', () async {
      await seedLibrary();

      final result = await repository.ask(
        'What is this document about?',
        documentId: 'bill',
      );
      final answer = result.valueOrNull!;

      expectGrounded(answer);
      expect(
        answer.text,
        contains('Northwind Utilities quarterly electricity statement'),
        reason: 'a bill is introduced by its statement line, not by a field '
            'or by its payment phone number',
      );
    });

    test('14. a document with headings is explained by its headings', () async {
      await seedLibrary();

      final result = await repository.ask(
        'Explain this document',
        documentId: 'report',
      );
      final answer = result.valueOrNull!;

      expectGrounded(answer);
      expect(answer.text, contains('Project setup'));
      expect(answer.text, contains('Permissions'));
    });

    test('15. a question the open document cannot answer does not fall back '
        'to the rest of the library', () async {
      await seedLibrary();

      final result = await repository.ask(
        'What is the monthly rent?',
        documentId: 'bill',
      );
      final answer = result.valueOrNull!;

      expect(
        answer.citations.every((citation) => citation.documentId == 'bill'),
        isTrue,
        reason: 'the rent is in the tenancy agreement, which was not asked',
      );
    });
  });

  group('the buttons are shortcuts, not a second assistant', () {
    test('16. typing "find important information" matches the button',
        () async {
      await seedLibrary();

      final typed = await askGlobally('find important information');
      final pressed = await repository.run(
        const FindInformation(InformationKind.important),
      );

      expect(typed.kind, pressed.valueOrNull!.kind);
    });

    test('17. typing "who is mentioned" matches the Find names button',
        () async {
      await seedLibrary();

      final typed = await askGlobally('who is mentioned');
      final pressed = await repository.run(
        const FindInformation(InformationKind.names),
      );

      expect(typed.kind, pressed.valueOrNull!.kind);
      expect(typed.text, pressed.valueOrNull!.text);
    });

    test('18. typing "what are the important dates" matches the Find dates '
        'button', () async {
      await seedLibrary();

      final typed = await askGlobally('what are the important dates');
      final pressed = await repository.run(
        const FindInformation(InformationKind.dates),
      );

      expect(typed.text, pressed.valueOrNull!.text);
    });

    test('19. typing "explain this document" matches the Explain button',
        () async {
      await seedLibrary();

      final typed = await repository.ask(
        'explain this document',
        documentId: 'report',
      );
      final pressed = await repository.run(
        const ExplainDocument(),
        documentId: 'report',
      );

      expect(typed.valueOrNull!.text, pressed.valueOrNull!.text);
    });
  });

  group('what is not there is reported as not there', () {
    test('20. a question the library does not answer says so plainly',
        () async {
      await seedLibrary();

      final answer = await askGlobally('What is the wifi password?');

      expect(answer.kind, AnswerKind.noMatch);
      expect(answer.citations, isEmpty);
      expect(
        AnswerCopy.forDisplay(answer.text),
        "I couldn't find that information in your documents.",
      );
    });

    test('21. an empty library is not treated as a failed search', () async {
      final answer = await askGlobally('Find names');

      expect(
        AnswerCopy.forDisplay(answer.text),
        AnswerCopy.emptyLibrary,
        reason: 'nothing to search is a different thing from searching and '
            'finding nothing',
      );
    });

    test('22. no answer uses retrieval vocabulary to describe itself',
        () async {
      await seedLibrary();

      const jargon = <String>[
        'bm25',
        'index',
        'query',
        'token',
        'corpus',
        'passage',
        'ocr',
        'embedding',
        'score',
      ];

      for (final question in <String>[
        'Find names',
        'What are the important dates?',
        'How much do I owe?',
        'What is the wifi password?',
        'Summarise the rental agreement',
      ]) {
        final answer = await askGlobally(question);
        final lowered = answer.text.toLowerCase();

        for (final word in jargon) {
          expect(
            lowered,
            isNot(contains(word)),
            reason: '"$question" answered with the word "$word"',
          );
        }
      }
    });
  });

  group('a conversation is kept whatever it was asked from', () {
    test('the global transcript stays separate from a document one', () async {
      await seedLibrary();

      final global = await askGlobally('Find names');
      final scoped = (await repository.ask(
        'Find names',
        documentId: 'report',
      )).valueOrNull!;

      await repository.appendMessage(
        ChatMessage(
          id: 'g1',
          role: ChatRole.assistant,
          text: global.text,
          createdAt: DateTime(2026, 8, 10),
          conversationId: 'library',
          citations: global.citations,
        ),
      );
      await repository.appendMessage(
        ChatMessage(
          id: 'd1',
          role: ChatRole.assistant,
          text: scoped.text,
          createdAt: DateTime(2026, 8, 10, 1),
          documentId: 'report',
          conversationId: 'report-chat',
          citations: scoped.citations,
        ),
      );

      final libraryTurns = await repository
          .watchHistory(conversationId: 'library')
          .first;
      final reportTurns = await repository
          .watchHistory(conversationId: 'report-chat')
          .first;

      expect(libraryTurns, hasLength(1));
      expect(reportTurns, hasLength(1));
      expect(
        libraryTurns.single.text,
        isNot(reportTurns.single.text),
        reason: 'the two conversations answered different scopes',
      );
      expect(
        libraryTurns.single.citations,
        isNotEmpty,
        reason: 'a stored turn keeps the sources it was answered from',
      );
    });
  });
}
