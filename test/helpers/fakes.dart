import 'dart:async';

import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/features/assistant/domain/entities/assistant_answer.dart';
import 'package:docuai/src/features/assistant/domain/entities/chat_message.dart';
import 'package:docuai/src/features/assistant/domain/repositories/assistant_repository.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/documents/domain/repositories/document_repository.dart';
import 'package:docuai/src/features/export/domain/repositories/export_repository.dart';
import 'package:docuai/src/features/ocr/domain/repositories/ocr_repository.dart';
import 'package:docuai/src/features/scanner/domain/repositories/scanner_repository.dart';
import 'package:docuai/src/features/search/domain/entities/search_hit.dart';
import 'package:docuai/src/features/search/domain/repositories/search_repository.dart';

/// In-memory doubles for every repository contract.
///
/// Hand-written rather than generated with `mockito` or `mocktail`: the domain
/// layer has no dependencies, and these tests should not introduce one. Each
/// fake also records what it was asked to do, which is most of what the use
/// case tests assert on.

/// A fixed instant, so tests can assert on exact timestamps.
final DateTime kNow = DateTime.utc(2026, 8, 4, 12);
final DateTime kEarlier = DateTime.utc(2026, 8, 1, 9);

DateTime fixedClock() => kNow;

/// Builds a document with sensible defaults; override only what the test cares
/// about.
Document buildDocument({
  String id = 'doc-1',
  String title = 'Lecture notes',
  DateTime? createdAt,
  DateTime? updatedAt,
  List<DocumentPage>? pages,
  List<String> tags = const <String>[],
  String? pdfPath,
  bool isFavorite = false,
}) => Document(
  id: id,
  title: title,
  createdAt: createdAt ?? kEarlier,
  updatedAt: updatedAt ?? kEarlier,
  pages: pages ?? <DocumentPage>[buildPage()],
  tags: tags,
  pdfPath: pdfPath,
  isFavorite: isFavorite,
);

DocumentPage buildPage({
  String id = 'page-1',
  String imagePath = 'documents/doc-1/page_000.jpg',
  int index = 0,
  String text = '',
  OcrStatus ocrStatus = OcrStatus.pending,
}) => DocumentPage(
  id: id,
  imagePath: imagePath,
  index: index,
  text: text,
  ocrStatus: ocrStatus,
);

class FakeDocumentRepository implements DocumentRepository {
  final Map<String, Document> store = <String, Document>{};
  final StreamController<List<Document>> _controller =
      StreamController<List<Document>>.broadcast();

  /// When set, every read fails with this instead of hitting [store].
  Failure? getFailure;

  /// When set, every write fails with this.
  Failure? saveFailure;

  final List<Document> savedDocuments = <Document>[];
  List<String>? lastSourceImagePaths;
  String? lastCreatedTitle;
  final List<String> deletedIds = <String>[];

  void seed(Document document) {
    store[document.id] = document;
    _emit();
  }

  /// Mirrors the real repository: a seed emission on subscribe, then one per
  /// mutation.
  ///
  /// The fake used to emit only from [seed], so every write went unobserved and
  /// no widget test could ever have caught a screen failing to react to a
  /// delete. A double that stays silent where the real thing speaks does not
  /// test the wiring, it hides it.
  @override
  Stream<List<Document>> watchDocuments() async* {
    yield _sorted();
    yield* _controller.stream;
  }

  /// Newest first, the order `DocumentLocalDataSource.readAll` guarantees.
  List<Document> _sorted() => store.values.toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  void _emit() {
    if (!_controller.isClosed) _controller.add(_sorted());
  }

  @override
  FutureResult<List<Document>> getDocuments() async {
    final failure = getFailure;
    if (failure != null) return Failed(failure);
    return Success(store.values.toList());
  }

  @override
  FutureResult<Document> getDocument(String id) async {
    final failure = getFailure;
    if (failure != null) return Failed(failure);
    final document = store[id];
    if (document == null) {
      return Failed(StorageFailure('No document with id "$id".'));
    }
    return Success(document);
  }

  @override
  FutureResult<Document> createFromImages({
    required String title,
    required List<String> sourceImagePaths,
  }) async {
    lastCreatedTitle = title;
    lastSourceImagePaths = sourceImagePaths;
    final failure = saveFailure;
    if (failure != null) return Failed(failure);

    final document = Document(
      id: 'created-${store.length + 1}',
      title: title,
      createdAt: kNow,
      updatedAt: kNow,
      pages: <DocumentPage>[
        for (var i = 0; i < sourceImagePaths.length; i++)
          buildPage(id: 'page-$i', index: i, imagePath: 'documents/new/$i.jpg'),
      ],
    );
    store[document.id] = document;
    _emit();
    return Success(document);
  }

  @override
  FutureResult<Document> saveDocument(Document document) async {
    final failure = saveFailure;
    if (failure != null) return Failed(failure);
    savedDocuments.add(document);
    store[document.id] = document;
    _emit();
    return Success(document);
  }

  @override
  FutureResult<void> deleteDocument(String id) async {
    final failure = saveFailure;
    if (failure != null) return Failed(failure);
    deletedIds.add(id);
    store.remove(id);
    _emit();
    return const Success<void>(null);
  }

  void dispose() => _controller.close();
}

class FakeSearchRepository implements SearchRepository {
  final List<String> indexedIds = <String>[];
  final List<String> removedIds = <String>[];
  List<SearchHit> results = <SearchHit>[];
  Failure? searchFailure;
  Failure? indexFailure;

  /// Queries actually forwarded by the use case — used to prove short queries
  /// never reach the repository at all.
  final List<String> receivedQueries = <String>[];

  @override
  FutureResult<List<SearchHit>> search(String query) async {
    receivedQueries.add(query);
    final failure = searchFailure;
    if (failure != null) return Failed(failure);
    return Success(results);
  }

  @override
  FutureResult<void> indexDocument(Document document) async {
    final failure = indexFailure;
    if (failure != null) return Failed(failure);
    indexedIds.add(document.id);
    return const Success<void>(null);
  }

  @override
  FutureResult<void> removeFromIndex(String documentId) async {
    removedIds.add(documentId);
    return const Success<void>(null);
  }

  @override
  FutureResult<void> rebuildIndex(List<Document> documents) async {
    indexedIds
      ..clear()
      ..addAll(documents.map((document) => document.id));
    return const Success<void>(null);
  }
}

class FakeScannerRepository implements ScannerRepository {
  Result<List<String>> result = const Success(<String>['/tmp/scan_0.jpg']);
  bool available = true;
  int? lastPageLimit;

  @override
  FutureResult<List<String>> scanPages({int pageLimit = 20}) async {
    lastPageLimit = pageLimit;
    return result;
  }

  @override
  Future<bool> isAvailable() async => available;
}

class FakeOcrRepository implements OcrRepository {
  /// Per-path outcomes. Any path not listed falls back to [defaultResult].
  final Map<String, Result<String>> results = <String, Result<String>>{};
  Result<String> defaultResult = const Success('recognised text');
  final List<String> requestedPaths = <String>[];

  @override
  FutureResult<String> recognizeText(String relativeImagePath) async {
    requestedPaths.add(relativeImagePath);
    return results[relativeImagePath] ?? defaultResult;
  }
}

class FakeExportRepository implements ExportRepository {
  Result<String> buildResult = const Success('documents/doc-1/doc-1.pdf');
  Failure? shareFailure;
  final List<String> sharedPaths = <String>[];
  final List<String> sharedText = <String>[];
  String? lastSubject;
  int buildCount = 0;

  @override
  FutureResult<String> buildPdf(Document document) async {
    buildCount++;
    return buildResult;
  }

  @override
  FutureResult<void> shareFile(String relativePath, {String? subject}) async {
    final failure = shareFailure;
    if (failure != null) return Failed(failure);
    sharedPaths.add(relativePath);
    lastSubject = subject;
    return const Success<void>(null);
  }

  @override
  FutureResult<void> shareText(String text, {String? subject}) async {
    final failure = shareFailure;
    if (failure != null) return Failed(failure);
    sharedText.add(text);
    lastSubject = subject;
    return const Success<void>(null);
  }
}

class FakeAssistantRepository implements AssistantRepository {
  final List<ChatMessage> messages = <ChatMessage>[];
  final List<String> askedQuestions = <String>[];
  String? lastScopedDocumentId;
  Result<AssistantAnswer> answer = const Success(
    AssistantAnswer(text: 'Because the deadline moved.'),
  );
  bool historyCleared = false;

  @override
  FutureResult<AssistantAnswer> ask(
    String question, {
    String? documentId,
  }) async {
    askedQuestions.add(question);
    lastScopedDocumentId = documentId;
    return answer;
  }

  @override
  Stream<List<ChatMessage>> watchHistory() => Stream.value(messages);

  @override
  FutureResult<void> appendMessage(ChatMessage message) async {
    messages.add(message);
    return const Success<void>(null);
  }

  @override
  FutureResult<void> clearHistory() async {
    historyCleared = true;
    messages.clear();
    return const Success<void>(null);
  }
}
