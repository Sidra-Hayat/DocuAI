import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/text/markup.dart';
import 'document_page.dart';

part 'document.freezed.dart';

/// How a document entered the library.
///
/// A different question from [PageKind], which describes one page. A document
/// created by import that later gains a camera page is still an imported
/// document — origin is a fact about history that the pages cannot reconstruct
/// once they have been edited, added to or removed.
enum DocumentSource {
  /// Captured with the camera.
  scanned,

  /// Built from images already on the device.
  imported,

  /// Written in the app.
  created,
}

/// A document: ordered pages plus the metadata the library screen, search index
/// and assistant all read from.
///
/// This is the *domain* representation. Its data-layer counterpart
/// (`DocumentModel`, `@HiveType`, arriving in Phase 2) is a separate class with
/// explicit mapping, so a change to the persisted schema cannot silently
/// reshape business logic — and so nothing in this file imports Hive.
@freezed
abstract class Document with _$Document {
  const Document._();

  const factory Document({
    required String id,
    required String title,
    required DateTime createdAt,
    required DateTime updatedAt,
    @Default(<DocumentPage>[]) List<DocumentPage> pages,
    @Default(<String>[]) List<String> tags,

    /// Relative path to the generated PDF, or `null` if it has not been
    /// exported yet. Regenerated whenever the pages change.
    String? pdfPath,
    @Default(false) bool isFavorite,
    @Default(DocumentSource.scanned) DocumentSource source,
  }) = _Document;

  int get pageCount => pages.length;

  bool get hasPages => pages.isNotEmpty;

  bool get hasPdf => pdfPath != null;

  /// Pages backed by a file on disk — the ones OCR can read and the PDF can
  /// draw. A text-only document has none.
  List<DocumentPage> get imagePages =>
      pages.where((page) => page.hasImage).toList(growable: false);

  bool get hasImagePages => pages.any((page) => page.hasImage);

  /// First page, used as the library thumbnail. `null` for an empty document,
  /// which is only possible transiently while a scan is being persisted.
  ///
  /// Deliberately the first page and not the first *image* page: the cover
  /// should be what the document opens with, and a document that begins with a
  /// typed title page should show that. Callers must handle a cover with no
  /// image — see [DocumentPage.hasImage].
  DocumentPage? get coverPage => pages.isEmpty ? null : pages.first;

  /// All recognised text, in page order, separated by blank lines.
  ///
  /// Computed rather than stored: keeping one copy of the text on the pages
  /// removes any chance of the document-level copy drifting out of sync after a
  /// page is re-scanned or deleted.
  ///
  /// **Pictures are not text.** A written page may place one in its text, and
  /// the reference is stored there as a line — so it is removed here, at the
  /// single point every text consumer reads from. Left in, the name of a JPEG
  /// would be indexed by search and quotable by the assistant.
  ///
  /// For a document containing no pictures this is exactly what it always was:
  /// [Markup.withoutImages] returns its input unchanged, so the same string
  /// yields the same tokens and the same results as before the feature existed.
  /// The emptiness test is [DocumentPage.hasText]'s, applied to the text that
  /// survives — a page holding only a picture has words to contribute in the
  /// same sense a blank page does, which is none.
  String get extractedText => pages
      .map((page) => Markup.withoutImages(page.text))
      .where((text) => text.trim().isNotEmpty)
      .join('\n\n');

  bool get hasText => pages.any((page) => page.hasText);

  /// Aggregate OCR state, resolved most-blocking-first: anything still running
  /// dominates, then anything pending, then any failure. Only when every page
  /// has succeeded is the document itself [OcrStatus.completed].
  ///
  /// Read over [imagePages] alone. A page with no image has nothing to
  /// recognise, and counting one would be more than untidy: the detail screen
  /// starts a recognition run whenever this reports [OcrStatus.pending], and
  /// that run cannot change a status it has no page to work on. A single typed
  /// page would leave the document pending forever, re-triggering on every
  /// open.
  OcrStatus get ocrStatus {
    if (pages.isEmpty) return OcrStatus.pending;

    final recognisable = imagePages;

    // Nothing to recognise is not the same as waiting to be recognised.
    if (recognisable.isEmpty) return OcrStatus.completed;

    if (recognisable.any((page) => page.ocrStatus == OcrStatus.running)) {
      return OcrStatus.running;
    }
    if (recognisable.any((page) => page.ocrStatus == OcrStatus.pending)) {
      return OcrStatus.pending;
    }
    if (recognisable.any((page) => page.ocrStatus == OcrStatus.failed)) {
      return OcrStatus.failed;
    }
    return OcrStatus.completed;
  }

  /// Pages still needing recognition — the work list for a retry, which is why
  /// [OcrStatus.running] is excluded but [OcrStatus.failed] is not.
  ///
  /// Only pages with an image can appear here. Recognition reads a file, so a
  /// page without one is not work that was skipped; it is not work at all.
  List<DocumentPage> get pagesAwaitingOcr => pages
      .where(
        (page) =>
            page.hasImage &&
            (page.ocrStatus == OcrStatus.pending ||
                page.ocrStatus == OcrStatus.failed),
      )
      .toList(growable: false);
}
