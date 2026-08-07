import 'dart:io';

import 'package:docuai/hive_registrar.g.dart';
import 'package:docuai/src/app.dart';
import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/core/storage/storage_providers.dart';
import 'package:docuai/src/features/assistant/data/datasources/chat_history_local_data_source.dart';
import 'package:docuai/src/features/assistant/data/models/chat_message_model.dart';
import 'package:docuai/src/features/documents/data/datasources/documents_box.dart';
import 'package:docuai/src/features/documents/data/models/document_model.dart';
import 'package:docuai/src/features/search/data/datasources/search_index_local_data_source.dart';
import 'package:docuai/src/features/search/presentation/providers/search_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// Phase 0 widget tests: routing, shell chrome and theming.
///
/// These are deliberately **read-only** with respect to storage. `testWidgets`
/// runs its body inside a fake-async zone that does not drive real file I/O to
/// completion, so an `await box.put(...)` triggered from a tap never resolves
/// and the test hangs until it times out. Reading an already-open Hive box is
/// synchronous and safe; anything that writes belongs in a plain `test()` —
/// see `test/core/theme_mode_controller_test.dart`.
void main() {
  late Directory tempDir;
  late Box<dynamic> settingsBox;
  late Box<DocumentModel> documentsBox;
  late Box<dynamic> searchIndexBox;
  late Box<ChatMessageModel> chatHistoryBox;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_widget_test');
    Hive.init(tempDir.path);
    Hive.registerAdapters();
    settingsBox = await Hive.openBox<dynamic>('settings_widget_test');
    documentsBox = await Hive.openBox<DocumentModel>('documents_widget_test');
    searchIndexBox = await Hive.openBox<dynamic>('search_index_widget_test');
    chatHistoryBox = await Hive.openBox<ChatMessageModel>('chat_widget_test');
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  /// Boots the real app with test-owned storage substituted in — the same
  /// substitution `bootstrap()` performs at runtime.
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsBoxProvider.overrideWithValue(settingsBox),
          documentsBoxProvider.overrideWithValue(documentsBox),
          searchIndexBoxProvider.overrideWithValue(searchIndexBox),
          chatHistoryBoxProvider.overrideWithValue(chatHistoryBox),
          // Opening the search screen would otherwise reconcile the index,
          // which writes to Hive — exactly the real file I/O the note above
          // says never completes inside a `testWidgets` zone. The reconciler
          // has its own tests in `test/features/search/`.
          searchIndexReadyProvider.overrideWith((ref) async {}),
          storagePathsProvider.overrideWithValue(StoragePaths(tempDir)),
        ],
        child: const DocuAiApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('boots to the documents screen with its shell chrome', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.text('DocuAI'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.widgetWithText(FloatingActionButton, 'Scan'), findsOneWidget);
  });

  testWidgets('navigates between all three shell branches', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Search'));
    await tester.pumpAndSettle();
    expect(find.text('Find documents'), findsOneWidget);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Assistant'));
    await tester.pumpAndSettle();
    expect(find.text('Ask about your documents'), findsOneWidget);

    await tester.tap(find.widgetWithText(NavigationDestination, 'Documents'));
    await tester.pumpAndSettle();
    expect(find.text('No documents yet'), findsOneWidget);
  });

  testWidgets('pushes the scan route above the shell', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Scan'));
    await tester.pumpAndSettle();

    expect(find.text('Scan document'), findsOneWidget);
    // A full-screen route must cover the bottom navigation bar.
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('opens settings and defaults the theme to System', (
    tester,
  ) async {
    await pumpApp(tester);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsOneWidget);

    final segmented = tester.widget<SegmentedButton<ThemeMode>>(
      find.byType(SegmentedButton<ThemeMode>),
    );
    expect(segmented.selected, {ThemeMode.system});
  });

  testWidgets('applies the Material 3 seeded colour scheme', (tester) async {
    await pumpApp(tester);

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
    expect(app.theme?.colorScheme.brightness, Brightness.light);
    expect(app.darkTheme?.colorScheme.brightness, Brightness.dark);
  });
}
