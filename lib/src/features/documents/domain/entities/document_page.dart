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

/// Where a page's content came from.
///
/// Provenance and display only — no behaviour keys off this. Whether a page has
/// a file on disk is answered by [DocumentPage.hasImage], because that is the
/// question every caller actually has, and because a record whose kind and
/// path disagreed would otherwise crash rather than degrade.
///
/// [scanned] and [imported] are byte-identical JPEGs by the time they are
/// stored, and deliberately share every code path. They are told apart so the
/// library can say where a page came from, not so they can behave differently.
enum PageKind {
  /// Captured with the camera through the ML Kit document scanner.
  scanned,

  /// Chosen from the device's own photos.
  imported,

  /// Written in the app. Has no image, and nothing to recognise.
  text,
}

/// A single page of a document.
///
/// Originally a scan and nothing else. It is now a unit of content that *may*
/// carry an image, which is what lets a typed page and a scanned page share one
/// text field — and so one search index, one passage extractor and one editor.
/// The alternative, a separate body on the document, would have put a second
/// copy of the text beside this one for every consumer to reconcile.
///
/// [imagePath] is stored **relative** to the app documents directory and must
/// be resolved through `StoragePaths.absolutePath` before use — Android does
/// not guarantee the absolute sandbox path survives a reinstall.
@freezed
abstract class DocumentPage with _$DocumentPage {
  const DocumentPage._();

  const factory DocumentPage({
    required String id,

    /// Relative path to the page JPEG, e.g. `documents/<docId>/page_001.jpg`,
    /// or null for a page that has no image.
    String? imagePath,

    /// Zero-based position within the parent document.
    required int index,

    /// The page's text: recognised for an image page, authored for a text one.
    ///
    /// One field for both, which is the whole point of the model. Editing a
    /// scan's recognised text and editing a typed page are the same operation.
    @Default('') String text,

    @Default(OcrStatus.pending) OcrStatus ocrStatus,

    @Default(PageKind.scanned) PageKind kind,

    /// When a person last wrote this page's text, or null if nobody has.
    ///
    /// Recorded because recognition and correction disagree about who owns the
    /// field. Recognition may re-read a page at any time; a correction is work
    /// that cannot be reproduced by re-reading, so the two need telling apart.
    DateTime? textEditedAt,
  }) = _DocumentPage;

  /// True when OCR produced something worth indexing or searching.
  bool get hasText => text.trim().isNotEmpty;

  /// Whether there is a file on disk behind this page.
  ///
  /// Read from the path rather than the kind on purpose. This is the guard
  /// before every image read, delete and render, so it has to describe what is
  /// actually there — a page whose kind says `scanned` but whose path is
  /// missing should render as empty, not throw.
  bool get hasImage => imagePath != null;

  /// True for a page whose content was written rather than captured.
  bool get isText => kind == PageKind.text;

  /// Whether this page's text has been corrected by hand.
  ///
  /// The guard on re-running recognition: re-reading a page reproduces what the
  /// scanner can see, and would silently discard what a person read instead.
  bool get hasEditedText => textEditedAt != null;

  /// Human-friendly label used in the page carousel and OCR progress UI.
  String get displayLabel => 'Page ${index + 1}';
}
