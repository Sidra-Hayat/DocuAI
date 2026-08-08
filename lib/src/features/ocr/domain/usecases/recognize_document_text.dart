import '../../../../core/error/result.dart';
import '../../../../core/utils/clock.dart';
import '../../../documents/domain/entities/document.dart';
import '../../../documents/domain/entities/document_page.dart';
import '../../../documents/domain/repositories/document_repository.dart';
import '../../../search/domain/repositories/search_repository.dart';
import '../repositories/ocr_repository.dart';

/// Runs text recognition over a document's outstanding pages, saves the result,
/// and re-indexes it for search.
///
/// The interesting decision here is what happens when one page fails.
/// Recognition is per-image, and the usual cause of a failure is that one photo
/// specifically — a blurred capture, an unreadable angle. Aborting the batch
/// would throw away the pages that did work and leave the document with no text
/// at all, so instead each page records its own outcome, the run continues, and
/// the failed pages stay in `pagesAwaitingOcr` for a retry.
///
/// Only a failure to *load* or *save* the document aborts, because those mean
/// the work cannot be recorded at all.
class RecognizeDocumentText {
  const RecognizeDocumentText({
    required OcrRepository ocr,
    required DocumentRepository documents,
    required SearchRepository search,
    Clock clock = systemClock,
  }) : _ocr = ocr,
       _documents = documents,
       _search = search,
       _now = clock;

  final OcrRepository _ocr;
  final DocumentRepository _documents;
  final SearchRepository _search;
  final Clock _now;

  /// [onProgress] reports `(pagesDone, pagesTotal)` after each page so the UI
  /// can show real progress instead of an indeterminate spinner; `pagesTotal`
  /// counts only the pages this run will touch.
  ///
  /// Set [force] to re-run every page, including ones already completed — the
  /// path behind a manual "re-run recognition" action.
  FutureResult<Document> call(
    String documentId, {
    void Function(int done, int total)? onProgress,
    bool force = false,
  }) async {
    final loaded = await _documents.getDocument(documentId);
    final Document document;
    switch (loaded) {
      case Failed(:final failure):
        return Failed(failure);
      case Success(:final value):
        document = value;
    }

    // `force` re-runs pages that already succeeded, but it must never reach a
    // page with no image. There is nothing to recognise there, and the text on
    // such a page was written by the user — replacing it with the output of a
    // run that has no file to read would be silent data loss.
    final targets = force
        ? document.pages.where((page) => page.hasImage).toList(growable: false)
        : document.pagesAwaitingOcr;
    if (targets.isEmpty) {
      onProgress?.call(0, 0);
      return Success(document);
    }

    final targetIds = targets.map((page) => page.id).toSet();
    final updatedPages = List.of(document.pages);
    var done = 0;

    for (var i = 0; i < updatedPages.length; i++) {
      final page = updatedPages[i];
      if (!targetIds.contains(page.id)) continue;

      final imagePath = page.imagePath;
      if (imagePath == null) continue;

      final recognised = await _ocr.recognizeText(imagePath);
      updatedPages[i] = switch (recognised) {
        Success(:final value) => page.copyWith(
          text: value,
          ocrStatus: OcrStatus.completed,
        ),
        // The page keeps whatever text it already had: a retry that fails
        // should not erase a previous successful run.
        Failed() => page.copyWith(ocrStatus: OcrStatus.failed),
      };

      onProgress?.call(++done, targets.length);
    }

    final saved = await _documents.saveDocument(
      document.copyWith(pages: updatedPages, updatedAt: _now()),
    );

    // Indexing is best-effort. The text is already safely persisted, so a
    // failure here costs discoverability until the next rebuild, not data.
    if (saved case Success(:final value) when value.hasText) {
      await _search.indexDocument(value);
    }

    return saved;
  }
}
