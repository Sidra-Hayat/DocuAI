import 'dart:io';

import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/core/theme/app_theme.dart';
import 'package:docuai/src/features/documents/domain/entities/document_block.dart';
import 'package:docuai/src/features/documents/presentation/widgets/document_block_controller.dart';
import 'package:docuai/src/features/documents/presentation/widgets/document_block_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// The editor's rows, as the user sees them.
///
/// The defect this feature exists for was entirely visual: inserting a picture
/// showed `![Image](9c2e1f4a.jpg)` — a file name the user never chose — and the
/// picture itself was one tap away behind a View button. So the assertions here
/// are about what is on screen: a real `Image`, and *no* file name anywhere.
void main() {
  late Directory tempDir;
  late StoragePaths paths;
  late DocumentBlockController controller;

  const documentId = 'doc-1';
  const imageName = '9c2e1f4a.jpg';

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_block_editor');
    paths = StoragePaths(tempDir);
    controller = DocumentBlockController();

    // A real JPEG where the document keeps its pictures, so `Image.file` has
    // something to decode rather than falling to its error builder.
    final file = File(paths.inlineImagePath(documentId, imageName));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(
      img.encodeJpg(img.Image(width: 24, height: 16)),
      flush: true,
    );
  });

  tearDown(() async {
    controller.dispose();
    if (tempDir.existsSync()) {
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        // Windows may still hold a handle; the OS reclaims it.
      }
    }
  });

  final edited = <ImageBlock>[];

  Future<void> pumpEditor(WidgetTester tester, String pageText) async {
    edited.clear();
    controller.load(pageText);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [storagePathsProvider.overrideWithValue(paths)],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: DocumentBlockEditor(
              controller: controller,
              documentId: documentId,
              onEditImage: edited.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('what the editor shows', () {
    testWidgets('a picture is drawn, not named', (tester) async {
      await pumpEditor(tester, 'Before\n![Image]($imageName)\nAfter');

      expect(
        find.byType(InlineImageBlock),
        findsOneWidget,
        reason: 'the picture is a widget, not a line of text',
      );
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('the file name is nowhere on screen', (tester) async {
      await pumpEditor(tester, 'Before\n![Image]($imageName)\nAfter');

      // The exact defect: a file name standing in for a picture. Checked
      // across every string the editor rendered, not just the obvious one.
      final rendered = <String>[
        ...tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data ?? ''),
        ...tester
            .widgetList<EditableText>(find.byType(EditableText))
            .map((field) => field.controller.text),
      ].join(' ');

      expect(rendered, isNot(contains(imageName)));
      expect(rendered, isNot(contains('![Image]')));
      expect(
        rendered,
        isNot(contains('inline')),
        reason: 'no part of the storage path may reach the screen',
      );
    });

    testWidgets('the picture actually decodes and takes up the page', (
      tester,
    ) async {
      // `find.byType(Image)` only proves a widget exists. This proves the file
      // was read and painted: with real I/O allowed, a 24x16 picture in a
      // 768-wide column resolves to a row far taller than the placeholder
      // floor it starts at.
      await tester.runAsync(() async {
        await pumpEditor(tester, '![Image]($imageName)');
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();

      final height = tester.getSize(find.byType(InlineImageBlock)).height;

      expect(
        height,
        greaterThan(InlineImageBlock.minHeight),
        reason: 'the row is still at its placeholder height, so nothing was '
            'drawn',
      );
      expect(height, lessThanOrEqualTo(InlineImageBlock.maxHeight + 16));
    });

    testWidgets('the text around it is still editable', (tester) async {
      await pumpEditor(tester, 'Before\n![Image]($imageName)\nAfter');

      // One field either side of the picture, each holding its own run.
      final fields = tester
          .widgetList<EditableText>(find.byType(EditableText))
          .map((field) => field.controller.text)
          .toList();

      expect(fields, <String>['Before', 'After']);
    });

    testWidgets('a page of plain text is one field, as it always was', (
      tester,
    ) async {
      await pumpEditor(tester, 'Just words.\nOn two lines.');

      expect(find.byType(EditableText), findsOneWidget);
      expect(find.byType(InlineImageBlock), findsNothing);
    });

    testWidgets('tapping a picture asks to edit it', (tester) async {
      await pumpEditor(tester, 'Before\n![Image]($imageName)\nAfter');

      await tester.tap(find.byType(InlineImageBlock));
      await tester.pumpAndSettle();

      expect(edited, hasLength(1));
      expect(edited.single.imageName, imageName);
    });

    testWidgets('a picture is bounded so it cannot fill the screen', (
      tester,
    ) async {
      await pumpEditor(tester, '![Image]($imageName)');

      final rendered = tester.getSize(find.byType(InlineImageBlock));

      expect(
        rendered.height,
        lessThanOrEqualTo(
          InlineImageBlock.maxHeight + 2 * 8,
        ),
        reason: 'a tall photograph must not take the whole page',
      );
    });
  });

  group('editing the page', () {
    testWidgets('inserting a picture splits the text around it', (
      tester,
    ) async {
      await pumpEditor(tester, 'One two');

      // Caret between the words, as if the user had tapped there.
      final field = controller.blocks.whereType<TextBlock>().first;
      controller.controllerFor(field).selection =
          const TextSelection.collapsed(offset: 3);

      controller.insertImageAtCaret(imageName);
      await tester.pumpAndSettle();

      expect(controller.serialize(), 'One\n![Image]($imageName)\n two');
      expect(find.byType(InlineImageBlock), findsOneWidget);
    });

    testWidgets('removing a picture joins the text back together', (
      tester,
    ) async {
      await pumpEditor(tester, 'Above\n![Image]($imageName)\nBelow');

      final image = controller.blocks.whereType<ImageBlock>().single;
      controller.removeImage(image.id);
      await tester.pumpAndSettle();

      // One field again, not two orphaned halves — a sentence split around a
      // picture has to be repairable after the picture goes.
      expect(controller.serialize(), 'Above\nBelow');
      expect(find.byType(InlineImageBlock), findsNothing);
      expect(find.byType(EditableText), findsOneWidget);
    });

    testWidgets('replacing a picture points the block at the new file', (
      tester,
    ) async {
      await pumpEditor(tester, 'Text\n![Image]($imageName)');

      final image = controller.blocks.whereType<ImageBlock>().single;
      controller.replaceImage(blockId: image.id, imageName: 'edited.jpg');
      await tester.pumpAndSettle();

      // What an edit produces: a new file, and the reference moved to it.
      expect(controller.serialize(), 'Text\n![Image](edited.jpg)');
    });

    testWidgets('typing is carried through a structural change', (
      tester,
    ) async {
      await pumpEditor(tester, 'Start');

      await tester.enterText(find.byType(EditableText), 'Start of a note');
      await tester.pump();

      controller.insertImageAtCaret(imageName);
      await tester.pumpAndSettle();

      // The insert reads the live field contents back before rebuilding the
      // block list; without that, everything typed since the page opened would
      // be reverted by the insert.
      expect(controller.serialize(), contains('Start of a note'));
    });

    testWidgets('what is typed is what gets saved', (tester) async {
      await pumpEditor(tester, 'Before\n![Image]($imageName)\nAfter');

      await tester.enterText(find.byType(EditableText).last, 'After the edit');
      await tester.pump();

      expect(
        controller.serialize(),
        'Before\n![Image]($imageName)\nAfter the edit',
      );
    });

    testWidgets('reopening the page shows the picture again', (tester) async {
      await pumpEditor(tester, 'Before\n![Image]($imageName)\nAfter');

      final saved = controller.serialize();

      // Close and reopen: a fresh controller loading what was stored, which is
      // exactly what happens when the screen is left and entered again.
      controller.dispose();
      controller = DocumentBlockController();
      await pumpEditor(tester, saved);

      expect(find.byType(InlineImageBlock), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(controller.serialize(), saved);
    });
  });

  group('a picture whose file has gone', () {
    testWidgets('says so rather than rendering as nothing', (tester) async {
      // `runAsync` because `testWidgets` runs in a fake-async zone where real
      // file I/O never completes — so an `Image.file` neither decodes nor
      // fails, and the error builder is never reached. This is the one test
      // here that needs the image layer to actually run.
      await tester.runAsync(() async {
        await pumpEditor(tester, 'Text\n![Image](missing.jpg)');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pump();

      expect(
        find.textContaining('no longer on this device'),
        findsOneWidget,
        reason: 'a picture that renders blank looks like a document that lost '
            'it',
      );
    });
  });
}
