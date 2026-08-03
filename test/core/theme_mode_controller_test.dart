import 'dart:io';

import 'package:docuai/src/core/storage/storage_providers.dart';
import 'package:docuai/src/core/theme/theme_mode_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// Persistence tests for the theme preference.
///
/// Written as plain `test()` cases rather than `testWidgets` on purpose: these
/// exercise real Hive writes, and only a plain test runs on the real event loop
/// where file I/O actually completes.
///
/// This is also the first proof that the layering works — a Riverpod notifier
/// is driven here with no widget tree, no emulator and no Flutter bindings
/// beyond the storage plugin itself.
void main() {
  late Directory tempDir;
  late Box<dynamic> settingsBox;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_unit_test');
    Hive.init(tempDir.path);
    settingsBox = await Hive.openBox<dynamic>('settings_unit_test');
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  tearDown(() async {
    await settingsBox.clear();
  });

  /// Builds a container wired to the shared test box, disposed automatically.
  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [settingsBoxProvider.overrideWithValue(settingsBox)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('defaults to system when nothing has been stored', () {
    final container = makeContainer();

    expect(container.read(themeModeProvider), ThemeMode.system);
  });

  test('writes the selected mode through to Hive', () async {
    final container = makeContainer();

    await container
        .read(themeModeProvider.notifier)
        .setThemeMode(ThemeMode.dark);

    expect(container.read(themeModeProvider), ThemeMode.dark);
    expect(settingsBox.get('theme_mode'), 'dark');
  });

  test('restores the stored mode in a fresh container', () async {
    final first = makeContainer();
    await first.read(themeModeProvider.notifier).setThemeMode(ThemeMode.light);

    // A new container simulates the next app launch against the same box.
    final second = makeContainer();

    expect(second.read(themeModeProvider), ThemeMode.light);
  });

  test('cycles system -> light -> dark -> system', () async {
    final container = makeContainer();
    final controller = container.read(themeModeProvider.notifier);

    await controller.cycle();
    expect(container.read(themeModeProvider), ThemeMode.light);

    await controller.cycle();
    expect(container.read(themeModeProvider), ThemeMode.dark);

    await controller.cycle();
    expect(container.read(themeModeProvider), ThemeMode.system);
  });

  test('falls back to system when the stored value is corrupt', () async {
    await settingsBox.put('theme_mode', 'not-a-theme-mode');

    final container = makeContainer();

    expect(container.read(themeModeProvider), ThemeMode.system);
  });
}
