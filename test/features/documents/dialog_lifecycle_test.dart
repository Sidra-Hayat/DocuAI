import 'dart:io';

import 'package:docuai/src/core/router/app_routes.dart';
import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/documents/presentation/providers/document_providers.dart';
import 'package:docuai/src/features/documents/presentation/screens/document_detail_screen.dart';
import 'package:docuai/src/features/documents/presentation/screens/documents_screen.dart';
import 'package:docuai/src/features/documents/presentation/screens/manage_pages_screen.dart';
import 'package:docuai/src/features/search/presentation/providers/search_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/fakes.dart';
import '../../helpers/ui.dart';

/// `_dependents.isEmpty is not true`, and the family of mistakes behind it.
///
/// The assertion fires when something that a widget subtree depends on is
/// disposed while that subtree is still mounted. Two shapes cause it here, and
/// both are easy to reintroduce because both look correct:
///
///  * A `TextEditingController` created beside `showDialog` and disposed when
///    its future completes. That future completes on `Navigator.pop`, which is
///    when the dismiss *animation starts* — the dialog stays mounted, holding
///    a controller that has already been torn down.
///  * Reading `ref` or `BuildContext` after an await, on a subtree the awaited
///    action has since destroyed. A delete is the sharp case: the document is
///    gone, the screen showing it is gone, and anything still reaching for
///    them is reaching into a disposed scope.
///
/// `tester.takeException()` is what actually catches these — an assertion
/// thrown during a frame is reported there rather than failing the tap.
void main() {
  late Directory tempDir;
  late FakeDocumentRepository documents;
  late FakeSearchRepository search;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_lifecycle');
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  setUp(() {
    documents = FakeDocumentRepository();
    search = FakeSearchRepository();
  });

  tearDown(() => documents.dispose());

  Widget wrap(Widget home) => ProviderScope(
    overrides: [
      documentRepositoryProvider.overrideWithValue(documents),
      searchRepositoryProvider.overrideWithValue(search),
      storagePathsProvider.overrideWithValue(StoragePaths(tempDir)),
    ],
    child: MaterialApp(home: home),
  );

  Document billWith({List<DocumentPage>? pages}) => buildDocument(
    id: 'doc',
    title: 'Water bill',
    pages:
        pages ??
        <DocumentPage>[
          buildPage(id: 'p0', index: 0),
          buildPage(id: 'p1', index: 1, imagePath: 'a/p1.jpg'),
        ],
  );

  group('renaming', () {
    Future<void> openRename(WidgetTester tester) async {
      documents.seed(billWith());
      await tester.pumpWidget(wrap(const DocumentsScreen()));
      await tester.pumpAndSettle();

      await tapDocumentAction(tester, 'Rename');
    }

    testWidgets('confirming a rename throws nothing', (tester) async {
      await openRename(tester);

      await enterDialogText(tester, 'Electricity bill');
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      // Pumped past the dismiss animation on purpose: the controller was
      // disposed at its start, and the frames after it are where the
      // assertion used to land.
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(documents.store['doc']!.title, 'Electricity bill');
    });

    testWidgets('cancelling a rename throws nothing', (tester) async {
      await openRename(tester);

      await enterDialogText(tester, 'Discarded');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(documents.store['doc']!.title, 'Water bill');
    });

    testWidgets('submitting from the keyboard throws nothing', (tester) async {
      await openRename(tester);

      await enterDialogText(tester, 'From the keyboard');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(documents.store['doc']!.title, 'From the keyboard');
    });

    testWidgets('renaming twice in a row throws nothing', (tester) async {
      // The second dialog builds while the first is still animating out, which
      // is the window a controller disposed too early lives in.
      await openRename(tester);
      await enterDialogText(tester, 'First');
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pump();

      await tester.pumpAndSettle();
      await tapDocumentAction(tester, 'Rename');

      await enterDialogText(tester, 'Second');
      await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(documents.store['doc']!.title, 'Second');
    });
  });

  group('deleting a document', () {
    testWidgets('from the library throws nothing', (tester) async {
      documents.seed(billWith());
      await tester.pumpWidget(wrap(const DocumentsScreen()));
      await tester.pumpAndSettle();

      await tapDocumentAction(tester, 'Delete');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(documents.deletedIds, <String>['doc']);
      expect(find.text('No documents yet'), findsOneWidget);
    });

    testWidgets('from the screen showing it throws nothing', (tester) async {
      // The hard one: the confirmation is dismissed, the document disappears,
      // and the screen that ran the delete is torn down by the same emission.
      documents.seed(billWith());
      await tester.pumpWidget(
        wrap(const DocumentDetailScreen(documentId: 'doc')),
      );
      await tester.pumpAndSettle();

      await tapDocumentAction(tester, 'Delete');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(documents.deletedIds, <String>['doc']);
    });

    testWidgets('cancelling deletes nothing and throws nothing', (
      tester,
    ) async {
      documents.seed(billWith());
      await tester.pumpWidget(wrap(const DocumentsScreen()));
      await tester.pumpAndSettle();

      await tapDocumentAction(tester, 'Delete');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(documents.deletedIds, isEmpty);
    });
  });

  group('deleting a page', () {
    testWidgets('from the page manager throws nothing', (tester) async {
      documents.seed(billWith());
      await tester.pumpWidget(wrap(const ManagePagesScreen(documentId: 'doc')));
      await tester.pumpAndSettle();

      await openPageActions(tester);
      await tapSheetAction(tester, 'Delete this page');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(documents.store['doc']!.pages, hasLength(1));
    });

    testWidgets('deleting the row the menu belongs to throws nothing', (
      tester,
    ) async {
      // The list rebuilds without that row while the dialog is dismissing, so
      // the menu's own subtree goes away underneath it.
      documents.seed(
        billWith(
          pages: <DocumentPage>[
            buildPage(id: 'p0', index: 0),
            buildPage(id: 'p1', index: 1, imagePath: 'a/p1.jpg'),
            buildPage(id: 'p2', index: 2, imagePath: 'a/p2.jpg'),
          ],
        ),
      );
      await tester.pumpWidget(wrap(const ManagePagesScreen(documentId: 'doc')));
      await tester.pumpAndSettle();

      // The last row, whose subtree the delete destroys.
      await openPageActions(tester, index: 2);
      await tapSheetAction(tester, 'Delete this page');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(documents.store['doc']!.pages.map((page) => page.id), <String>[
        'p0',
        'p1',
      ]);
    });
  });

  group('creating a text document', () {
    testWidgets('the title dialog throws nothing on either outcome', (
      tester,
    ) async {
      // The same controller-ownership trap as rename, in a dialog written
      // later — which is exactly how this class of defect comes back.
      // A real router, because the creation path resolves GoRouter *before*
      // awaiting — which is the lifecycle-safe order, and the reason a bare
      // MaterialApp cannot host it.
      final router = GoRouter(
        initialLocation: '/',
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (context, state) => const DocumentsScreen(),
            routes: <RouteBase>[
              GoRoute(
                path: 'edit/:id/:page',
                name: AppRoutes.editPageName,
                builder: (context, state) =>
                    const Scaffold(body: Text('editor')),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            documentRepositoryProvider.overrideWithValue(documents),
            searchRepositoryProvider.overrideWithValue(search),
            storagePathsProvider.overrideWithValue(StoragePaths(tempDir)),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Write one'));
      await tester.pumpAndSettle();
      await enterDialogText(tester, 'Meeting notes');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Write one'));
      await tester.pumpAndSettle();
      await enterDialogText(tester, 'Meeting notes');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        documents.store.values.map((document) => document.title),
        contains('Meeting notes'),
      );
    });
  });
}
