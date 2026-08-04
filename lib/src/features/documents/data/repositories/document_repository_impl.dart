import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../domain/entities/document.dart';
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
  Stream<List<Document>> watchDocuments() async* {
    yield _toEntities(_local.readAll());

    // `BoxEvent` says which key changed, but the library renders the whole
    // list, and re-reading a metadata box is cheap. Mapping every event to a
    // full re-read keeps this correct for puts, deletes and clears alike.
    yield* _local.watch().map((_) => _toEntities(_local.readAll()));
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
  }) => _guard(() async {
    final model = await _local.create(
      title: title,
      sourceImagePaths: sourceImagePaths,
    );
    return model.toEntity();
  });

  @override
  FutureResult<Document> saveDocument(Document document) => _guard(() async {
    final model = await _local.write(DocumentModel.fromEntity(document));
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
