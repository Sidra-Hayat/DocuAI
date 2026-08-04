import 'package:freezed_annotation/freezed_annotation.dart';

part 'document_page.freezed.dart';

/// Where a page is in the text-recognition lifecycle.
///
/// Persisted per page rather than per document so that a document with one
/// unreadable page is not marked as wholly failed, and so a retry can re-run
/// only the pages that need it.
enum OcrStatus {
  /// Captured but not yet queued for recognition.
  pending,

  /// Currently being processed by ML Kit.
  running,

  /// Recognition finished. Note that a successful run can still yield empty
  /// text — a photo of a blank page is a valid, textless result.
  completed,

  /// Recognition threw. The page keeps its image and can be retried.
  failed;

  bool get isTerminal => this == completed || this == failed;
}

/// A single scanned page.
///
/// [imagePath] is stored **relative** to the app documents directory and must
/// be resolved through `StoragePaths.absolutePath` before use — Android does
/// not guarantee the absolute sandbox path survives a reinstall.
@freezed
abstract class DocumentPage with _$DocumentPage {
  const DocumentPage._();

  const factory DocumentPage({
    required String id,

    /// Relative path to the page JPEG, e.g. `documents/<docId>/page_001.jpg`.
    required String imagePath,

    /// Zero-based position within the parent document.
    required int index,

    /// Text recognised on this page. Empty until OCR runs.
    @Default('') String text,

    @Default(OcrStatus.pending) OcrStatus ocrStatus,
  }) = _DocumentPage;

  /// True when OCR produced something worth indexing or searching.
  bool get hasText => text.trim().isNotEmpty;

  /// Human-friendly label used in the page carousel and OCR progress UI.
  String get displayLabel => 'Page ${index + 1}';
}
