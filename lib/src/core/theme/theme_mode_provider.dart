import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/hive_boxes.dart';
import '../storage/storage_providers.dart';

/// Persisted light/dark/system preference.
///
/// This is deliberately the first end-to-end slice in the app: it proves the
/// Hive → Riverpod → Material 3 chain works before any feature depends on it.
/// Written with a hand-rolled [Notifier] rather than `@riverpod` codegen so the
/// foundation has no build_runner step — generated providers arrive in Phase 1
/// where Freezed entities make them worth the extra build.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final box = ref.watch(settingsBoxProvider);
    final stored = box.get(SettingsKeys.themeMode) as String?;
    return _decode(stored);
  }

  /// Updates the preference and writes it through to disk.
  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await ref
        .read(settingsBoxProvider)
        .put(SettingsKeys.themeMode, mode.name);
  }

  /// Convenience toggle for the settings switch: system → light → dark → system.
  Future<void> cycle() => setThemeMode(switch (state) {
    ThemeMode.system => ThemeMode.light,
    ThemeMode.light => ThemeMode.dark,
    ThemeMode.dark => ThemeMode.system,
  });

  /// Decodes defensively: an unknown or corrupt value falls back to [
  /// ThemeMode.system] rather than throwing on startup.
  static ThemeMode _decode(String? value) => switch (value) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);
