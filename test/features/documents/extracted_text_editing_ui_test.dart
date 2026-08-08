import 'dart:io';

import 'package:docuai/src/core/router/app_routes.dart';
import 'package:docuai/src/core/storage/storage_providers.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/documents/presentation/providers/document_providers.dart';
import 'package:docuai/src/features/documents/presentation/screens/extracted_text_screen.dart';
import 'package:docuai/src/features/search/presentation/providers/search_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';

/// Reaching the editor from the text, and what the text says about itself.
///
/// The reader is where someone notices OCR got a word wrong, so it is where the
/// correction has to start. The edit action sits on each page heading rather
/// than in the app bar: a document has one body of text but several pages of
/// it, and a single action at the top could only guess which was meant.
void main() {
  late Directory tempDir;
  late Box<dynamic> settingsBox;
  late FakeDocumentRepository documents;
  late FakeSearchRepository search;

  String? editedDocumentId;
  String? editedPageId;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_edit_ui');
    Hive.init(p.join(tempDir.path, 'hive'));
    // The reader reads its font scale from settings, so the box has to exist
    // even though nothing here changes the size.
    settingsBox = await Hive.openBox<dynamic>('settings_edit_ui');
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await settingsBox.clear();
    documents = FakeDocumentRepository();
    search = FakeSearchRepository();
    editedDocumentId = null;
    editedPageId = null;
  });

  tearDown(() => documents.dispose());

  Future<void> pumpReader(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) =>
              const ExtractedTextScreen(documentId: 'doc'),
          routes: <RouteBase>[
            GoRoute(
              path: 'edit/:id/:page',
              name: AppRoutes.editPageName,
              builder: (context, state) {
                editedDocumentId = state.pathParameters['id'];
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
          settingsBoxProvider.overrideWithValue(settingsBox),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Document billWith(List<DocumentPage> pages) =>
      buildDocument(id: 'doc', title: 'Electricity bill', pages: pages);

  testWidgets('every page offers to have its text corrected', (tester) async {
    documents.seed(
      billWith(<DocumentPage>[
        buildPage(
          id: 'p0',
          index: 0,
          text: 'T0tal amaunt due',
          ocrStatus: OcrStatus.completed,
        ),
        buildPage(
          id: 'p1',
          index: 1,
          imagePath: 'documents/doc/p1.jpg',
          text: 'Second page text.',
          ocrStatus: OcrStatus.completed,
        ),
      ]),
    );

    await pumpReader(tester);

    expect(find.widgetWithText(TextButton, 'Edit'), findsNWidgets(2));
  });

  testWidgets('editing opens the page whose heading was tapped', (
    tester,
  ) async {
    documents.seed(
      billWith(<DocumentPage>[
        buildPage(
          id: 'p0',
          index: 0,
          text: 'First page.',
          ocrStatus: OcrStatus.completed,
        ),
        buildPage(
          id: 'p1',
          index: 1,
          imagePath: 'documents/doc/p1.jpg',
          text: 'Second page.',
          ocrStatus: OcrStatus.completed,
        ),
      ]),
    );

    await pumpReader(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Edit').last);
    await tester.pumpAndSettle();

    expect(editedDocumentId, 'doc');
    expect(
      editedPageId,
      'p1',
      reason: 'the second heading must edit the second page',
    );
  });

  testWidgets('a corrected page says so', (tester) async {
    documents.seed(
      billWith(<DocumentPage>[
        buildPage(
          id: 'p0',
          index: 0,
          text: 'Total amount due 500.00 EUR',
          ocrStatus: OcrStatus.completed,
          textEditedAt: DateTime.utc(2026, 8, 8),
        ),
      ]),
    );

    await pumpReader(tester);

    expect(find.text('Edited'), findsOneWidget);
  });

  testWidgets('an untouched page does not', (tester) async {
    documents.seed(
      billWith(<DocumentPage>[
        buildPage(
          id: 'p0',
          index: 0,
          text: 'T0tal amaunt due',
          ocrStatus: OcrStatus.completed,
        ),
      ]),
    );

    await pumpReader(tester);

    expect(find.text('Edited'), findsNothing);
  });

  testWidgets('a page with nothing on it still offers to be written', (
    tester,
  ) async {
    // Otherwise a faint scan is a dead end: the page heading would not appear
    // at all, so there would be nowhere to start typing what it says.
    documents.seed(
      billWith(<DocumentPage>[
        buildPage(
          id: 'p0',
          index: 0,
          text: 'Readable page.',
          ocrStatus: OcrStatus.completed,
        ),
        buildPage(
          id: 'p1',
          index: 1,
          imagePath: 'documents/doc/p1.jpg',
          ocrStatus: OcrStatus.completed,
        ),
      ]),
    );

    await pumpReader(tester);

    expect(find.text('No text was found on this page.'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Edit').last);
    await tester.pumpAndSettle();

    expect(editedPageId, 'p1');
  });

  testWidgets('a document with no text at all offers to be typed out', (
    tester,
  ) async {
    documents.seed(
      billWith(<DocumentPage>[
        buildPage(id: 'p0', index: 0, ocrStatus: OcrStatus.completed),
      ]),
    );

    await pumpReader(tester);

    expect(find.text('No text on these pages'), findsOneWidget);

    await tester.tap(find.text('Type it yourself'));
    await tester.pumpAndSettle();

    expect(editedPageId, 'p0');
  });

  testWidgets('editing is withheld while the text is being searched', (
    tester,
  ) async {
    // The heading sits above a filtered view, so Edit there would open the
    // whole page and lose the match the user was looking at.
    documents.seed(
      billWith(<DocumentPage>[
        buildPage(
          id: 'p0',
          index: 0,
          text: 'Total amount due 500.00 EUR',
          ocrStatus: OcrStatus.completed,
        ),
      ]),
    );

    await pumpReader(tester);
    expect(find.widgetWithText(TextButton, 'Edit'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'amount');
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextButton, 'Edit'), findsNothing);
  });
}
