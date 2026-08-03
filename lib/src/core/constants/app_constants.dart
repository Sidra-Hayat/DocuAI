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

  /// Filename pattern for a scanned page inside a document folder.
  static String pageFileName(int index) =>
      'page_${index.toString().padLeft(3, '0')}.jpg';

  /// Debounce applied to search-as-you-type so we do not re-query the index on
  /// every keystroke.
  static const Duration searchDebounce = Duration(milliseconds: 300);

  /// Standard animation duration for shared transitions across the app.
  static const Duration defaultAnimationDuration = Duration(milliseconds: 250);
}
