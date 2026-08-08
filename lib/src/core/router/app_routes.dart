/// Every route path and name in the app, in one place.
///
/// Screens navigate with `context.goNamed(AppRoutes.documentDetailName)` rather
/// than raw strings, so a renamed path is a compile-time change instead of a
/// runtime 404.
abstract final class AppRoutes {
  // ---- Shell branches (bottom navigation) ----------------------------------
  static const String documents = '/documents';
  static const String documentsName = 'documents';

  static const String search = '/search';
  static const String searchName = 'search';

  static const String assistant = '/assistant';
  static const String assistantName = 'assistant';

  // ---- Full-screen routes (pushed above the shell) -------------------------
  static const String settings = '/settings';
  static const String settingsName = 'settings';

  static const String scan = '/scan';
  static const String scanName = 'scan';

  /// Detail route is nested under documents so the back stack stays correct.
  static const String documentDetail = 'detail/:id';
  static const String documentDetailName = 'documentDetail';

  /// Builds the absolute path for a document detail page.
  static String documentDetailPath(String id) => '$documents/detail/$id';

  /// Recognised text, nested under the document it belongs to — so Back from
  /// the reader returns to that document rather than to the library.
  static const String extractedText = 'text';
  static const String extractedTextName = 'extractedText';

  static String extractedTextPath(String id) =>
      '${documentDetailPath(id)}/text';

  /// Full-screen page viewer. The page number is part of the path so the route
  /// restores to the page the user was looking at rather than to the first.
  static const String pageViewer = 'pages/:page';
  static const String pageViewerName = 'pageViewer';

  static String pageViewerPath(String id, int page) =>
      '${documentDetailPath(id)}/pages/$page';

  /// Reorder, delete, rescan and add pages.
  static const String managePages = 'manage';
  static const String managePagesName = 'managePages';

  static String managePagesPath(String id) =>
      '${documentDetailPath(id)}/manage';

  /// The text editor for one page, nested under its document so Back returns
  /// to the document rather than to the library.
  static const String editPage = 'edit/:page';
  static const String editPageName = 'editPage';

  static String editPagePath(String id, String pageId) =>
      '${documentDetailPath(id)}/edit/$pageId';

  /// One conversation, nested under the Assistant tab so Back returns to the
  /// list of threads rather than to wherever it was opened from.
  static const String conversation = 'c/:conversation';
  static const String conversationName = 'conversation';

  static String conversationPath(String id) => '$assistant/c/$id';
}
