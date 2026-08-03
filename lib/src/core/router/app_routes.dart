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
}
