import '../entities/document.dart';
import '../repositories/document_repository.dart';

/// Streams the document library, newest first.
///
/// A pass-through, and deliberately so: the presentation layer depends on the
/// use case rather than on [DocumentRepository], so when Phase 6 starts folding
/// pinned or archived documents into this list, the change lands here and no
/// widget is touched.
class WatchDocuments {
  const WatchDocuments(this._repository);

  final DocumentRepository _repository;

  Stream<List<Document>> call() => _repository.watchDocuments();
}
