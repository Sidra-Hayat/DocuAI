import 'dart:io';

import 'package:docuai/hive_registrar.g.dart';
import 'package:docuai/src/features/assistant/data/datasources/chat_history_local_data_source.dart';
import 'package:docuai/src/features/assistant/data/models/chat_message_model.dart';
import 'package:docuai/src/features/assistant/data/repositories/retrieval_assistant_repository.dart';
import 'package:docuai/src/features/assistant/domain/entities/assistant_answer.dart';
import 'package:docuai/src/features/assistant/domain/entities/assistant_intent.dart';
import 'package:docuai/src/features/assistant/domain/entities/chat_message.dart';
import 'package:docuai/src/features/assistant/domain/usecases/suggest_questions.dart';
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
    DateTime? updatedAt,
  }) => buildDocument(
    id: id,
    title: title,
    updatedAt: updatedAt,
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

  /// The bill is the newest document, the report the oldest.
  ///
  /// Stated explicitly rather than left to the fixture's defaults, because
  /// "which document did the assistant pick" is now a user-visible decision:
  /// a request naming no document resolves to the one last worked on, and a
  /// library whose timestamps all tie would make that assertion a coin toss.
  const newest = 'bill';

  /// An internship report, a utility bill and a tenancy agreement.
  ///
  /// Three documents of genuinely different shapes, because that is what breaks
  /// retrieval: the report has headings and prose, the bill is almost entirely
  /// `Label: value` fields, and the agreement is prose with names buried in it.
  Future<void> seedLibrary() => index(<Document>[
    documentWith(
      id: 'report',
      title: 'Internship report',
      updatedAt: DateTime.utc(2026, 8, 1),
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
      updatedAt: DateTime.utc(2026, 8, 9),
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
      updatedAt: DateTime.utc(2026, 8, 5),
      pageTexts: <String>[
        'This tenancy agreement is made between the landlord and the tenant.\n'
            'The tenant is Aisha Rahman and the landlord is Gregor Lantz.\n'
            'The monthly rent is 1150.00 EUR payable on the first of the '
            'month.\n'
            'The property is 14 Marlowe Street, Bristol.\n'
            'The agreement begins on 01/09/2026.\n'
            // Gives the library a "requirements" concept to find. The engine
            // never invents one, so a question about requirements can only be
            // proved against a document that states some.
            'Requirements: the deposit must be paid before the start date.',
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

  /// The questions a student or a professional actually types.
  ///
  /// Every one of these was a dead end from the Assistant tab. Four answered
  /// "Open the document you want first — this works on one document at a
  /// time", which is the app declining a question it had everything it needed
  /// to answer; the rest were sent to retrieval as though the words in them —
  /// "latest", "purpose", "simply", "information" — were printed on a page
  /// somewhere, and came back "I could not find that".
  ///
  /// The rule they all now follow: a request that names no document is about
  /// the document last worked on, and says which one that was.
  group('natural questions from the Home assistant', () {
    /// Asserts a real answer, and that nothing was answered about a document
    /// the user was never told about.
    Future<AssistantAnswer> expectAnswered(String question) async {
      final answer = await askGlobally(question);
      expectGrounded(answer);
      return answer;
    }

    test('23. "What is this document about?" describes a real document',
        () async {
      await seedLibrary();

      final answer = await expectAnswered('What is this document about?');

      expect(answer.kind, AnswerKind.explanation);
      expect(
        answer.citations.single.documentId,
        newest,
        reason: '"this document" from the library means the one last worked on',
      );
      expect(
        answer.text,
        contains('Electricity bill August'),
        reason: 'a document the assistant chose must be named, so a wrong '
            'guess is visible instead of being mistaken for a fact',
      );
    });

    test('24. "Explain this document" is not a request to go and open one',
        () async {
      await seedLibrary();

      final answer = await expectAnswered('Explain this document');

      expect(answer.kind, AnswerKind.explanation);
      expect(answer.text, isNot(contains('Open the document')));
    });

    test('25. "What is this section about?" answers rather than deflecting',
        () async {
      await seedLibrary();

      final answer = await expectAnswered('What is this section about?');

      expect(answer.kind, AnswerKind.explanation);
    });

    test('26. "What is the purpose of this document?" is an about question',
        () async {
      await seedLibrary();

      final answer = await expectAnswered(
        'What is the purpose of this document?',
      );

      expect(
        answer.kind,
        AnswerKind.explanation,
        reason: '"purpose" asks what a thing is, and was being searched for as '
            'though a page had the word printed on it',
      );
    });

    test('27. "Explain it simply" explains rather than hunting for "simply"',
        () async {
      await seedLibrary();

      final answer = await expectAnswered('Explain it simply');

      expect(answer.kind, AnswerKind.explanation);
    });

    test('28. "Summarize my latest document" picks the newest, not the word',
        () async {
      await seedLibrary();

      final answer = await expectAnswered('Summarize my latest document');

      expect(answer.kind, AnswerKind.summary);
      expect(answer.citations.single.documentId, newest);
      expect(
        answer.text.toLowerCase(),
        isNot(contains('could not find')),
        reason: 'this searched for the literal word "latest"',
      );
    });

    test('29. "What are the important points?" summarises something real',
        () async {
      await seedLibrary();

      final answer = await expectAnswered('What are the important points?');

      expect(answer.kind, AnswerKind.summary);
      expect(answer.citations.single.documentId, newest);
    });

    test('30. "Give me the important information from this document" is the '
        'digest', () async {
      await seedLibrary();

      final answer = await expectAnswered(
        'Give me the important information from this document',
      );

      expect(answer.kind, AnswerKind.extraction);
      expect(
        answer.text,
        contains('248.60'),
        reason: 'a request made entirely of request words asks what the '
            'documents hold, not for a page containing "information"',
      );
    });

    test('31. "What are the main requirements?" answers from the page',
        () async {
      await seedLibrary();

      final answer = await expectAnswered('What are the main requirements?');

      expect(answer.text, contains('deposit'));
    });

    test('32. "Who should I contact?" finds the contact', () async {
      await seedLibrary();

      final answer = await expectAnswered('Who should I contact?');

      expect(answer.text, contains('priya.nair@university.edu'));
    });

    test('33. "What does this document say about Flutter?" stays a search',
        () async {
      await seedLibrary();

      final answer = await expectAnswered(
        'What does this document say about Flutter?',
      );

      expect(
        answer.text,
        contains('Flutter'),
        reason: 'naming a topic is an ordinary question and must not be '
            'swallowed by the about-the-document rule',
      );
      expect(answer.citations.single.documentId, 'report');
    });

    test('34. "What is the total amount?" still answers with the total',
        () async {
      await seedLibrary();

      final answer = await expectAnswered('What is the total amount?');

      expect(answer.text, contains('248.60'));
    });

    test('35. "What is the deadline?" reaches the dates', () async {
      await seedLibrary();

      final answer = await expectAnswered('What is the deadline?');

      expect(answer.text, contains('05/04/2026'));
    });

    test('36. "Summarize my electricity bill" beats the recency rule',
        () async {
      await seedLibrary();

      final answer = await expectAnswered('Summarize my electricity bill');

      expect(answer.kind, AnswerKind.summary);
      expect(
        answer.citations.single.documentId,
        'bill',
        reason: 'a document the user named wins over the one last worked on',
      );
    });

    test('37. "Explain the internship report" names the document it read',
        () async {
      await seedLibrary();

      final answer = await expectAnswered('Explain the internship report');

      expect(answer.citations.single.documentId, 'report');
      expect(
        answer.text,
        contains('Internship report'),
        reason: 'in a library-wide thread "this document" identifies nothing',
      );
    });

    test('38. every natural question is answered from somewhere', () async {
      await seedLibrary();

      // The full set from the brief, run in one go. A regression in any single
      // rule shows up here as a named question rather than as a subtle change
      // in one assertion elsewhere.
      for (final question in <String>[
        'What is this document about?',
        'Summarize my electricity bill.',
        'Explain the internship report.',
        'Who is mentioned in the document?',
        'What dates are mentioned?',
        'What is the total amount?',
        'What is the deadline?',
        'What is this section about?',
        'What does this document say about Flutter?',
        'Who should I contact?',
        'What are the important points?',
        'Tell me the main requirements.',
        'What is the purpose of this document?',
        'Explain it simply.',
        'Give me the important information from this document.',
      ]) {
        final answer = await askGlobally(question);

        expect(
          answer.kind,
          isIn(<AnswerKind>[
            AnswerKind.grounded,
            AnswerKind.extraction,
            AnswerKind.summary,
            AnswerKind.explanation,
          ]),
          reason: '"$question" was not answered: ${answer.text}',
        );
        expect(
          answer.citations,
          isNotEmpty,
          reason: '"$question" answered without saying where from',
        );
      }
    });
  });

  group('a document in scope is preferred over the library', () {
    test('39. an unnamed question inside a document never leaves it', () async {
      await seedLibrary();

      // The report is the *oldest* document, so an answer about it can only
      // have come from the scope rather than from the recency fallback.
      for (final question in <String>[
        'What is this document about?',
        'Explain this document',
        'What are the important points?',
        'What is the purpose of this document?',
      ]) {
        final answer = (await repository.ask(
          question,
          documentId: 'report',
        )).valueOrNull!;

        expectGrounded(answer);
        expect(
          answer.citations.map((citation) => citation.documentId).toSet(),
          <String>{'report'},
          reason: '"$question" left the document it was asked in',
        );
      }
    });

    test('40. a scoped answer does not announce the title already on screen',
        () async {
      await seedLibrary();

      final scoped = (await repository.ask(
        'What is this document about?',
        documentId: 'report',
      )).valueOrNull!;

      expect(scoped.text, startsWith('This document'));
    });
  });

  group('names are reported conservatively', () {
    test('41. a heading is not a person', () async {
      await seedLibrary();

      final answer = await askGlobally('Who is mentioned?');

      expect(
        answer.text,
        isNot(contains('Flashlight Controller')),
        reason: 'a section heading is capitalised like a name and is not one',
      );
      expect(answer.text, contains('Daniel Okafor'));
    });

    test('42. a company is not a person', () async {
      await seedLibrary();

      final answer = await askGlobally('Who is mentioned?');

      expect(
        answer.text,
        isNot(contains('Northwind Utilities')),
        reason: 'a run ending in a sectoral suffix is an organisation',
      );
      expect(answer.text, contains('Marcus Webb'));
    });

    test('43. the people who are there are still all found', () async {
      await seedLibrary();

      final answer = await askGlobally('Who is mentioned?');

      for (final person in <String>[
        'Daniel Okafor',
        'Priya Nair',
        'Marcus Webb',
        'Aisha Rahman',
        'Gregor Lantz',
      ]) {
        expect(answer.text, contains(person), reason: 'lost $person');
      }
    });
  });

  group('the examples offered are examples that work', () {
    test('44. every suggested question answers when tapped', () async {
      await seedLibrary();

      final suggestions = (await repository.suggestedQuestions()).valueOrNull!;
      expect(suggestions, isNotEmpty);

      // The whole promise of an example prompt. One that comes back "I could
      // not find that" teaches the user the assistant does not work, using a
      // question the app itself chose to put in front of them.
      for (final question in suggestions) {
        final answer = await askGlobally(question);

        expect(
          answer.kind,
          isIn(<AnswerKind>[
            AnswerKind.grounded,
            AnswerKind.extraction,
            AnswerKind.summary,
            AnswerKind.explanation,
          ]),
          reason: 'offered "$question" and answered: ${answer.text}',
        );
        expect(answer.citations, isNotEmpty, reason: question);
      }
    });

    test('45. the offer names the user’s own newest document', () async {
      await seedLibrary();

      final suggestions = (await repository.suggestedQuestions()).valueOrNull!;

      expect(suggestions, contains(LibraryQuestions.summariseLatest));
      expect(
        suggestions,
        contains(LibraryQuestions.about('Electricity bill August')),
        reason: 'an example naming a document the user does not have cannot '
            'be tapped',
      );
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
