import 'dart:io';

import 'package:docuai/src/core/constants/hive_boxes.dart';
import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/core/storage/storage_providers.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/documents/presentation/providers/document_providers.dart';
import 'package:docuai/src/features/documents/presentation/providers/reader_providers.dart';
import 'package:docuai/src/features/documents/presentation/screens/extracted_text_screen.dart';
import 'package:docuai/src/features/documents/presentation/widgets/reader_paragraph.dart';
import 'package:docuai/src/features/export/presentation/providers/export_controller.dart';
import 'package:docuai/src/features/search/presentation/providers/search_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<dynamic> settingsBox;
  late FakeDocumentRepository documents;
  late FakeSearchRepository search;
  late FakeExportRepository export;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_reader_test');
    Hive.init(p.join(tempDir.path, 'hive'));
    settingsBox = await Hive.openBox<dynamic>('settings_reader_test');
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  setUp(() async {
    await settingsBox.clear();
    documents = FakeDocumentRepository();
    search = FakeSearchRepository();
    export = FakeExportRepository();
  });

  tearDown(() => documents.dispose());

  Document readable() => buildDocument(
    id: 'doc-1',
    title: 'Rental agreement',
    pages: <DocumentPage>[
      buildPage(
        id: 'p0',
        index: 0,
        ocrStatus: OcrStatus.completed,
        text:
            'The tenant shall maintain the property.\n\n'
            'The deposit is 1,200.00 EUR payable on signing.',
      ),
      buildPage(
        id: 'p1',
        index: 1,
        ocrStatus: OcrStatus.completed,
        text: 'Notice is one calendar month.',
      ),
    ],
  );

  /// Writes a stored text scale before the reader is pumped.
  ///
  /// Through `runAsync` because a `testWidgets` body runs in a fake-async zone
  /// that never drives real file I/O to completion — an awaited `box.put` there
  /// simply never returns, and the box is left holding an operation that stalls
  /// every later `clear()` and finally `Hive.close()`.
  Future<void> seedScale(WidgetTester tester, double scale) => tester.runAsync(
    () => settingsBox.put(SettingsKeys.readerTextScale, scale),
  );

  Future<void> pumpReader(WidgetTester tester, Document document) async {
    documents.seed(document);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(documents),
          searchRepositoryProvider.overrideWithValue(search),
          exportRepositoryProvider.overrideWithValue(export),
          settingsBoxProvider.overrideWithValue(settingsBox),
          storagePathsProvider.overrideWithValue(StoragePaths(tempDir)),
        ],
        child: const MaterialApp(
          home: ExtractedTextScreen(documentId: 'doc-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('reading', () {
    testWidgets('renders each paragraph separately', (tester) async {
      await pumpReader(tester, readable());

      expect(find.byType(ReaderParagraph), findsNWidgets(3));
      expect(
        find.text('The tenant shall maintain the property.'),
        findsOneWidget,
      );
      expect(
        find.text('The deposit is 1,200.00 EUR payable on signing.'),
        findsOneWidget,
      );
    });

    testWidgets('labels which page text came from', (tester) async {
      await pumpReader(tester, readable());

      expect(find.text('Page 1'), findsOneWidget);
      expect(find.text('Page 2'), findsOneWidget);
    });

    testWidgets('selection spans the document', (tester) async {
      await pumpReader(tester, readable());

      expect(find.byType(SelectionArea), findsOneWidget);
    });
  });

  group('search', () {
    Future<void> searchFor(WidgetTester tester, String query) async {
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), query);
      await tester.pumpAndSettle();
    }

    testWidgets('filters to matching paragraphs and counts matches', (
      tester,
    ) async {
      await pumpReader(tester, readable());

      await searchFor(tester, 'deposit');

      expect(find.byType(ReaderParagraph), findsOneWidget);
      expect(find.textContaining('1 result in 1 place'), findsOneWidget);
      expect(
        find.text('The tenant shall maintain the property.'),
        findsNothing,
      );
    });

    testWidgets('is case-insensitive', (tester) async {
      await pumpReader(tester, readable());

      await searchFor(tester, 'DEPOSIT');

      expect(find.byType(ReaderParagraph), findsOneWidget);
    });

    testWidgets('pluralises the count across paragraphs', (tester) async {
      await pumpReader(tester, readable());

      await searchFor(tester, 'the');

      expect(find.textContaining('results in'), findsOneWidget);
      expect(find.textContaining('places'), findsOneWidget);
    });

    testWidgets('says so when nothing matches', (tester) async {
      await pumpReader(tester, readable());

      await searchFor(tester, 'helicopter');

      expect(find.text('No matches for "helicopter"'), findsOneWidget);
      expect(find.byType(ReaderParagraph), findsNothing);
    });

    testWidgets('closing search restores the whole document', (tester) async {
      await pumpReader(tester, readable());
      await searchFor(tester, 'deposit');
      expect(find.byType(ReaderParagraph), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(ReaderParagraph), findsNWidgets(3));
    });
  });

  group('ReaderParagraph highlighting', () {
    testWidgets('emphasises matches without altering the text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReaderParagraph(
              text: 'Deposit paid. The deposit is refundable.',
              query: 'deposit',
              scale: 1,
            ),
          ),
        ),
      );

      final widget = tester.widget<Text>(find.byType(Text));
      final rendered = widget.textSpan!.toPlainText();

      expect(
        rendered,
        'Deposit paid. The deposit is refundable.',
        reason: 'matching must never change what the page said',
      );
    });

    testWidgets('renders plain text when nothing is being searched', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ReaderParagraph(text: 'Plain paragraph', query: '', scale: 1),
          ),
        ),
      );

      expect(find.text('Plain paragraph'), findsOneWidget);
    });
  });

  group('actions', () {
    testWidgets('copies the whole document to the clipboard', (tester) async {
      final clipboard = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') clipboard.add(call);
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await pumpReader(tester, readable());
      await tester.tap(find.byIcon(Icons.copy_all_outlined));
      await tester.pumpAndSettle();

      expect(clipboard, hasLength(1));
      expect(
        (clipboard.single.arguments as Map)['text'],
        contains('The deposit is 1,200.00 EUR payable on signing.'),
      );
      expect(find.text('Text copied to the clipboard.'), findsOneWidget);
    });

    testWidgets('shares the text with the title as the subject', (
      tester,
    ) async {
      await pumpReader(tester, readable());

      await tester.tap(find.byIcon(Icons.ios_share));
      await tester.pumpAndSettle();

      expect(export.sharedText, hasLength(1));
      expect(
        export.sharedText.single,
        contains('Notice is one calendar month.'),
      );
      expect(export.lastSubject, 'Rental agreement');
    });

    testWidgets('reports a share that fails', (tester) async {
      export.shareFailure = const ExportFailure('No app can receive text.');
      await pumpReader(tester, readable());

      await tester.tap(find.byIcon(Icons.ios_share));
      await tester.pumpAndSettle();

      expect(find.text('No app can receive text.'), findsOneWidget);
    });
  });

  // Reading the stored size is a widget concern; changing it writes to Hive,
  // and a write started from a tap never resolves inside `testWidgets`' fake
  // async zone — it leaves the box holding an in-flight operation that stalls
  // the next `clear()` and then `Hive.close()`. So the widget tests only read,
  // and the controller's own group below does the writing in plain `test()`s.
  group('text size — rendering', () {
    double renderedScale(WidgetTester tester) => tester
        .widget<ReaderParagraph>(find.byType(ReaderParagraph).first)
        .scale;

    testWidgets('renders at the default when nothing is stored', (
      tester,
    ) async {
      await pumpReader(tester, readable());

      expect(renderedScale(tester), ReaderTextScaleController.defaultScale);
    });

    testWidgets('renders at the stored size', (tester) async {
      await seedScale(tester, 1.6);

      await pumpReader(tester, readable());

      expect(renderedScale(tester), 1.6);
    });

    testWidgets('offers no way to shrink further at the floor', (tester) async {
      await seedScale(tester, ReaderTextScaleController.minScale);
      await pumpReader(tester, readable());

      await tester.tap(find.byIcon(Icons.format_size));
      await tester.pumpAndSettle();

      final smaller = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.remove),
      );
      expect(smaller.onPressed, isNull);
    });

    testWidgets('offers no way to grow further at the ceiling', (tester) async {
      await seedScale(tester, ReaderTextScaleController.maxScale);
      await pumpReader(tester, readable());

      await tester.tap(find.byIcon(Icons.format_size));
      await tester.pumpAndSettle();

      final larger = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.add),
      );
      expect(larger.onPressed, isNull);
    });
  });

  group('ReaderTextScaleController', () {
    ProviderContainer container() => ProviderContainer(
      overrides: [settingsBoxProvider.overrideWithValue(settingsBox)],
    );

    test('starts at the default with nothing stored', () {
      final c = container();
      addTearDown(c.dispose);

      expect(
        c.read(readerTextScaleProvider),
        ReaderTextScaleController.defaultScale,
      );
    });

    test('enlarging persists the new size', () async {
      final c = container();
      addTearDown(c.dispose);

      await c.read(readerTextScaleProvider.notifier).enlarge();

      expect(
        c.read(readerTextScaleProvider),
        greaterThan(ReaderTextScaleController.defaultScale),
      );
      expect(
        settingsBox.get(SettingsKeys.readerTextScale),
        c.read(readerTextScaleProvider),
      );
    });

    test('reducing persists the new size', () async {
      final c = container();
      addTearDown(c.dispose);

      await c.read(readerTextScaleProvider.notifier).reduce();

      expect(
        c.read(readerTextScaleProvider),
        lessThan(ReaderTextScaleController.defaultScale),
      );
    });

    test('will not pass the floor or the ceiling', () async {
      final c = container();
      addTearDown(c.dispose);
      final notifier = c.read(readerTextScaleProvider.notifier);

      for (var i = 0; i < 20; i++) {
        await notifier.enlarge();
      }
      expect(
        c.read(readerTextScaleProvider),
        ReaderTextScaleController.maxScale,
      );

      for (var i = 0; i < 40; i++) {
        await notifier.reduce();
      }
      expect(
        c.read(readerTextScaleProvider),
        ReaderTextScaleController.minScale,
      );
    });

    test('reset returns to the default', () async {
      final c = container();
      addTearDown(c.dispose);
      final notifier = c.read(readerTextScaleProvider.notifier);

      await notifier.enlarge();
      await notifier.reset();

      expect(
        c.read(readerTextScaleProvider),
        ReaderTextScaleController.defaultScale,
      );
    });

    test('a stored value outside the range is clamped on read', () async {
      await settingsBox.put(SettingsKeys.readerTextScale, 99.0);
      final c = container();
      addTearDown(c.dispose);

      expect(
        c.read(readerTextScaleProvider),
        ReaderTextScaleController.maxScale,
      );
    });
  });

  group('nothing to read', () {
    testWidgets('offers to recognise text when the pages are unread', (
      tester,
    ) async {
      await pumpReader(
        tester,
        buildDocument(pages: <DocumentPage>[buildPage()]),
      );

      expect(find.text('Not read yet'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Read the text'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.search), findsNothing);
    });

    testWidgets('distinguishes a blank page from a failed read', (
      tester,
    ) async {
      await pumpReader(
        tester,
        buildDocument(
          pages: <DocumentPage>[
            buildPage(id: 'p', index: 0, ocrStatus: OcrStatus.completed),
          ],
        ),
      );

      expect(find.text('No text on these pages'), findsOneWidget);
    });

    testWidgets('explains a failed read and offers a retry', (tester) async {
      await pumpReader(
        tester,
        buildDocument(
          pages: <DocumentPage>[
            buildPage(id: 'p', index: 0, ocrStatus: OcrStatus.failed),
          ],
        ),
      );

      expect(find.text('The pages could not be read'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
    });

    testWidgets('hides the reading actions when there is nothing to act on', (
      tester,
    ) async {
      await pumpReader(
        tester,
        buildDocument(pages: <DocumentPage>[buildPage()]),
      );

      expect(find.byIcon(Icons.copy_all_outlined), findsNothing);
      expect(find.byIcon(Icons.ios_share), findsNothing);
      expect(find.byIcon(Icons.format_size), findsNothing);
    });
  });
}
