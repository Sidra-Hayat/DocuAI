import 'dart:io';

import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/core/theme/app_spacing.dart';
import 'package:docuai/src/core/widgets/app_search_field.dart';
import 'package:docuai/src/core/widgets/app_skeleton.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/documents/presentation/providers/document_providers.dart';
import 'package:docuai/src/features/documents/presentation/screens/documents_screen.dart';
import 'package:docuai/src/features/documents/presentation/widgets/document_card.dart';
import 'package:docuai/src/features/documents/presentation/widgets/library_actions.dart';
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
    expect(
      find.widgetWithText(FilledButton, 'Scan a document'),
      findsOneWidget,
    );
    expect(find.byType(DocumentCard), findsNothing);
  });

  testWidgets('renders a row per document', (tester) async {
    await pumpLibrary(
      tester,
      documents: Stream.value(<Document>[
        buildDocument(id: 'a', title: 'Electricity bill'),
        buildDocument(id: 'b', title: 'Rental agreement'),
      ]),
    );

    expect(find.byType(DocumentCard), findsNWidgets(2));
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
    expect(find.textContaining('Text not read yet'), findsOneWidget);
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
    expect(find.textContaining('Text not read yet'), findsNothing);
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
    expect(find.byType(DocumentCard), findsNothing);
  });

  /// The order the screen is read in.
  ///
  /// The library used to open on a search field and a row of filter chips over
  /// a flat list: the four ways of getting a document *in* were behind one "+"
  /// button, and the things you could do with one were invisible until you
  /// opened it.
  group('the home hierarchy', () {
    testWidgets('leads with search, then how to add, then the tools', (
      tester,
    ) async {
      await pumpLibrary(
        tester,
        documents: Stream.value(<Document>[buildDocument(id: 'a')]),
      );

      double topOf(Finder finder) => tester.getTopLeft(finder).dy;

      expect(find.byType(LibraryPrimaryActions), findsOneWidget);
      expect(find.byType(LibraryTools), findsOneWidget);

      expect(
        topOf(find.byType(AppSearchField)),
        lessThan(topOf(find.byType(LibraryPrimaryActions))),
      );
      expect(
        topOf(find.byType(LibraryPrimaryActions)),
        lessThan(topOf(find.byType(LibraryTools))),
        reason: 'how to start comes before what to do next',
      );
      expect(
        topOf(find.byType(LibraryTools)),
        lessThan(topOf(find.byType(DocumentCard).first)),
        reason: 'recent documents sit below the actions',
      );
    });

    testWidgets('names every way a document starts', (tester) async {
      await pumpLibrary(
        tester,
        documents: Stream.value(<Document>[buildDocument(id: 'a')]),
      );

      for (final label in <String>['Scan', 'Photos', 'Files', 'Write']) {
        expect(find.text(label), findsOneWidget, reason: 'missing $label');
      }
    });

    testWidgets('offers the tools that act on a document', (tester) async {
      await pumpLibrary(
        tester,
        documents: Stream.value(<Document>[buildDocument(id: 'a')]),
      );

      // "PDF tools" rather than the "Export PDF" this tile used to say. The
      // narrower name was honest while sharing was all it did; now that merge
      // and compress sit behind it, the broader one is the accurate one.
      for (final label in <String>[
        'PDF tools',
        'Read text',
        'Assistant',
        'More',
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'missing $label');
      }
    });

    testWidgets('shows recent documents once, not twice', (tester) async {
      // Six documents: enough that the old screen would have drawn a
      // horizontal "Recent" strip *and* an "All documents" list beginning with
      // the same five, which is two answers to "what was I last working on".
      await pumpLibrary(
        tester,
        documents: Stream.value(<Document>[
          for (var i = 0; i < 6; i++)
            buildDocument(id: '$i', title: 'Document $i'),
        ]),
      );

      expect(find.text('Recent documents'), findsOneWidget);
      // The newest document appears exactly once. It used to be drawn twice —
      // in the strip and again at the top of the list below it. The list is
      // built lazily, so the count of cards on screen is a function of the
      // viewport; what matters is that no title is rendered more than once.
      expect(
        find.text('Document 0'),
        findsOneWidget,
        reason: 'a document listed twice is the duplication this removed',
      );
      expect(find.text('Document 1'), findsOneWidget);
    });

    testWidgets('renames the section when a filter narrows it', (tester) async {
      await pumpLibrary(
        tester,
        documents: Stream.value(<Document>[
          buildDocument(id: 'a', title: 'Starred', isFavorite: true),
          buildDocument(id: 'b', title: 'Plain'),
        ]),
      );

      await tester.tap(find.widgetWithText(FilterChip, 'Favourites'));
      await tester.pumpAndSettle();

      // Under a filter the list is no longer "recent anything", and a heading
      // saying otherwise would describe a list the user is not looking at.
      expect(find.text('Recent documents'), findsNothing);
      expect(find.byType(DocumentCard), findsOneWidget);
    });
  });

  group('narrow phones', () {
    testWidgets('two rows of four tiles fit without overflowing', (
      tester,
    ) async {
      // 320dp is the narrowest Android width still in circulation. Two rows of
      // four equal tiles is exactly the layout that fails there first, and a
      // RenderFlex overflow throws in a test rather than merely painting a
      // yellow stripe.
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpLibrary(
        tester,
        documents: Stream.value(<Document>[
          buildDocument(id: 'a', title: 'Electricity bill August 2026'),
        ]),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(LibraryPrimaryActions), findsOneWidget);
    });

    testWidgets('survives the largest text the app allows', (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            storagePathsProvider.overrideWithValue(StoragePaths(tempDir)),
            documentsProvider.overrideWith(
              (ref) => Stream.value(<Document>[buildDocument(id: 'a')]),
            ),
          ],
          child: MaterialApp(
            home: MediaQuery(
              // The ceiling `app.dart` clamps to. Above it the layouts are not
              // expected to hold; at it they must.
              data: const MediaQueryData(
                textScaler: TextScaler.linear(AppAccessibility.maxTextScale),
              ),
              child: const DocumentsScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
