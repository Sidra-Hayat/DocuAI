import 'dart:io';

import 'package:docuai/src/core/router/app_routes.dart';
import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/documents/presentation/providers/document_providers.dart';
import 'package:docuai/src/features/documents/presentation/screens/page_viewer_screen.dart';
import 'package:docuai/src/features/documents/presentation/widgets/page_edit_actions.dart';
import 'package:docuai/src/features/search/presentation/providers/search_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/fakes.dart';

/// The full-screen viewer.
///
/// It is a media viewer, which is why it forces a dark surround — and why a
/// page that was written rather than photographed needs different treatment
/// inside it. Pinch and pan exist to inspect small print in a photograph; text
/// reflows, so neither means anything for it.
void main() {
  late Directory tempDir;
  late FakeDocumentRepository documents;
  late FakeSearchRepository search;
  String? editedPageId;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_viewer');
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  setUp(() {
    documents = FakeDocumentRepository();
    search = FakeSearchRepository();
    editedPageId = null;
  });

  tearDown(() => documents.dispose());

  Future<void> pumpViewer(WidgetTester tester, {int initialPage = 0}) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) =>
              PageViewerScreen(documentId: 'doc', initialPage: initialPage),
          routes: <RouteBase>[
            GoRoute(
              path: 'edit/:id/:page',
              name: AppRoutes.editPageName,
              builder: (context, state) {
                editedPageId = state.pathParameters['page'];
                return const Scaffold(body: Text('editor'));
              },
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
  }

  Document docWith(List<DocumentPage> pages) =>
      buildDocument(id: 'doc', title: 'Electricity bill', pages: pages);

  group('navigation', () {
    setUp(() {
      documents.seed(
        docWith(<DocumentPage>[
          buildPage(id: 'p0', index: 0),
          buildPage(id: 'p1', index: 1, imagePath: 'a/p1.jpg'),
          buildPage(id: 'p2', index: 2, imagePath: 'a/p2.jpg'),
        ]),
      );
    });

    testWidgets('says which page you are on', (tester) async {
      await pumpViewer(tester);

      expect(find.text('Page 1 of 3'), findsOneWidget);
    });

    testWidgets('moves forward and back', (tester) async {
      await pumpViewer(tester);

      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(find.text('Page 2 of 3'), findsOneWidget);

      await tester.tap(find.byTooltip('Previous page'));
      await tester.pumpAndSettle();
      expect(find.text('Page 1 of 3'), findsOneWidget);
    });

    testWidgets('cannot go back from the first page', (tester) async {
      await pumpViewer(tester);

      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_left),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_right),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('cannot go forward from the last page', (tester) async {
      await pumpViewer(tester, initialPage: 2);

      expect(find.text('Page 3 of 3'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.chevron_right),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('opens at the page it was asked for', (tester) async {
      await pumpViewer(tester, initialPage: 1);

      expect(find.text('Page 2 of 3'), findsOneWidget);
    });
  });

  group('zooming', () {
    testWidgets('a photographed page can be pinched and panned', (
      tester,
    ) async {
      documents.seed(docWith(<DocumentPage>[buildPage(id: 'p0', index: 0)]));

      await pumpViewer(tester);

      expect(find.byType(InteractiveViewer), findsOneWidget);
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      expect(viewer.maxScale, greaterThan(1));
      expect(viewer.panEnabled, isTrue);
    });

    testWidgets('a written page is not zoomable, because text reflows', (
      tester,
    ) async {
      documents.seed(
        docWith(<DocumentPage>[
          buildTextPage(id: 't0', index: 0, text: 'Written by hand.'),
        ]),
      );

      await pumpViewer(tester);

      expect(find.byType(InteractiveViewer), findsNothing);
      expect(find.text('Written by hand.'), findsOneWidget);
    });
  });

  group('written pages', () {
    testWidgets('show their text and offer to edit it', (tester) async {
      documents.seed(
        docWith(<DocumentPage>[
          buildTextPage(id: 't0', index: 0, text: 'The deposit is 500.00 EUR.'),
        ]),
      );

      await pumpViewer(tester);
      expect(find.text('The deposit is 500.00 EUR.'), findsOneWidget);

      await tester.tap(find.text('Edit this page'));
      await tester.pumpAndSettle();

      expect(editedPageId, 't0');
    });

    testWidgets('a blank one says so rather than looking broken', (
      tester,
    ) async {
      documents.seed(
        docWith(<DocumentPage>[buildTextPage(id: 't0', index: 0, text: '')]),
      );

      await pumpViewer(tester);

      expect(find.text('This page is blank'), findsOneWidget);

      await tester.tap(find.text('Write on it'));
      await tester.pumpAndSettle();

      expect(editedPageId, 't0');
    });

    testWidgets('rescanning is not offered for one', (tester) async {
      // There is no image to replace, and swapping written content for a
      // photograph is not a thing anyone means to do.
      documents.seed(
        docWith(<DocumentPage>[
          buildTextPage(id: 't0', index: 0, text: 'Written.'),
          buildPage(id: 'p1', index: 1, imagePath: 'a/p1.jpg'),
        ]),
      );

      await pumpViewer(tester);
      await tester.tap(find.byTooltip('Page actions'));
      await tester.pumpAndSettle();

      expect(find.text('Rescan this page'), findsNothing);
      expect(find.text('Delete this page'), findsOneWidget);
    });

    testWidgets('rescanning is offered for a photographed one', (tester) async {
      documents.seed(
        docWith(<DocumentPage>[
          buildPage(id: 'p0', index: 0),
          buildPage(id: 'p1', index: 1, imagePath: 'a/p1.jpg'),
        ]),
      );

      await pumpViewer(tester);
      await tester.tap(find.byTooltip('Page actions'));
      await tester.pumpAndSettle();

      expect(find.text('Rescan this page'), findsOneWidget);
    });
  });

  group('deleting', () {
    testWidgets('asks first, and says what is lost', (tester) async {
      documents.seed(
        docWith(<DocumentPage>[
          buildPage(id: 'p0', index: 0),
          buildPage(id: 'p1', index: 1, imagePath: 'a/p1.jpg'),
        ]),
      );

      await pumpViewer(tester);
      await tester.tap(find.byTooltip('Page actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete this page'));
      await tester.pumpAndSettle();

      expect(find.text('Delete page 1?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(
        documents.pageOperations,
        isEmpty,
        reason: 'cancelling must not delete anything',
      );
    });

    testWidgets('the last page cannot be deleted', (tester) async {
      documents.seed(docWith(<DocumentPage>[buildPage(id: 'p0', index: 0)]));

      await pumpViewer(tester);
      await tester.tap(find.byTooltip('Page actions'));
      await tester.pumpAndSettle();

      final item = tester.widget<PopupMenuItem<PageAction>>(
        find
            .ancestor(
              of: find.text('Delete this page'),
              matching: find.byType(PopupMenuItem<PageAction>),
            )
            .first,
      );
      expect(
        item.enabled,
        isFalse,
        reason: 'a document with no pages is not a document',
      );
    });
  });
}
