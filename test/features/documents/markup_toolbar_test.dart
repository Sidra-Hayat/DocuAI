import 'package:docuai/src/core/text/markup.dart';
import 'package:docuai/src/features/documents/presentation/widgets/markup_editing_controller.dart';
import 'package:docuai/src/features/documents/presentation/widgets/markup_toolbar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The toolbar as the user meets it.
///
/// The transforms themselves are covered as pure functions elsewhere; what a
/// widget test can add is that each button is wired to the right one, and that
/// the caret ends up somewhere sensible — a formatting button that throws the
/// cursor to the bottom of the document is worse than no button.
void main() {
  late MarkupEditingController controller;

  setUp(() => controller = MarkupEditingController());
  tearDown(() => controller.dispose());

  Future<void> pumpEditor(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              // An explicit size, as the real editor passes: a paragraph span
              // inherits its size from the base style, so without one there is
              // nothing to compare a heading against.
              Expanded(
                child: TextField(
                  controller: controller,
                  maxLines: null,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              MarkupToolbar(controller: controller),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void selectAll() {
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
  }

  Future<void> press(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pumpAndSettle();
  }

  testWidgets('every button is present', (tester) async {
    await pumpEditor(tester);

    for (final tooltip in <String>[
      'Bold',
      'Italic',
      'Heading',
      'Bullet list',
      'Numbered list',
      'Quote',
    ]) {
      expect(find.byTooltip(tooltip), findsOneWidget, reason: tooltip);
    }
  });

  testWidgets('bold wraps the selection', (tester) async {
    await pumpEditor(tester);
    controller.text = 'the deposit';
    controller.selection = const TextSelection(baseOffset: 4, extentOffset: 11);

    await press(tester, 'Bold');

    expect(controller.text, 'the **deposit**');
    expect(
      controller.selection.textInside(controller.text),
      'deposit',
      reason: 'the selection must still cover the word it was on',
    );
  });

  testWidgets('italic wraps the selection', (tester) async {
    await pumpEditor(tester);
    controller.text = 'paid late';
    controller.selection = const TextSelection(baseOffset: 5, extentOffset: 9);

    await press(tester, 'Italic');

    expect(controller.text, 'paid *late*');
  });

  testWidgets('heading marks the line', (tester) async {
    await pumpEditor(tester);
    controller.text = 'Tenancy agreement';
    controller.selection = const TextSelection.collapsed(offset: 3);

    await press(tester, 'Heading');

    expect(controller.text, '## Tenancy agreement');
  });

  testWidgets('bullet and numbered apply across selected lines', (
    tester,
  ) async {
    await pumpEditor(tester);
    controller.text = 'milk\neggs\nbread';
    selectAll();

    await press(tester, 'Bullet list');
    expect(controller.text, '- milk\n- eggs\n- bread');

    selectAll();
    await press(tester, 'Numbered list');
    expect(controller.text, '1. milk\n2. eggs\n3. bread');
  });

  testWidgets('quote marks the line', (tester) async {
    await pumpEditor(tester);
    controller.text = 'as agreed';
    controller.selection = const TextSelection.collapsed(offset: 0);

    await press(tester, 'Quote');

    expect(controller.text, '> as agreed');
  });

  testWidgets('pressing twice undoes it', (tester) async {
    await pumpEditor(tester);
    controller.text = 'the deposit';
    controller.selection = const TextSelection(baseOffset: 4, extentOffset: 11);

    await press(tester, 'Bold');
    await press(tester, 'Bold');

    expect(controller.text, 'the deposit');
  });

  testWidgets('the caret never jumps to the end of the document', (
    tester,
  ) async {
    // Assigning `text` alone resets the selection, which would drop the cursor
    // at the bottom on every press. The controller sets value and selection
    // together for exactly this reason.
    await pumpEditor(tester);
    controller.text = 'first line\nsecond line\nthird line';
    controller.selection = const TextSelection.collapsed(offset: 13);

    await press(tester, 'Bullet list');

    expect(controller.text, 'first line\n- second line\nthird line');
    expect(
      controller.selection.baseOffset,
      lessThan(controller.text.length),
      reason: 'the caret stayed on the line it was on',
    );
    expect(
      controller.text.substring(0, controller.selection.baseOffset),
      'first line\n- se',
    );
  });

  testWidgets('an empty document survives every button', (tester) async {
    await pumpEditor(tester);

    for (final tooltip in <String>[
      'Bold',
      'Italic',
      'Heading',
      'Bullet list',
      'Numbered list',
      'Quote',
    ]) {
      controller.value = TextEditingValue.empty;
      await press(tester, tooltip);
      expect(tester.takeException(), isNull, reason: tooltip);
    }
  });

  testWidgets('recognised text is untouched until a button is pressed', (
    tester,
  ) async {
    const recognised = 'Northwind Utilities\nTotal amount due: 248.60 EUR';

    await pumpEditor(tester);
    controller.text = recognised;
    await tester.pumpAndSettle();

    expect(controller.text, recognised);
    expect(tester.takeException(), isNull);
  });

  group('live styling', () {
    testWidgets('markers are drawn dimmer than the words', (tester) async {
      await pumpEditor(tester);
      controller.text = 'the **deposit**';
      await tester.pumpAndSettle();

      final span = controller.buildTextSpan(
        context: tester.element(find.byType(TextField)),
        withComposing: false,
      );

      final children = span.children!.cast<TextSpan>();
      final marker = children.firstWhere((s) => s.text == '**');
      final word = children.firstWhere((s) => s.text == 'deposit');

      expect(word.style?.fontWeight, FontWeight.w700);
      expect(marker.style?.color, isNot(word.style?.color));
    });

    testWidgets('spans cover the text exactly, so the caret stays in step', (
      tester,
    ) async {
      // The invariant live styling rests on. Flutter maps caret positions
      // through this span tree; one character unaccounted for puts the cursor
      // somewhere other than where it appears.
      await pumpEditor(tester);

      for (final text in <String>[
        'plain',
        '# Heading\n- **bold** item\n1. numbered\n> quoted',
        '2 * 3 = 6',
        '**unclosed',
      ]) {
        controller.text = text;
        await tester.pumpAndSettle();

        final span = controller.buildTextSpan(
          context: tester.element(find.byType(TextField)),
          withComposing: false,
        );

        expect(
          span.toPlainText(),
          text,
          reason: 'the rendered spans must reconstruct the text exactly',
        );
      }
    });

    testWidgets('a heading renders larger than a paragraph', (tester) async {
      await pumpEditor(tester);
      controller.text = '# Big\nsmall';
      await tester.pumpAndSettle();

      final children = controller
          .buildTextSpan(
            context: tester.element(find.byType(TextField)),
            // Passed as the framework passes it. A paragraph keeps the base
            // size rather than restating it, so without a base there is
            // nothing for a heading to be larger than.
            style: const TextStyle(fontSize: 16),
            withComposing: false,
          )
          .children!
          .cast<TextSpan>();

      // The newline merges into the paragraph run that follows it, since both
      // are unmarked paragraph text — so match on content rather than equality.
      final heading = children.firstWhere((s) => s.text == 'Big');
      final body = children.firstWhere(
        (s) => s.text?.contains('small') ?? false,
      );

      expect(heading.style!.fontSize!, greaterThan(body.style!.fontSize!));
    });
  });

  test('tokens and the stripper agree about what a marker is', () {
    // The two consumers of `tokenize` must not drift: what the editor dims is
    // exactly what search and the assistant remove.
    const source = '# Heading\n- **bold** and *italic*\n> quote';

    final kept = Markup.tokenize(source)
        .where((token) => !token.isMarker)
        .map((token) => source.substring(token.start, token.end))
        .join();

    expect(kept, Markup.strip(source).text);
  });
}
