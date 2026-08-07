import 'dart:io';

import 'package:docuai/hive_registrar.g.dart';
import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/features/assistant/data/datasources/chat_history_local_data_source.dart';
import 'package:docuai/src/features/assistant/data/models/chat_message_model.dart';
import 'package:docuai/src/features/assistant/data/repositories/retrieval_assistant_repository.dart';
import 'package:docuai/src/features/assistant/domain/entities/assistant_answer.dart';
import 'package:docuai/src/features/assistant/domain/entities/chat_message.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/search/domain/entities/search_hit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';

void main() {
  late Directory tempDir;
  late Box<ChatMessageModel> box;
  late ChatHistoryLocalDataSource history;
  late FakeSearchRepository search;
  late FakeDocumentRepository documents;
  late RetrievalAssistantRepository repository;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_assistant_test');
    Hive.init(p.join(tempDir.path, 'hive'));
    Hive.registerAdapters();
  });

  setUp(() async {
    box = await Hive.openBox<ChatMessageModel>(
      'chat_${DateTime.now().microsecondsSinceEpoch}',
    );
    history = ChatHistoryLocalDataSource(box);
    search = FakeSearchRepository();
    documents = FakeDocumentRepository();
    repository = RetrievalAssistantRepository(
      search: search,
      documents: documents,
      history: history,
    );
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

  /// Puts documents behind both the search index and the library.
  void library(List<Document> library) {
    for (final document in library) {
      documents.seed(document);
    }
    search.results = <SearchHit>[
      for (final document in library)
        SearchHit(
          document: document,
          score: 5 - library.indexOf(document).toDouble(),
        ),
    ];
  }

  group('answering', () {
    test('quotes the passage that answers the question', () async {
      library(<Document>[
        documentWith(
          id: 'lease',
          title: 'Rental agreement',
          pageTexts: <String>[
            'The tenant shall maintain the property.\n'
                'The deposit is 1,200.00 EUR payable on signing.\n'
                'Notice is one calendar month.',
          ],
        ),
      ]);

      final answer =
          (await repository.ask('How much is the deposit?')).valueOrNull!;

      expect(answer.text, contains('1,200.00 EUR'));
      expect(answer.isGrounded, isTrue);
      expect(answer.source, AnswerSource.retrieval);
    });

    test('the answer is quoted verbatim, never composed', () async {
      const sentence = 'The deposit is 1,200.00 EUR payable on signing.';
      library(<Document>[
        documentWith(
          id: 'lease',
          title: 'Rental agreement',
          pageTexts: <String>[sentence],
        ),
      ]);

      final answer =
          (await repository.ask('How much is the deposit?')).valueOrNull!;

      expect(
        answer.text,
        sentence,
        reason: 'nothing may be introduced that was not on the page',
      );
    });

    test('cites the document and page it quoted', () async {
      library(<Document>[
        documentWith(
          id: 'lease',
          title: 'Rental agreement',
          pageTexts: <String>[
            'Unrelated opening clause about nothing much at all.',
            'The deposit is 1,200.00 EUR payable on signing.',
          ],
        ),
      ]);

      final answer =
          (await repository.ask('How much is the deposit?')).valueOrNull!;

      expect(answer.citations, isNotEmpty);
      expect(answer.citations.first.documentId, 'lease');
      expect(answer.citations.first.documentTitle, 'Rental agreement');
      expect(answer.citations.first.pageIndex, 1);
      expect(answer.citations.first.pageLabel, 'Page 2');
      expect(answer.citations.first.snippet, contains('deposit'));
    });

    test('admits when nothing matches rather than quoting something else',
        () async {
      library(<Document>[
        documentWith(
          id: 'lease',
          title: 'Rental agreement',
          pageTexts: <String>['The tenant shall maintain the property.'],
        ),
      ]);

      final answer =
          (await repository.ask('What is the helicopter model?')).valueOrNull!;

      expect(answer.text, RetrievalAssistantRepository.notFoundMessage);
      expect(answer.isGrounded, isFalse);
      expect(answer.citations, isEmpty);
    });

    test('says so specifically when no document has been read yet', () async {
      final unread = buildDocument(
        id: 'unread',
        title: 'Scanned but unread',
        pages: <DocumentPage>[buildPage(id: 'p', index: 0)],
      );
      library(<Document>[unread]);

      final answer = (await repository.ask('deposit amount')).valueOrNull!;

      expect(
        answer.text,
        RetrievalAssistantRepository.noTextMessage,
        reason: '"not found" would send the user looking for a phrasing '
            'problem they do not have',
      );
    });

    test('an empty library says so, rather than "not found"', () async {
      search.results = <SearchHit>[];

      final answer = (await repository.ask('anything at all')).valueOrNull!;

      expect(answer.isGrounded, isFalse);
      expect(answer.kind, AnswerKind.emptyLibrary);
      expect(answer.text, RetrievalAssistantRepository.emptyLibraryMessage);
    });

    test('a stocked library that matched nothing reports no match', () async {
      documents.seed(
        documentWith(
          id: 'other',
          title: 'Unrelated',
          pageTexts: <String>['Entirely unrelated content about gardening.'],
        ),
      );
      search.results = <SearchHit>[];

      final answer = (await repository.ask('helicopter model')).valueOrNull!;

      expect(answer.kind, AnswerKind.noMatch);
      expect(answer.text, RetrievalAssistantRepository.notFoundMessage);
      expect(answer.documentsSearched, 1);
    });
  });

  group('context assembly', () {
    test('offers at most one citation per page', () async {
      library(<Document>[
        documentWith(
          id: 'lease',
          title: 'Rental agreement',
          pageTexts: <String>[
            'The deposit is due on signing.\n'
                'The deposit is refundable.\n'
                'The deposit is held in escrow.',
          ],
        ),
      ]);

      final answer = (await repository.ask('deposit')).valueOrNull!;

      expect(
        answer.citations,
        hasLength(1),
        reason: 'a page matching three times is one place to look',
      );
    });

    test('caps how much any one document contributes', () async {
      library(<Document>[
        documentWith(
          id: 'long',
          title: 'Long document',
          pageTexts: <String>[
            'The deposit is due on signing.',
            'The deposit is refundable in full.',
            'The deposit is held in an escrow account.',
            'The deposit is returned within 30 days.',
          ],
        ),
      ]);

      final answer = (await repository.ask('deposit')).valueOrNull!;

      expect(
        answer.citations,
        hasLength(RetrievalAssistantRepository.maxPassagesPerDocument),
      );
    });

    test('draws on more than one document when both are relevant', () async {
      library(<Document>[
        documentWith(
          id: 'lease',
          title: 'Rental agreement',
          pageTexts: <String>['The deposit is 1,200.00 EUR on signing.'],
        ),
        documentWith(
          id: 'receipt',
          title: 'Deposit receipt',
          pageTexts: <String>['Deposit received in full, thank you.'],
        ),
      ]);

      final answer = (await repository.ask('deposit')).valueOrNull!;

      expect(
        answer.citedDocumentIds.toSet(),
        <String>{'lease', 'receipt'},
      );
    });

    test('never exceeds the citation cap', () async {
      library(<Document>[
        for (var i = 0; i < 6; i++)
          documentWith(
            id: 'doc$i',
            title: 'Document $i',
            pageTexts: <String>['The deposit is mentioned in document $i.'],
          ),
      ]);

      final answer = (await repository.ask('deposit')).valueOrNull!;

      expect(
        answer.citations.length,
        lessThanOrEqualTo(RetrievalAssistantRepository.maxPassages),
      );
    });
  });

  group('scoping to one document', () {
    test('reads only the named document and never searches', () async {
      final scoped = documentWith(
        id: 'scoped',
        title: 'Just this one',
        pageTexts: <String>['The deposit is 500.00 EUR.'],
      );
      documents.seed(scoped);
      library(<Document>[
        documentWith(
          id: 'other',
          title: 'Another',
          pageTexts: <String>['The deposit is 900.00 EUR.'],
        ),
      ]);
      documents.seed(scoped);

      final answer = (await repository.ask(
        'How much is the deposit?',
        documentId: 'scoped',
      )).valueOrNull!;

      expect(answer.text, contains('500.00'));
      expect(
        search.receivedQueries,
        isEmpty,
        reason: 'the user already said where to look',
      );
    });

    test('propagates a failure to load the scoped document', () async {
      final result = await repository.ask('anything', documentId: 'missing');

      expect(result.failureOrNull, isA<StorageFailure>());
    });
  });

  group('failures', () {
    test('propagates a search failure', () async {
      search.searchFailure = const StorageFailure('Index unreadable.');

      final result = await repository.ask('deposit');

      expect(result.failureOrNull, isA<StorageFailure>());
    });

    test('a question with no usable terms is an honest empty answer', () async {
      final answer = (await repository.ask('?!  ...')).valueOrNull!;

      expect(answer.isGrounded, isFalse);
    });
  });

  group('transcript', () {
    ChatMessage message(String id, ChatRole role, String text) => ChatMessage(
      id: id,
      role: role,
      text: text,
      createdAt: DateTime.utc(2026, 8, 4).add(Duration(seconds: id.length)),
    );

    test('appends and reads back in order', () async {
      await repository.appendMessage(
        message('a', ChatRole.user, 'first question'),
      );
      await repository.appendMessage(
        message('bb', ChatRole.assistant, 'first answer'),
      );

      final transcript = await repository.watchHistory().first;

      expect(
        transcript.map((entry) => entry.text),
        <String>['first question', 'first answer'],
      );
      expect(transcript.first.isFromUser, isTrue);
    });

    test('round-trips citations through Hive', () async {
      await repository.appendMessage(
        ChatMessage(
          id: 'a',
          role: ChatRole.assistant,
          text: 'The deposit is 500.00 EUR.',
          createdAt: DateTime.utc(2026, 8, 4),
          citations: const <AnswerCitation>[
            AnswerCitation(
              documentId: 'lease',
              documentTitle: 'Rental agreement',
              pageIndex: 2,
              snippet: '…the deposit is 500.00 EUR…',
            ),
          ],
        ),
      );

      final restored = (await repository.watchHistory().first).single;

      expect(restored.citations.single.documentTitle, 'Rental agreement');
      expect(restored.citations.single.pageLabel, 'Page 3');
    });

    test('round-trips a failed turn', () async {
      await repository.appendMessage(
        ChatMessage(
          id: 'a',
          role: ChatRole.assistant,
          text: '',
          createdAt: DateTime.utc(2026, 8, 4),
          errorMessage: 'The index could not be read.',
        ),
      );

      final restored = (await repository.watchHistory().first).single;

      expect(restored.hasFailed, isTrue);
      expect(restored.errorMessage, 'The index could not be read.');
    });

    test('clearHistory empties the transcript', () async {
      await repository.appendMessage(message('a', ChatRole.user, 'question'));

      await repository.clearHistory();

      expect(await repository.watchHistory().first, isEmpty);
    });

    test('drops the oldest turns past the cap', () async {
      for (var i = 0; i < ChatHistoryLocalDataSource.maxMessages + 10; i++) {
        await repository.appendMessage(
          ChatMessage(
            id: 'm$i',
            role: ChatRole.user,
            text: 'question $i',
            createdAt: DateTime.utc(2026, 8, 4).add(Duration(seconds: i)),
          ),
        );
      }

      final transcript = await repository.watchHistory().first;

      expect(transcript, hasLength(ChatHistoryLocalDataSource.maxMessages));
      expect(
        transcript.first.text,
        'question 10',
        reason: 'the oldest turns are the ones dropped',
      );
    });

    test('re-emits when a turn is appended', () async {
      final emissions = <List<ChatMessage>>[];
      final subscription = repository.watchHistory().listen(emissions.add);
      await Future<void>.delayed(Duration.zero);

      await repository.appendMessage(message('a', ChatRole.user, 'hello'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await subscription.cancel();

      expect(emissions.first, isEmpty);
      expect(emissions.last, hasLength(1));
    });
  });
}
