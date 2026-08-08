import '../../../../core/error/result.dart';
import '../../../search/domain/repositories/search_repository.dart';
import '../entities/document.dart';
import '../repositories/document_repository.dart';

/// Saves a page's text and makes the change findable straight away.
///
/// Re-indexing here rather than leaving it to the next rebuild is the whole
/// difference between an edit that takes effect and one that appears to have
/// been ignored: the library redraws from the box watch immediately, so a
/// document whose text changed but whose index did not would sit in the list
/// looking saved while search kept returning the old wording.
///
/// The same reasoning `RecognizeDocumentText` already applies after a scan —
/// this is that path, for text that was typed instead of read.
class EditPageText {
  const EditPageText({
    required DocumentRepository documents,
    required SearchRepository search,
  }) : _documents = documents,
       _search = search;

  final DocumentRepository _documents;
  final SearchRepository _search;

  FutureResult<Document> call({
    required String documentId,
    required String pageId,
    required String text,
  }) async {
    final saved = await _documents.updatePageText(
      documentId: documentId,
      pageId: pageId,
      text: text,
    );

    if (saved case Success(:final value)) {
      // Best-effort, like recognition's: the text is already persisted, so a
      // failure here costs discoverability until the next rebuild, not data.
      if (value.hasText) {
        await _search.indexDocument(value);
      } else {
        // Emptied of every word. Left indexed, it would keep matching the text
        // it no longer contains.
        await _search.removeFromIndex(value.id);
      }
    }

    return saved;
  }
}

/// Appends an empty page to write on.
class AddTextPage {
  const AddTextPage(this._repository);

  final DocumentRepository _repository;

  FutureResult<Document> call(String documentId) =>
      _repository.addTextPage(documentId: documentId);
}
