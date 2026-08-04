/// Canonical Hive box names and type ids.
///
/// Every box name and adapter type id in the app is declared here so that
/// collisions are impossible to introduce by accident. Hive identifies adapters
/// by a numeric id that is written into the binary payload — **once a type id
/// ships, it can never be reused for a different type** without corrupting
/// existing users' data.
abstract final class HiveBoxes {
  /// Key/value box for user preferences (theme mode, onboarding state, …).
  static const String settings = 'settings';

  /// Document metadata: title, timestamps, tags, OCR text, page paths.
  /// Image bytes are never stored here — only relative paths on disk.
  static const String documents = 'documents';

  /// Inverted search index: token -> list of document ids.
  static const String searchIndex = 'search_index';

  /// Persisted assistant conversations.
  static const String chatHistory = 'chat_history';
}

/// Hive adapter type ids. Append only — never renumber.
abstract final class HiveTypeIds {
  static const int document = 0;
  static const int documentPage = 1;

  /// Reserved and unused. Tags are plain normalised strings on `Document`, so
  /// no adapter ever claimed this id — and renumbering to close the gap would
  /// reinterpret every record already written.
  static const int tag = 2;

  static const int chatMessage = 3;
  static const int answerCitation = 4;
}

/// Keys used inside the [HiveBoxes.settings] box.
abstract final class SettingsKeys {
  static const String themeMode = 'theme_mode';
  static const String onboardingCompleted = 'onboarding_completed';
}
