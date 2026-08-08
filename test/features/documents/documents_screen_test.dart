import 'dart:io';

import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/core/widgets/app_skeleton.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/documents/presentation/providers/document_providers.dart';
import 'package:docuai/src/features/documents/presentation/screens/documents_screen.dart';
import 'package:docuai/src/features/documents/presentation/widgets/document_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

/// Library screen tests.
///
/// These override [documentsProvider] with a fixed stream rather than driving
/// real Hive: the point is what the screen renders for each of the stream's
/// three states, and a real box would make that depend on file I/O that
/// `testWidgets`' fake-async zone does not run to completion.
void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_screen_test');
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<void> pumpLibrary(
    WidgetTester tester, {
    required Stream<List<Document>> documents,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storagePathsProvider.overrideWithValue(StoragePaths(tempDir)),
          documentsProvider.overrideWith((ref) => documents),
        ],
        child: const MaterialApp(home: DocumentsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the empty state when the library is empty', (
    tester,
  ) async {
    await pumpLibrary(tester, documents: Stream.value(const <Document>[]));

    expect(find.text('No documents yet'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Scan a document'), findsOneWidget);
    expect(find.byType(DocumentTile), findsNothing);
  });

  testWidgets('renders a row per document', (tester) async {
    await pumpLibrary(
      tester,
      documents: Stream.value(<Document>[
        buildDocument(id: 'a', title: 'Electricity bill'),
        buildDocument(id: 'b', title: 'Rental agreement'),
      ]),
    );

    expect(find.byType(DocumentTile), findsNWidgets(2));
    expect(find.text('Electricity bill'), findsOneWidget);
    expect(find.text('Rental agreement'), findsOneWidget);
    expect(find.text('No documents yet'), findsNothing);
  });

  testWidgets('summarises page count and outstanding OCR work', (tester) async {
    await pumpLibrary(
      tester,
      documents: Stream.value(<Document>[
        buildDocument(
          pages: <DocumentPage>[
            buildPage(id: 'a', index: 0),
            buildPage(id: 'b', index: 1),
          ],
        ),
      ]),
    );

    expect(find.textContaining('2 pages'), findsOneWidget);
    expect(find.textContaining('Text pending'), findsOneWidget);
  });

  testWidgets('drops the OCR note once every page is recognised', (
    tester,
  ) async {
    await pumpLibrary(
      tester,
      documents: Stream.value(<Document>[
        buildDocument(
          pages: <DocumentPage>[
            buildPage(
              id: 'a',
              index: 0,
              text: 'done',
              ocrStatus: OcrStatus.completed,
            ),
          ],
        ),
      ]),
    );

    expect(find.textContaining('1 page'), findsOneWidget);
    expect(find.textContaining('Text pending'), findsNothing);
  });

  testWidgets('marks favourites', (tester) async {
    await pumpLibrary(
      tester,
      documents: Stream.value(<Document>[
        buildDocument(id: 'a', title: 'Starred', isFavorite: true),
        buildDocument(id: 'b', title: 'Plain'),
      ]),
    );

    expect(find.byIcon(Icons.star), findsOneWidget);
  });

  testWidgets('shows a loading placeholder until the first emission', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storagePathsProvider.overrideWithValue(StoragePaths(tempDir)),
          documentsProvider.overrideWith(
            (ref) => const Stream<List<Document>>.empty(),
          ),
        ],
        child: const MaterialApp(home: DocumentsScreen()),
      ),
    );
    await tester.pump();

    // A skeleton shaped like the list, rather than a spinner: the layout does
    // not shift when the documents arrive.
    expect(find.byType(AppListSkeleton), findsOneWidget);
    expect(
      find.bySemanticsLabel('Loading'),
      findsOneWidget,
      reason: 'a screen reader has to be told the wait is a wait',
    );
  });

  testWidgets('explains itself when storage cannot be read', (tester) async {
    await pumpLibrary(
      tester,
      documents: Stream<List<Document>>.error(Exception('box is corrupt')),
    );

    expect(find.text('Could not open your library'), findsOneWidget);
    expect(find.byType(DocumentTile), findsNothing);
  });
}
