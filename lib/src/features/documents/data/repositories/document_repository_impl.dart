import 'dart:async';

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../domain/entities/document.dart';
import '../../domain/entities/document_page.dart';
import '../../domain/repositories/document_repository.dart';
import '../datasources/document_local_data_source.dart';
import '../models/document_model.dart';

/// Turns the local data source's exceptions into `Failure`s, and its models
/// into entities.
///
/// This class is the boundary the README describes: below it everything throws
/// and speaks Hive, above it everything returns a `Result` and speaks pure
/// Dart. It holds no logic of its own beyond that translation — which is why
/// `RenameDocument` and friends exist as use cases rather than as methods here.
class DocumentRepositoryImpl implements DocumentRepository {
  const DocumentRepositoryImpl(this._local);

  final DocumentLocalDataSource _local;

  @override
  Stream<List<Document>> watchDocuments() {
    final controller = StreamController<List<Document>>();
    StreamSubscription<void>? changes;

    void emit() {
      try {
        // The event says which key changed, but the library renders the whole
        // list and re-reading a metadata box is cheap. A full re-read keeps
        // this correct for puts, deletes and clears alike.
        controller.add(_toEntities(_local.readAll()));
      } on CacheException catch (error, stackTrace) {
        controller.addError(
          StorageFailure(error.message, cause: error),
          stackTrace,
        );
      }
    }

    controller.onListen = () {
      // Subscribe *before* the first read.
      //
      // This was an `async*` generator that yielded a snapshot and then
      // `yield*`-ed the change feed, which subscribes only after the first
      // yield has been delivered. Hive's feed is a broadcast stream, so it
      // buffers nothing: a write landing in that window is dropped outright,
      // and the screen is left holding a snapshot that is already wrong with
      // nothing remaining to correct it.
      changes = _local.watch().listen(
        (_) => emit(),
        onError: controller.addError,
        // The feed only ends when the box closes. If that happens while the
        // app is still running, every screen reading this would otherwise
        // freeze on its last value — silently, and until the app is
        // restarted. Surfacing it means a stuck library announces itself
        // instead of looking like a store that simply stopped changing.
        onDone: () {
          controller.addError(
            const StorageFailure(
              'The document store stopped reporting changes.',
            ),
            StackTrace.current,
          );
          controller.close();
        },
      );

      emit();
    };

    controller.onCancel = () async {
      await changes?.cancel();
      changes = null;
    };

    return controller.stream;
  }

  @override
  FutureResult<List<Document>> getDocuments() =>
      _guard(() async => _toEntities(_local.readAll()));

  @override
  FutureResult<Document> getDocument(String id) =>
      _guard(() async => _local.read(id).toEntity());

  @override
  FutureResult<Document> createFromImages({
    required String title,
    required List<String> sourceImagePaths,
    DocumentSource source = DocumentSource.scanned,
    PageKind pageKind = PageKind.scanned,
  }) => _guard(() async {
    final model = await _local.create(
      title: title,
      sourceImagePaths: sourceImagePaths,
      source: source,
      pageKind: pageKind,
    );
    return model.toEntity();
  });

  @override
  FutureResult<Document> createArchive({
    required String title,
    required String fileName,
    required String sourceZipPath,
  }) => _guard(() async {
    final model = await _local.createArchive(
      title: title,
      fileName: fileName,
      sourceZipPath: sourceZipPath,
    );
    return model.toEntity();
  });

  @override
  FutureResult<Document> createTextDocument({required String title}) =>
      _guard(() async {
        final model = await _local.createTextDocument(title: title);
        return model.toEntity();
      });

  @override
  FutureResult<Document> addTextPage({required String documentId}) =>
      _guard(() async {
        final model = await _local.addTextPage(documentId);
        return model.toEntity();
      });

  @override
  FutureResult<String> addInlineImage({
    required String documentId,
    required String sourcePath,
  }) => _guard(() => _local.addInlineImage(documentId, sourcePath));

  @override
  FutureResult<Document> updatePageText({
    required String documentId,
    required String pageId,
    required String text,
  }) => _guard(() async {
    final model = await _local.updatePageText(documentId, pageId, text);
    return model.toEntity();
  });

  @override
  FutureResult<Document> saveDocument(Document document) => _guard(() async {
    final model = await _local.write(DocumentModel.fromEntity(document));
    return model.toEntity();
  });

  @override
  FutureResult<Document> addPages({
    required String documentId,
    required List<String> sourceImagePaths,
    PageKind pageKind = PageKind.scanned,
  }) => _guard(() async {
    final model = await _local.addPages(
      documentId,
      sourceImagePaths,
      pageKind: pageKind,
    );
    return model.toEntity();
  });

  @override
  FutureResult<Document> deletePage({
    required String documentId,
    required String pageId,
  }) => _guard(() async {
    final model = await _local.deletePage(documentId, pageId);
    return model.toEntity();
  });

  @override
  FutureResult<Document> reorderPages({
    required String documentId,
    required List<String> orderedPageIds,
  }) => _guard(() async {
    final model = await _local.reorderPages(documentId, orderedPageIds);
    return model.toEntity();
  });

  @override
  FutureResult<Document> replacePage({
    required String documentId,
    required String pageId,
    required String sourceImagePath,
  }) => _guard(() async {
    final model = await _local.replacePage(documentId, pageId, sourceImagePath);
    return model.toEntity();
  });

  @override
  FutureResult<void> deleteDocument(String id) => _guard(() async {
    try {
      await _local.delete(id);
    } on NotFoundException {
      // Deleting something already gone is the outcome the caller wanted.
    }
  });

  List<Document> _toEntities(List<DocumentModel> models) =>
      models.map((model) => model.toEntity()).toList(growable: false);

  /// Runs [action], mapping every exception it can raise onto a [Failure].
  ///
  /// The bare `catch` at the end is deliberate: Hive and `dart:io` can both
  /// throw types this layer does not enumerate, and letting one escape would
  /// crash the app from inside a repository that promised never to throw.
  Future<Result<T>> _guard<T>(Future<T> Function() action) async {
    try {
      return Success(await action());
    } on NotFoundException catch (error, stackTrace) {
      return Failed(
        StorageFailure(
          'That document no longer exists.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } on CacheException catch (error, stackTrace) {
      return Failed(
        StorageFailure(error.message, cause: error, stackTrace: stackTrace),
      );
    } catch (error, stackTrace) {
      return Failed(
        StorageFailure(
          'Something went wrong reading your documents.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
