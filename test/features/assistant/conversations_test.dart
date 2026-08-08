import 'dart:io';

import 'package:docuai/hive_registrar.g.dart';
import 'package:docuai/src/features/assistant/data/datasources/chat_history_local_data_source.dart';
import 'package:docuai/src/features/assistant/data/models/answer_citation_model.dart';
import 'package:docuai/src/features/assistant/data/models/chat_message_model.dart';
import 'package:docuai/src/features/assistant/data/repositories/retrieval_assistant_repository.dart';
import 'package:docuai/src/features/assistant/domain/entities/chat_message.dart';
import 'package:docuai/src/features/assistant/domain/entities/conversation.dart';
import 'package:docuai/src/features/assistant/domain/usecases/ask_assistant.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/search/domain/entities/search_hit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';

/// Threads, rather than one endless transcript.
///
/// A conversation is derived from its messages: named by the first thing asked,
/// aged by the last thing said, and non-existent until something is in it. That
/// is what makes "start a new one" free and "delete this one" precise.
void main() {
  late Directory tempDir;
  late Box<ChatMessageModel> box;
  late ChatHistoryLocalDataSource history;
  late FakeSearchRepository search;
  late FakeDocumentRepository documents;
  late RetrievalAssistantRepository repository;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_threads');
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

  var counter = 0;
  ChatMessage message(
    String text, {
    required String conversationId,
    String? documentId,
    ChatRole role = ChatRole.user,
  }) => ChatMessage(
    id: 'm${counter++}',
    role: role,
    text: text,
    createdAt: DateTime.utc(2026, 8, 8).add(Duration(seconds: counter)),
    conversationId: conversationId,
    documentId: documentId,
  );

  group('threads are separate', () {
    test('two conversations do not see each other', () async {
      await repository.appendMessage(
        message('about the lease', conversationId: 'a'),
      );
      await repository.appendMessage(
        message('about the boiler', conversationId: 'b'),
      );

      expect(
        (await repository.watchHistory(conversationId: 'a').first).single.text,
        'about the lease',
      );
      expect(
        (await repository.watchHistory(conversationId: 'b').first).single.text,
        'about the boiler',
      );
    });

    test('a thread survives being reopened — this is the restore path', () async {
      await repository.appendMessage(message('first', conversationId: 'a'));
      await repository.appendMessage(message('second', conversationId: 'a'));

      // A fresh repository over the same box is what relaunching the app does.
      final reopened = RetrievalAssistantRepository(
        search: search,
        documents: documents,
        history: ChatHistoryLocalDataSource(box),
      );

      expect(
        (await reopened.watchHistory(conversationId: 'a').first)
            .map((m) => m.text),
        <String>['first', 'second'],
      );
    });

    test('an unspoken thread is empty rather than an error', () async {
      expect(
        await repository.watchHistory(conversationId: 'never-used').first,
        isEmpty,
      );
    });
  });

  group('the list of conversations', () {
    test('names each thread after the first question in it', () async {
      await repository.appendMessage(
        message('How much is the deposit?', conversationId: 'a'),
      );
      await repository.appendMessage(
        message('An answer.', conversationId: 'a', role: ChatRole.assistant),
      );

      final threads = await repository.watchConversations().first;

      expect(threads.single.title, 'How much is the deposit?');
      expect(threads.single.messageCount, 2);
    });

    test('an assistant turn never names a thread', () async {
      await repository.appendMessage(
        message('Something went wrong.', conversationId: 'a', role: ChatRole.assistant),
      );
      await repository.appendMessage(
        message('The real question', conversationId: 'a'),
      );

      final threads = await repository.watchConversations().first;
      expect(threads.single.title, 'The real question');
    });

    test('a thread with nothing askable falls back to a name', () async {
      await repository.appendMessage(
        message('', conversationId: 'a', role: ChatRole.assistant),
      );

      expect(
        (await repository.watchConversations().first).single.title,
        Conversation.untitled,
      );
    });

    test('the most recently spoken in comes first', () async {
      await repository.appendMessage(message('older', conversationId: 'old'));
      await repository.appendMessage(message('newer', conversationId: 'new'));

      expect(
        (await repository.watchConversations().first).map((c) => c.id),
        <String>['new', 'old'],
      );
    });

    test('a document scope lists only its own threads', () async {
      await repository.appendMessage(
        message('about the lease', conversationId: 'a', documentId: 'lease'),
      );
      await repository.appendMessage(
        message('about everything', conversationId: 'b'),
      );

      expect(
        (await repository.watchConversations(documentId: 'lease').first)
            .map((c) => c.id),
        <String>['a'],
      );
      expect(
        (await repository.watchConversations().first).map((c) => c.id),
        containsAll(<String>['a', 'b']),
      );
    });

    test('a thread remembers which document it is about', () async {
      await repository.appendMessage(
        message('scoped', conversationId: 'a', documentId: 'lease'),
      );

      final thread = (await repository.watchConversations().first).single;
      expect(thread.documentId, 'lease');
      expect(thread.isAboutOneDocument, isTrue);
    });

    test('a long question is shortened for the row', () async {
      await repository.appendMessage(
        message('x' * 200, conversationId: 'a'),
      );

      final title = (await repository.watchConversations().first).single.title;
      expect(title.length, lessThanOrEqualTo(60));
      expect(title, endsWith('…'));
    });
  });

  group('deleting one', () {
    test('leaves every other thread untouched', () async {
      await repository.appendMessage(message('keep me', conversationId: 'a'));
      await repository.appendMessage(message('delete me', conversationId: 'b'));

      await repository.deleteConversation('b');

      expect(
        (await repository.watchConversations().first).map((c) => c.id),
        <String>['a'],
      );
      expect(
        await repository.watchHistory(conversationId: 'b').first,
        isEmpty,
      );
    });

    test('deleting one that never existed changes nothing', () async {
      await repository.appendMessage(message('keep me', conversationId: 'a'));

      await repository.deleteConversation('nope');

      expect(await repository.watchConversations().first, hasLength(1));
    });
  });

  group('trimming', () {
    test('caps each thread on its own', () async {
      // One busy thread must not evict another the user never touched.
      for (var i = 0; i < ChatHistoryLocalDataSource.maxMessages + 5; i++) {
        await repository.appendMessage(
          message('busy $i', conversationId: 'busy'),
        );
      }
      await repository.appendMessage(message('quiet', conversationId: 'quiet'));

      expect(
        await repository.watchHistory(conversationId: 'busy').first,
        hasLength(ChatHistoryLocalDataSource.maxMessages),
      );
      expect(
        (await repository.watchHistory(conversationId: 'quiet').first)
            .single
            .text,
        'quiet',
        reason: 'a global cap would have taken this one first',
      );
    });
  });

  group('asking', () {
    test('both turns land in the thread they were asked in', () async {
      final document = buildDocument(
        id: 'lease',
        title: 'Lease',
        pages: <DocumentPage>[
          buildPage(
            id: 'p0',
            index: 0,
            text: 'The deposit is 500.00 EUR.',
            ocrStatus: OcrStatus.completed,
          ),
        ],
      );
      documents.seed(document);
      search.results = <SearchHit>[SearchHit(document: document, score: 5)];

      await AskAssistant(repository, idGenerator: () => 'id-${counter++}')(
        'How much is the deposit?',
        conversationId: 'thread-1',
        documentId: 'lease',
      );

      final turns = await repository
          .watchHistory(conversationId: 'thread-1')
          .first;
      expect(turns, hasLength(2));
      expect(turns.every((m) => m.conversation == 'thread-1'), isTrue);
      expect(turns.every((m) => m.documentId == 'lease'), isTrue);
    });
  });

  group('transcripts written before threads existed', () {
    test('become one conversation per scope, not orphans', () async {
      // Records the previous version wrote: no conversationId at all.
      await box.put(
        'old-library',
        ChatMessageModel(
          id: 'old-library',
          role: 'user',
          text: 'asked before threads existed',
          createdAt: DateTime.utc(2026, 5),
          citations: const <AnswerCitationModel>[],
          errorMessage: null,
          documentId: null,
          conversationId: null,
        ),
      );
      await box.put(
        'old-scoped',
        ChatMessageModel(
          id: 'old-scoped',
          role: 'user',
          text: 'asked about the lease',
          createdAt: DateTime.utc(2026, 5, 2),
          citations: const <AnswerCitationModel>[],
          errorMessage: null,
          documentId: 'lease',
          conversationId: null,
        ),
      );

      final threads = await repository.watchConversations().first;

      expect(threads, hasLength(2));
      expect(
        threads.map((c) => c.id),
        containsAll(<String>['legacy:library', 'legacy:lease']),
      );
      expect(
        (await repository
                .watchHistory(conversationId: 'legacy:library')
                .first)
            .single
            .text,
        'asked before threads existed',
      );
    });

    test('an old thread can be deleted like any other', () async {
      await box.put(
        'old',
        ChatMessageModel(
          id: 'old',
          role: 'user',
          text: 'old question',
          createdAt: DateTime.utc(2026, 5),
          citations: const <AnswerCitationModel>[],
          errorMessage: null,
          documentId: null,
          conversationId: null,
        ),
      );

      await repository.deleteConversation('legacy:library');

      expect(await repository.watchConversations().first, isEmpty);
    });
  });

  group('the transcript stream', () {
    test('a turn written before the first read is not lost', () async {
      // No await between subscribing and writing. A stream that snapshots and
      // *then* subscribes drops this event, leaving a transcript that is
      // already wrong with nothing left to correct it.
      final seen = <List<ChatMessage>>[];
      final subscription = repository
          .watchHistory(conversationId: 'a')
          .listen(seen.add);
      await repository.appendMessage(message('raced', conversationId: 'a'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await subscription.cancel();

      expect(seen.last.single.text, 'raced');
    });

    test('the conversation list re-emits when a thread is added', () async {
      final seen = <List<Conversation>>[];
      final subscription = repository.watchConversations().listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      await repository.appendMessage(message('new thread', conversationId: 'a'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await subscription.cancel();

      expect(seen.first, isEmpty);
      expect(seen.last, hasLength(1));
    });
  });
}
