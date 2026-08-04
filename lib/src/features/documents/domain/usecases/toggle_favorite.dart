import '../../../../core/error/result.dart';
import '../entities/document.dart';
import '../repositories/document_repository.dart';

/// Flips a document's favourite flag.
///
/// Deliberately does **not** touch `updatedAt`: favouriting is a bookmark, not
/// an edit, and bumping the timestamp would jump the document to the top of a
/// newest-first library for no reason the user would recognise.
class ToggleFavorite {
  const ToggleFavorite(this._repository);

  final DocumentRepository _repository;

  FutureResult<Document> call(String documentId) async {
    final loaded = await _repository.getDocument(documentId);
    final Document document;
    switch (loaded) {
      case Failed(:final failure):
        return Failed(failure);
      case Success(:final value):
        document = value;
    }

    return _repository.saveDocument(
      document.copyWith(isFavorite: !document.isFavorite),
    );
  }
}
