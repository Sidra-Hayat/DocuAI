import 'dart:io';

import 'package:docuai/hive_registrar.g.dart';
import 'package:docuai/src/app.dart';
import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/core/storage/storage_providers.dart';
import 'package:docuai/src/features/assistant/data/datasources/chat_history_local_data_source.dart';
import 'package:docuai/src/features/assistant/data/models/chat_message_model.dart';
import 'package:docuai/src/features/documents/data/datasources/documents_box.dart';
import 'package:docuai/src/features/documents/data/models/document_model.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/presentation/providers/document_providers.dart';
import 'package:docuai/src/features/search/data/datasources/search_index_local_data_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import '../../helpers/ui.dart';

/// The whole app — real router, real `StatefulShellRoute`, real Hive — driven
/// through the UI a user actually touches.
///
/// Every other document test isolates a layer: the repository stream, the
/// provider graph, a screen on its own, the delete flow against a fake. This is
/// the only configuration that puts all of them together behind the shell, and
/// it is the one being run on the device.
void main() {
  late Directory tempDir;
  late Box<dynamic> settingsBox;
  late Box<DocumentModel> documentsBox;
  late Box<dynamic> searchIndexBox;
  late Box<ChatMessageModel> chatBox;
  late ProviderContainer container;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_app_docs');
    Hive.init(p.join(tempDir.path, 'hive'));
    Hive.registerAdapters();
  });

  // Deliberately does not call `Hive.close()`.
  //
  // Disposing a container cancels the box watch subscription the library
  // stream opened, and that cancellation was created inside a fake-async zone
  // that no longer runs — so it never completes, and `Hive.close()` waits on
  // it forever. The test isolate ends here regardless; the temp directory is
  // best-effort because Windows may still hold a handle on a box file.
  tearDownAll(() async {
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } on FileSystemException {
      // The OS reclaims it.
    }
  });

  // Fresh boxes per test rather than clearing shared ones. Disposing the
  // container cancels a Hive watch subscription that was created inside a
  // fake-async zone, and that cancellation never completes — a reused box is
  // left wedged and the next `clear()` waits on it forever.
  setUp(() async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    settingsBox = await Hive.openBox<dynamic>('settings_$stamp');
    documentsBox = await Hive.openBox<DocumentModel>('documents_$stamp');
    searchIndexBox = await Hive.openBox<dynamic>('index_$stamp');
    chatBox = await Hive.openBox<ChatMessageModel>('chat_$stamp');

    container = ProviderContainer(
      overrides: [
        settingsBoxProvider.overrideWithValue(settingsBox),
        documentsBoxProvider.overrideWithValue(documentsBox),
        searchIndexBoxProvider.overrideWithValue(searchIndexBox),
        chatHistoryBoxProvider.overrideWithValue(chatBox),
        storagePathsProvider.overrideWithValue(StoragePaths(tempDir)),
      ],
    );
  });

  tearDown(() => container.dispose());

  Future<List<String>> sourceImages(int count) async {
    final source = await Directory(
      p.join(tempDir.path, 'incoming'),
    ).create(recursive: true);

    return <String>[
      for (var i = 0; i < count; i++)
        (await File(
          p.join(
            source.path,
            'cap_${DateTime.now().microsecondsSinceEpoch}_$i.jpg',
          ),
        ).writeAsBytes(<int>[0xFF, 0xD8, 0xFF, 0xD9])).path,
    ];
  }

  Future<Document> createDocument(String title) async {
    final result = await container
        .read(documentRepositoryProvider)
        .createFromImages(
          title: title,
          sourceImagePaths: await sourceImages(1),
        );
    return result.valueOrNull!;
  }

  /// Real file and Hive I/O runs on the real event loop. A `testWidgets` body
  /// is a fake-async zone that never drives it to completion, so anything a tap
  /// started has to be flushed here or it simply never finishes.
  Future<void> settle(WidgetTester tester) => tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );

  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const DocuAiApp()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a deleted document leaves the library immediately', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await createDocument('Water bill');
      await createDocument('Rental agreement');
    });

    await pumpApp(tester);
    expect(find.text('Water bill'), findsOneWidget);
    expect(find.text('Rental agreement'), findsOneWidget);

    // Newest first, so "Rental agreement" is the first row.
    await tapDocumentAction(tester, 'Delete');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    await settle(tester);
    await tester.pumpAndSettle();

    expect(
      find.text('Rental agreement'),
      findsNothing,
      reason: 'the library must not wait for a restart',
    );
    expect(find.text('Water bill'), findsOneWidget);
    expect(documentsBox.values.map((d) => d.title), <String>['Water bill']);
  });

  testWidgets('deleting the last document shows the empty state', (
    tester,
  ) async {
    await tester.runAsync(() => createDocument('Only one'));

    await pumpApp(tester);
    expect(find.text('Only one'), findsOneWidget);

    await tapDocumentAction(tester, 'Delete');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    await settle(tester);
    await tester.pumpAndSettle();

    expect(find.text('No documents yet'), findsOneWidget);
  });

  testWidgets('renaming from the library throws nothing and updates the row', (
    tester,
  ) async {
    await tester.runAsync(() => createDocument('Before'));

    await pumpApp(tester);

    await tapDocumentAction(tester, 'Rename');
    await enterDialogText(tester, 'After');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();

    await settle(tester);
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason: 'no framework assertion may escape the rename flow',
    );
    expect(find.text('After'), findsOneWidget);
    expect(find.text('Before'), findsNothing);
  });

  testWidgets('deleting the open document pops back and clears the row', (
    tester,
  ) async {
    await tester.runAsync(() => createDocument('Water bill'));

    await pumpApp(tester);

    // Into the document, through the shell's own navigator.
    await tester.tap(find.text('Water bill'));
    await tester.pumpAndSettle();
    await settle(tester);
    await tester.pumpAndSettle();

    await tapDocumentAction(tester, 'Delete');
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    await settle(tester);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('No documents yet'), findsOneWidget);
  });

  testWidgets('renaming the open document updates the library behind it', (
    tester,
  ) async {
    await tester.runAsync(() => createDocument('Before'));

    await pumpApp(tester);
    await tester.tap(find.text('Before'));
    await tester.pumpAndSettle();
    await settle(tester);
    await tester.pumpAndSettle();

    await tapDocumentAction(tester, 'Rename');
    await enterDialogText(tester, 'After');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();

    await settle(tester);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    // Back to the library, which was mounted underneath the whole time.
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('After'), findsOneWidget);
    expect(find.text('Before'), findsNothing);
  });
}
