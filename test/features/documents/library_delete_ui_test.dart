import 'dart:io';

import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/features/documents/presentation/providers/document_providers.dart';
import 'package:docuai/src/features/documents/presentation/screens/documents_screen.dart';
import 'package:docuai/src/features/documents/presentation/widgets/document_actions.dart';
import 'package:docuai/src/features/documents/presentation/widgets/document_tile.dart';
import 'package:docuai/src/features/search/presentation/providers/search_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

/// Drives a delete the way a user does — overflow menu, confirmation dialog —
/// and checks the library reacts without anything asking it to.
void main() {
  late FakeDocumentRepository documents;
  late FakeSearchRepository search;
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_delete_ui');
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  setUp(() {
    documents = FakeDocumentRepository();
    search = FakeSearchRepository();
  });

  tearDown(() => documents.dispose());

  Future<void> pumpLibrary(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(documents),
          searchRepositoryProvider.overrideWithValue(search),
          storagePathsProvider.overrideWithValue(StoragePaths(tempDir)),
        ],
        child: const MaterialApp(home: DocumentsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> deleteFirstTile(WidgetTester tester) async {
    await tester.tap(find.byType(PopupMenuButton<DocumentAction>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
  }

  testWidgets('the tile disappears as soon as the delete completes', (
    tester,
  ) async {
    documents.seed(buildDocument(id: 'a', title: 'Water bill'));
    await pumpLibrary(tester);
    expect(find.text('Water bill'), findsOneWidget);

    await deleteFirstTile(tester);

    expect(
      find.text('Water bill'),
      findsNothing,
      reason: 'the library must react to the store, not to being told',
    );
    expect(find.text('No documents yet'), findsOneWidget);
    expect(documents.deletedIds, <String>['a']);
  });

  testWidgets('the other documents stay', (tester) async {
    documents
      ..seed(
        buildDocument(
          id: 'keep',
          title: 'Keep me',
          updatedAt: DateTime.utc(2026, 8, 1),
        ),
      )
      ..seed(
        buildDocument(
          id: 'remove',
          title: 'Remove me',
          updatedAt: DateTime.utc(2026, 8, 2),
        ),
      );
    await pumpLibrary(tester);
    expect(find.byType(DocumentTile), findsNWidgets(2));

    // Newest first, so "Remove me" is the first tile.
    await deleteFirstTile(tester);

    expect(find.text('Remove me'), findsNothing);
    expect(find.text('Keep me'), findsOneWidget);
    expect(find.byType(DocumentTile), findsOneWidget);
  });

  testWidgets('cancelling the confirmation deletes nothing', (tester) async {
    documents.seed(buildDocument(id: 'a', title: 'Water bill'));
    await pumpLibrary(tester);

    await tester.tap(find.byType(PopupMenuButton<DocumentAction>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Water bill'), findsOneWidget);
    expect(documents.deletedIds, isEmpty);
  });

  testWidgets('a rename is reflected in the list without a refresh', (
    tester,
  ) async {
    documents.seed(buildDocument(id: 'a', title: 'Before'));
    await pumpLibrary(tester);

    await tester.tap(find.byType(PopupMenuButton<DocumentAction>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'After');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();

    expect(find.text('After'), findsOneWidget);
    expect(find.text('Before'), findsNothing);
  });

  testWidgets('a failed delete leaves the document and reports why', (
    tester,
  ) async {
    documents.seed(buildDocument(id: 'a', title: 'Water bill'));
    await pumpLibrary(tester);

    documents.saveFailure = const StorageFailure('Storage is read-only.');
    await deleteFirstTile(tester);

    expect(find.text('Water bill'), findsOneWidget);
    expect(find.text('Storage is read-only.'), findsOneWidget);
  });
}
