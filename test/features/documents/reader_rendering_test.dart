import 'dart:io';

import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/core/storage/storage_providers.dart';
import 'package:docuai/src/core/text/markup.dart';
import 'package:docuai/src/core/theme/app_theme.dart';
import 'package:docuai/src/core/theme/app_typography.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_block.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/documents/presentation/providers/document_providers.dart';
import 'package:docuai/src/features/documents/presentation/screens/document_detail_screen.dart';
import 'package:docuai/src/features/documents/presentation/screens/extracted_text_screen.dart';
import 'package:docuai/src/features/documents/presentation/screens/page_viewer_screen.dart';
import 'package:docuai/src/features/documents/presentation/widgets/document_block_controller.dart';
import 'package:docuai/src/features/documents/presentation/widgets/markup_view.dart';
import 'package:docuai/src/features/export/presentation/providers/export_controller.dart';
import 'package:docuai/src/features/search/presentation/providers/search_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';

/// What a saved document looks like when it is read back.
///
/// The defect these exist for was reported from a phone: a page written with a
/// heading, some bold text and a picture was read back as
///
/// ```
/// ## gddvjiufxhj
/// ![Image](1cb23234f061.jpg)
/// **
/// ```
///
/// `Markup.parse` had existed all along — the editor styled with it and the PDF
/// composer drew from it — but nothing in Flutter turned a `MarkupBlock` into a
/// widget, so every screen that showed a saved page handed the raw string to a
/// `Text`.
///
/// So the assertions here are about what reaches the screen. Every one of them
/// checks the *rendered* strings, and the sweep at the end checks that no
/// marker and no file name survives anywhere on any of the three surfaces that
/// show a document.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late Box<dynamic> settingsBox;
  late FakeDocumentRepository documents;

  const imageName = '1cb23234f061.jpg';
  const documentId = 'doc-1';

  /// A page of every shape the format supports, in a deliberate order:
  /// heading, text, image, text, image — exactly what the brief asks be proved.
  const richPage =
      '# Tenancy agreement\n'
      'The **deposit** is *1,200.00 EUR*.\n'
      '![Image]($imageName)\n'
      '## Notice period\n'
      '- One calendar month\n'
      '- In writing\n'
      '1. Sign the agreement\n'
      '2. Pay the deposit\n'
      '> Signed in duplicate\n'
      '![Image]($imageName)\n'
      'Closing paragraph.';

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_reader_render');
    Hive.init(p.join(tempDir.path, 'hive'));
    settingsBox = await Hive.openBox<dynamic>('settings_render');

    final paths = StoragePaths(tempDir);
    final file = File(paths.inlineImagePath(documentId, imageName));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(
      img.encodeJpg(img.Image(width: 32, height: 20)),
      flush: true,
    );
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) {
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        // Windows may still hold the box files; the OS reclaims them.
      }
    }
  });

  setUp(() {
    documents = FakeDocumentRepository();
  });

  tearDown(() => documents.dispose());

  Document written({String text = richPage}) => buildDocument(
    id: documentId,
    title: 'Written note',
    pages: <DocumentPage>[
      buildPage(
        id: 'p0',
        index: 0,
        imagePath: null,
        ocrStatus: OcrStatus.completed,
        text: text,
      ),
    ],
  );

  Future<void> pump(
    WidgetTester tester,
    Widget screen, {
    Document? document,
  }) async {
    documents.seed(document ?? written());

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(documents),
          searchRepositoryProvider.overrideWithValue(FakeSearchRepository()),
          exportRepositoryProvider.overrideWithValue(FakeExportRepository()),
          settingsBoxProvider.overrideWithValue(settingsBox),
          storagePathsProvider.overrideWithValue(StoragePaths(tempDir)),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Every string the screen actually put on the display.
  String rendered(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data ?? text.textSpan?.toPlainText() ?? '')
      .join('\n');

  /// The three screens that show a saved document.
  final surfaces = <String, Widget>{
    'reader': const ExtractedTextScreen(documentId: documentId),
    'page viewer': const PageViewerScreen(documentId: documentId),
    'document detail': const DocumentDetailScreen(documentId: documentId),
  };

  group('no screen shows internal syntax', () {
    for (final entry in surfaces.entries) {
      testWidgets('${entry.key} shows no markers and no file name', (
        tester,
      ) async {
        await pump(tester, entry.value);

        final text = rendered(tester);

        // The exact strings from the report.
        expect(text, isNot(contains('![Image]')), reason: entry.key);
        expect(text, isNot(contains(imageName)), reason: entry.key);
        expect(text, isNot(contains('.jpg')), reason: entry.key);
        expect(text, isNot(contains('##')), reason: entry.key);
        expect(text, isNot(contains('**')), reason: entry.key);
        expect(
          text,
          isNot(contains('inline')),
          reason: 'no part of the storage path may reach the screen',
        );
      });
    }
  });

  group('the reader renders the document', () {
    testWidgets('a heading is text, not hashes', (tester) async {
      await pump(tester, surfaces['reader']!);

      expect(find.text('Tenancy agreement'), findsOneWidget);
      expect(find.text('# Tenancy agreement'), findsNothing);
    });

    testWidgets('a heading is set larger than the body', (tester) async {
      await pump(tester, surfaces['reader']!);

      double sizeOf(String content) => tester
          .widget<Text>(find.text(content))
          .style!
          .fontSize!;

      // The sizes the brief asks for, read off what was painted rather than
      // asserted against the constants that produced them.
      expect(sizeOf('Tenancy agreement'), AppTypography.heading1);
      expect(sizeOf('Notice period'), AppTypography.heading2);
      expect(sizeOf('Closing paragraph.'), AppTypography.body);
      expect(AppTypography.heading1, greaterThan(AppTypography.heading2));
      expect(AppTypography.heading2, greaterThan(AppTypography.body));
    });

    testWidgets('bold and italic are weights, not asterisks', (tester) async {
      await pump(tester, surfaces['reader']!);

      final line = tester.widget<Text>(
        find.textContaining('The deposit is'),
      );
      final spans = <InlineSpan>[];
      line.textSpan!.visitChildren((span) {
        spans.add(span);
        return true;
      });

      expect(
        line.textSpan!.toPlainText(),
        'The deposit is 1,200.00 EUR.',
        reason: 'the markers are gone from the text itself',
      );
      expect(
        spans.any((s) => s.style?.fontWeight == FontWeight.w700),
        isTrue,
        reason: '"deposit" was written bold and is not rendered bold',
      );
      expect(
        spans.any((s) => s.style?.fontStyle == FontStyle.italic),
        isTrue,
        reason: 'the amount was written italic and is not rendered italic',
      );
    });

    testWidgets('bullets render as bullets', (tester) async {
      await pump(tester, surfaces['reader']!);

      expect(find.text('One calendar month'), findsOneWidget);
      expect(find.text('- One calendar month'), findsNothing);
      expect(find.text('•'), findsNWidgets(2));
    });

    testWidgets('numbered items keep their own numbers', (tester) async {
      await pump(tester, surfaces['reader']!);

      expect(find.text('Sign the agreement'), findsOneWidget);
      expect(find.text('1.'), findsOneWidget);
      expect(
        find.text('2.'),
        findsOneWidget,
        reason: 'a list that renumbers from one is not the list that was saved',
      );
    });

    testWidgets('a quotation renders as one', (tester) async {
      await pump(tester, surfaces['reader']!);

      expect(find.text('Signed in duplicate'), findsOneWidget);
      expect(find.text('> Signed in duplicate'), findsNothing);
    });

    testWidgets('pictures are drawn where the writing put them', (
      tester,
    ) async {
      await pump(tester, surfaces['reader']!);

      expect(find.byType(ReaderImage), findsNWidgets(2));
    });

    testWidgets('text, image and text keep their order', (tester) async {
      await pump(tester, surfaces['reader']!);

      double topOf(Finder finder) => tester.getTopLeft(finder).dy;

      final images = find.byType(ReaderImage);

      expect(topOf(find.text('Tenancy agreement')), lessThan(topOf(images.at(0))));
      expect(topOf(images.at(0)), lessThan(topOf(find.text('Notice period'))));
      expect(topOf(find.text('Notice period')), lessThan(topOf(images.at(1))));
      expect(
        topOf(images.at(1)),
        lessThan(topOf(find.text('Closing paragraph.'))),
        reason: 'the closing text moved above the picture it was written under',
      );
    });
  });

  group('reading a document back after it was saved', () {
    testWidgets('what the editor serialised is what the reader shows', (
      tester,
    ) async {
      // The exact shape the brief describes: heading, text, image, text, image.
      const saved =
          '# My notes\n'
          'First paragraph.\n'
          '![Image]($imageName)\n'
          'Second paragraph.\n'
          '![Image]($imageName)';

      await pump(
        tester,
        surfaces['reader']!,
        document: written(text: saved),
      );

      expect(find.text('My notes'), findsOneWidget);
      expect(find.text('First paragraph.'), findsOneWidget);
      expect(find.text('Second paragraph.'), findsOneWidget);
      expect(find.byType(ReaderImage), findsNWidgets(2));
      expect(rendered(tester), isNot(contains('![Image]')));
    });

    testWidgets('a scanned page with no markup is unchanged', (tester) async {
      // The commonest page in the library, and the one the renderer must not
      // touch: recognised text contains no markers and has to read verbatim.
      const scan =
          'Northwind Utilities quarterly electricity statement.\n'
          'Account number: NW-4471902\n'
          'Total amount due: 248.60 EUR';

      await pump(tester, surfaces['reader']!, document: written(text: scan));

      expect(
        find.text('Northwind Utilities quarterly electricity statement.'),
        findsOneWidget,
      );
      expect(find.text('Account number: NW-4471902'), findsOneWidget);
      expect(find.text('Total amount due: 248.60 EUR'), findsOneWidget);
    });
  });

  group('the editor and the reader agree', () {
    testWidgets('what the block editor saves is what the reader renders', (
      tester,
    ) async {
      // The round trip the user actually performs: write, insert a picture,
      // write more, insert another, tap Done, reopen. The editor's serialised
      // output is fed straight to the reader rather than being retyped here,
      // so a change to either side that broke the other would fail this.
      final editor = DocumentBlockController();
      addTearDown(editor.dispose);

      editor.load('# My notes\nFirst paragraph.');
      editor.insertImageAtCaret(imageName);
      editor
          .controllerFor(editor.blocks.whereType<TextBlock>().last)
          .text = 'Second paragraph.';
      editor.insertImageAtCaret(imageName);

      final saved = editor.serialize();

      // Nothing internal survives into the reader.
      await pump(tester, surfaces['reader']!, document: written(text: saved));

      expect(find.text('My notes'), findsOneWidget);
      expect(find.text('First paragraph.'), findsOneWidget);
      expect(find.text('Second paragraph.'), findsOneWidget);
      expect(find.byType(ReaderImage), findsNWidgets(2));
      expect(rendered(tester), isNot(contains(imageName)));
    });
  });

  group('the saved-document preview draws its pictures', () {
    // Reported from a phone, on the release build: write a note, insert a
    // photograph, tap Done, reopen it — and the preview showed the words with a
    // "Picture" chip where the photograph belonged. The photograph appeared
    // only after tapping through to the full-screen page. It had never been
    // lost; the preview was asked not to draw it.
    //
    // Five blocks, so nothing here is lost to the preview's eight-block limit
    // and a failure means what it says.
    const saved =
        '# My notes\n'
        'First paragraph.\n'
        '![Image]($imageName)\n'
        'Second paragraph.\n'
        '![Image]($imageName)';

    Finder previewImages() => find.descendant(
      of: find.byType(DocumentDetailScreen),
      matching: find.byType(ReaderImage),
    );

    Future<void> pumpPreview(WidgetTester tester, {String text = saved}) => pump(
      tester,
      surfaces['document detail']!,
      document: written(text: text),
    );

    testWidgets('the pictures are drawn rather than named', (tester) async {
      await pumpPreview(tester);

      expect(previewImages(), findsNWidgets(2));
      expect(
        find.text('Picture'),
        findsNothing,
        reason: 'the caption that stood in for the photograph is back',
      );
    });

    testWidgets('what is drawn is the file stored for this document', (
      tester,
    ) async {
      await pumpPreview(tester);

      final images = tester
          .widgetList<Image>(
            find.descendant(
              of: find.byType(ReaderImage),
              matching: find.byType(Image),
            ),
          )
          .toList(growable: false);

      expect(images, hasLength(2));
      for (final image in images) {
        // Not merely *an* image: the one the editor wrote into this document's
        // own `inline/` folder.
        expect(
          (image.image as FileImage).file.path,
          StoragePaths(tempDir).inlineImagePath(documentId, imageName),
        );
      }
    });

    testWidgets('the file name and the path stay off the screen', (
      tester,
    ) async {
      await pumpPreview(tester);

      final text = rendered(tester);

      expect(text, isNot(contains(imageName)));
      expect(text, isNot(contains('.jpg')));
      expect(text, isNot(contains('inline')));
      expect(text, isNot(contains('![Image]')));
    });

    testWidgets('text, picture, text, picture keep their order', (tester) async {
      await pumpPreview(tester);

      double topOf(Finder finder) => tester.getTopLeft(finder).dy;
      final images = previewImages();

      expect(topOf(find.text('My notes')), lessThan(topOf(find.text('First paragraph.'))));
      expect(topOf(find.text('First paragraph.')), lessThan(topOf(images.at(0))));
      expect(topOf(images.at(0)), lessThan(topOf(find.text('Second paragraph.'))));
      expect(
        topOf(find.text('Second paragraph.')),
        lessThan(topOf(images.at(1))),
        reason: 'the second picture rose above the paragraph written before it',
      );
    });

    testWidgets('a picture in the card is smaller than one on a full page', (
      tester,
    ) async {
      await pumpPreview(tester);

      // The card is a little under 300 logical pixels tall. A picture given the
      // full-page height would be the only thing in it, and the writing after
      // it would never appear — which is a different way of not showing the
      // document.
      expect(
        tester.widget<ReaderImage>(previewImages().first).maxHeight,
        lessThan(ReaderImage.defaultMaxHeight),
      );
    });

    testWidgets('the reader still draws pictures at full page size', (
      tester,
    ) async {
      await pump(
        tester,
        surfaces['reader']!,
        document: written(text: saved),
      );

      final images = tester.widgetList<ReaderImage>(find.byType(ReaderImage));

      expect(images, hasLength(2));
      for (final image in images) {
        expect(image.maxHeight, ReaderImage.defaultMaxHeight);
      }
    });

    testWidgets('a scanned page still shows its scan', (tester) async {
      await pump(
        tester,
        surfaces['document detail']!,
        document: buildDocument(
          id: documentId,
          title: 'Electricity bill',
          pages: <DocumentPage>[
            // The commonest page in the library: captured, with an image path
            // of its own. It never reaches the written-page preview at all, and
            // this change must not give it inline pictures it does not have.
            buildPage(id: 'p0', index: 0, ocrStatus: OcrStatus.completed,
              text: 'Total amount due: 248.60 EUR'),
          ],
        ),
      );

      expect(find.byType(ReaderImage), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a written page of recognised text is unchanged', (
      tester,
    ) async {
      await pumpPreview(
        tester,
        text: 'Northwind Utilities quarterly electricity statement.\n'
            'Account number: NW-4471902',
      );

      expect(
        find.text('Northwind Utilities quarterly electricity statement.'),
        findsOneWidget,
      );
      expect(find.byType(ReaderImage), findsNothing);
    });
  });

  group('searching the rendered text', () {
    Future<void> searchFor(WidgetTester tester, String query) async {
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), query);
      await tester.pumpAndSettle();
    }

    testWidgets('matches what is shown, not what is stored', (tester) async {
      await pump(tester, surfaces['reader']!);

      // "deposit" is stored as `**deposit**`. Searching the raw text for
      // "the deposit is" would find nothing, because of two asterisks the user
      // cannot see.
      await searchFor(tester, 'the deposit is');

      expect(find.textContaining('1 result in 1 place'), findsOneWidget);
    });
  });

  group('text that leaves the app', () {
    test('what is copied and shared carries no markup', () {
      final document = written();

      // The reader strips at the point of drawing; text handed to another app
      // has to be stripped too, or a paste into an email arrives as
      // `## Notice period` and `**deposit**`.
      final readable = document.readableText;

      expect(readable, isNot(contains('#')));
      expect(readable, isNot(contains('**')));
      expect(readable, isNot(contains('![Image]')));
      expect(readable, isNot(contains(imageName)));

      // And the words survive.
      expect(readable, contains('Tenancy agreement'));
      expect(readable, contains('deposit'));
      expect(readable, contains('Notice period'));
    });

    test('what search and the assistant read is deliberately unchanged', () {
      final document = written();

      // `extractedText` feeds the index and the retriever. Both tokenise on
      // non-alphanumerics, so they have always seen `**total**` and `total` as
      // the same word — changing what they are given to fix a *display*
      // problem would be changing retrieval for no reason.
      expect(document.extractedText, contains('**deposit**'));
      expect(
        document.extractedText,
        isNot(contains(imageName)),
        reason: 'pictures were already kept out of the indexed text',
      );
    });
  });

  group('MarkupView on its own', () {
    testWidgets('renders nothing for an empty page', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MarkupView(text: '', documentId: documentId),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('parses through Markup rather than reimplementing it', (
      tester,
    ) async {
      // The guard against a second markup implementation drifting from the one
      // the exporter and the editor use: whatever `Markup.parse` calls a block,
      // the view renders that many.
      const text = '# One\nTwo\n- Three\n> Four';
      final blocks = Markup.parse(text);

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: MarkupView(text: text, documentId: documentId),
            ),
          ),
        ),
      );

      expect(blocks, hasLength(4));
      for (final block in blocks) {
        expect(find.text(block.text), findsOneWidget, reason: block.text);
      }
    });
  });
}
