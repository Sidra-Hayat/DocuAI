import 'dart:io';

import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/features/documents/presentation/providers/document_providers.dart';
import 'package:docuai/src/features/documents/presentation/screens/document_detail_screen.dart';
import 'package:docuai/src/features/documents/presentation/screens/documents_screen.dart';
import 'package:docuai/src/features/documents/presentation/widgets/document_actions.dart';
import 'package:docuai/src/features/search/presentation/providers/search_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

/// Deleting the document you are currently looking at.
///
/// The detail screen resolves its document from the same stream as the library,
/// so the record disappears underneath it at the moment of deletion — which is
/// exactly when it also tries to navigate away.
void main() {
  late FakeDocumentRepository documents;
  late FakeSearchRepository search;
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_detail_delete');
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  setUp(() {
    documents = FakeDocumentRepository()
      ..seed(buildDocument(id: 'a', title: 'Water bill'));
    search = FakeSearchRepository();
  });

  tearDown(() => documents.dispose());

  Future<void> pumpDetail(WidgetTester tester) async {
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

    // Push the detail route the way the library tile does.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (context) => const DocumentDetailScreen(documentId: 'a'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('deleting the open document pops back to the library', (
    tester,
  ) async {
    await pumpDetail(tester);
    expect(find.byType(DocumentDetailScreen), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<DocumentAction>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason: 'navigating away must not touch a context that is already gone',
    );
    expect(find.byType(DocumentDetailScreen), findsNothing);
    expect(find.text('No documents yet'), findsOneWidget);
    expect(documents.deletedIds, <String>['a']);
  });
}

void unawaited(Future<void> future) {}
