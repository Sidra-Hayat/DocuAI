import '../../../../core/error/result.dart';
import '../entities/document.dart';
import '../repositories/document_repository.dart';

/// Loads a single document by id, for the detail screen and for every other
/// use case that starts from an id rather than an entity.
class GetDocument {
  const GetDocument(this._repository);

  final DocumentRepository _repository;

  FutureResult<Document> call(String id) => _repository.getDocument(id);
}
