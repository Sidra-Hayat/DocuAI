import 'package:freezed_annotation/freezed_annotation.dart';

import 'document_page.dart';

part 'document.freezed.dart';

/// A scanned document: ordered pages plus the metadata the library screen,
/// search index and assistant all read from.
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
  }) = _Document;

  int get pageCount => pages.length;

  bool get hasPages => pages.isNotEmpty;

  bool get hasPdf => pdfPath != null;

  /// First page, used as the library thumbnail. `null` for an empty document,
  /// which is only possible transiently while a scan is being persisted.
  DocumentPage? get coverPage => pages.isEmpty ? null : pages.first;

  /// All recognised text, in page order, separated by blank lines.
  ///
  /// Computed rather than stored: keeping one copy of the text on the pages
  /// removes any chance of the document-level copy drifting out of sync after a
  /// page is re-scanned or deleted.
  String get extractedText =>
      pages.where((page) => page.hasText).map((page) => page.text).join('\n\n');

  bool get hasText => pages.any((page) => page.hasText);

  /// Aggregate OCR state, resolved most-blocking-first: anything still running
  /// dominates, then anything pending, then any failure. Only when every page
  /// has succeeded is the document itself [OcrStatus.completed].
  OcrStatus get ocrStatus {
    if (pages.isEmpty) return OcrStatus.pending;
    if (pages.any((page) => page.ocrStatus == OcrStatus.running)) {
      return OcrStatus.running;
    }
    if (pages.any((page) => page.ocrStatus == OcrStatus.pending)) {
      return OcrStatus.pending;
    }
    if (pages.any((page) => page.ocrStatus == OcrStatus.failed)) {
      return OcrStatus.failed;
    }
    return OcrStatus.completed;
  }

  /// Pages still needing recognition — the work list for a retry, which is why
  /// [OcrStatus.running] is excluded but [OcrStatus.failed] is not.
  List<DocumentPage> get pagesAwaitingOcr => pages
      .where(
        (page) =>
            page.ocrStatus == OcrStatus.pending ||
            page.ocrStatus == OcrStatus.failed,
      )
      .toList(growable: false);
}
