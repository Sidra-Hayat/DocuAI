import 'dart:io';

import 'package:docuai/hive_registrar.g.dart';
import 'package:docuai/src/features/assistant/data/datasources/chat_history_local_data_source.dart';
import 'package:docuai/src/features/assistant/data/models/answer_citation_model.dart';
import 'package:docuai/src/features/assistant/data/models/chat_message_model.dart';
import 'package:docuai/src/features/assistant/data/repositories/retrieval_assistant_repository.dart';
import 'package:docuai/src/features/assistant/domain/entities/chat_message.dart';
import 'package:docuai/src/features/assistant/domain/usecases/ask_assistant.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/search/domain/entities/search_hit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';

/// Conversations are per document, persisted, and restored on return.
void main() {
  late Directory tempDir;
  late Box<ChatMessageModel> box;
  late ChatHistoryLocalDataSource history;
  late FakeSearchRepository search;
  late FakeDocumentRepository documents;
  late RetrievalAssistantRepository repository;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_chat_scope');
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
  ChatMessage message(String text, {String? documentId, ChatRole? role}) =>
      ChatMessage(
        id: 'm${counter++}',
        role: role ?? ChatRole.user,
        text: text,
        createdAt: DateTime.utc(2026, 8, 8).add(Duration(seconds: counter)),
        documentId: documentId,
      );

  group('scoping', () {
    test('a document conversation is separate from the library one', () async {
      await repository.appendMessage(message('about the lease', documentId: 'lease'));
      await repository.appendMessage(message('about everything'));

      final scoped = await repository.watchHistory(documentId: 'lease').first;
      final global = await repository.watchHistory().first;

      expect(scoped.map((m) => m.text), <String>['about the lease']);
      expect(global.map((m) => m.text), <String>['about everything']);
    });

    test('two documents do not see each other', () async {
      await repository.appendMessage(message('lease question', documentId: 'a'));
      await repository.appendMessage(message('bill question', documentId: 'b'));

      expect(
        (await repository.watchHistory(documentId: 'a').first).single.text,
        'lease question',
      );
      expect(
        (await repository.watchHistory(documentId: 'b').first).single.text,
        'bill question',
      );
    });

    test('history survives being read again — this is the restore path', () async {
      await repository.appendMessage(message('first', documentId: 'lease'));
      await repository.appendMessage(message('second', documentId: 'lease'));

      // A fresh repository over the same box is what reopening the screen — or
      // relaunching the app — actually does.
      final reopened = RetrievalAssistantRepository(
        search: search,
        documents: documents,
        history: ChatHistoryLocalDataSource(box),
      );

      final restored = await reopened.watchHistory(documentId: 'lease').first;

      expect(restored.map((m) => m.text), <String>['first', 'second']);
    });
  });

  group('clearing', () {
    test('clears only the named conversation', () async {
      await repository.appendMessage(message('lease', documentId: 'lease'));
      await repository.appendMessage(message('bill', documentId: 'bill'));
      await repository.appendMessage(message('library'));

      await repository.clearHistory(documentId: 'lease');

      expect(await repository.watchHistory(documentId: 'lease').first, isEmpty);
      expect(
        await repository.watchHistory(documentId: 'bill').first,
        hasLength(1),
      );
      expect(await repository.watchHistory().first, hasLength(1));
    });

    test('clearing the library conversation leaves documents alone', () async {
      await repository.appendMessage(message('lease', documentId: 'lease'));
      await repository.appendMessage(message('library'));

      await repository.clearHistory();

      expect(await repository.watchHistory().first, isEmpty);
      expect(
        await repository.watchHistory(documentId: 'lease').first,
        hasLength(1),
      );
    });
  });

  group('trimming', () {
    test('caps each conversation independently', () async {
      // One busy conversation must not evict another the user never touched.
      for (var i = 0; i < ChatHistoryLocalDataSource.maxMessages + 5; i++) {
        await repository.appendMessage(message('busy $i', documentId: 'busy'));
      }
      await repository.appendMessage(message('quiet', documentId: 'quiet'));

      expect(
        await repository.watchHistory(documentId: 'busy').first,
        hasLength(ChatHistoryLocalDataSource.maxMessages),
      );
      expect(
        (await repository.watchHistory(documentId: 'quiet').first).single.text,
        'quiet',
        reason: 'a global cap would have taken this one first',
      );
    });
  });

  group('asking', () {
    Document documentWith(String id, String text) => buildDocument(
      id: id,
      title: 'Doc $id',
      pages: <DocumentPage>[
        buildPage(id: '$id-p', index: 0, text: text, ocrStatus: OcrStatus.completed),
      ],
    );

    test('both turns are stamped with the conversation they belong to', () async {
      final document = documentWith('lease', 'The deposit is 500.00 EUR.');
      documents.seed(document);
      search.results = <SearchHit>[SearchHit(document: document, score: 5)];

      final ask = AskAssistant(
        repository,
        idGenerator: () => 'id-${counter++}',
      );

      await ask('How much is the deposit?', documentId: 'lease');

      final scoped = await repository.watchHistory(documentId: 'lease').first;
      expect(scoped, hasLength(2));
      expect(scoped.every((m) => m.documentId == 'lease'), isTrue);
      expect(
        await repository.watchHistory().first,
        isEmpty,
        reason: 'a scoped question must not land in the library conversation',
      );
    });

    test('an unscoped question stays in the library conversation', () async {
      final document = documentWith('lease', 'The deposit is 500.00 EUR.');
      documents.seed(document);
      search.results = <SearchHit>[SearchHit(document: document, score: 5)];

      final ask = AskAssistant(
        repository,
        idGenerator: () => 'id-${counter++}',
      );

      await ask('How much is the deposit?');

      expect(await repository.watchHistory().first, hasLength(2));
      expect(
        await repository.watchHistory(documentId: 'lease').first,
        isEmpty,
      );
    });
  });

  group('the transcript stream', () {
    test('re-emits when a turn is appended', () async {
      final seen = <List<ChatMessage>>[];
      final subscription = repository
          .watchHistory(documentId: 'lease')
          .listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      await repository.appendMessage(message('hello', documentId: 'lease'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await subscription.cancel();

      expect(seen.first, isEmpty);
      expect(seen.last, hasLength(1));
    });

    test('a turn written before the first read is not lost', () async {
      // No await between subscribing and writing. A stream that snapshots and
      // *then* subscribes drops this event, leaving a transcript that is
      // already wrong with nothing left to correct it.
      final seen = <List<ChatMessage>>[];
      final subscription = repository
          .watchHistory(documentId: 'lease')
          .listen(seen.add);
      await repository.appendMessage(message('raced', documentId: 'lease'));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await subscription.cancel();

      expect(seen.last.single.text, 'raced');
    });
  });

  group('older transcripts', () {
    test('turns written before scoping existed read as library-wide', () async {
      // A record with no documentId is exactly what the previous schema wrote.
      await box.put(
        'legacy',
        ChatMessageModel(
          id: 'legacy',
          role: 'user',
          text: 'asked before scoping existed',
          createdAt: DateTime.utc(2026),
          citations: const <AnswerCitationModel>[],
          errorMessage: null,
          documentId: null,
        ),
      );

      final global = await repository.watchHistory().first;

      expect(global.single.text, 'asked before scoping existed');
    });
  });
}
