/// Application-wide constants that are not tied to a single feature.
///
/// Feature-specific values belong in that feature's own folder — this file is
/// reserved for things the whole app agrees on.
abstract final class AppConstants {
  /// Display name used in the UI. The Android launcher label lives in
  /// `AndroidManifest.xml` and must be kept in sync with this value.
  static const String appName = 'DocuAI';

  static const String appTagline = 'Intelligent Document Scanner';

  /// Directory (relative to the app documents dir) that holds scanned pages
  /// and generated PDFs.
  static const String documentsDirName = 'documents';

  /// Filename for a page captured when the document is first created.
  ///
  /// Only used at creation, where the indices are known to be 0..n and unique.
  static String pageFileName(int index) =>
      'page_${index.toString().padLeft(3, '0')}.jpg';

  /// Filename for a page added or replaced after creation.
  ///
  /// Derived from the page's own id rather than its position, because position
  /// changes. Once pages can be reordered or deleted, a name like `page_003`
  /// either has to be renamed on disk — slow, and destructive if it fails
  /// halfway — or it silently stops describing where the page actually sits.
  /// Order lives in `DocumentPage.index` alone; the filename only has to be
  /// unique.
  static String pageFileNameFor(String pageId) =>
      'page_${pageId.replaceAll('-', '').substring(0, 12)}.jpg';

  /// Subfolder holding pictures placed inside a written document's text.
  ///
  /// Separate from the pages, which sit directly in the document's folder.
  /// Not tidiness: the sweep that deletes pictures nobody references any more
  /// runs over this directory, and a scanned page sharing it would be one
  /// mis-scoped delete away from being destroyed by an unrelated text edit.
  static const String inlineImagesDirName = 'inline';

  /// Filename for a picture placed in a document's text.
  ///
  /// Named from its own id rather than from a position, because a picture has
  /// no position — it sits wherever its reference sits in the text, and that
  /// moves every time a line above it is typed.
  static String inlineImageFileName(String imageId) =>
      '${imageId.replaceAll('-', '').substring(0, 12)}.jpg';

  /// Debounce applied to search-as-you-type so we do not re-query the index on
  /// every keystroke.
  static const Duration searchDebounce = Duration(milliseconds: 300);

  /// Standard animation duration for shared transitions across the app.
  static const Duration defaultAnimationDuration = Duration(milliseconds: 250);
}
