import 'package:docuai/src/core/text/markup.dart';
import 'package:docuai/src/core/text/markup_editing.dart';
import 'package:flutter_test/flutter_test.dart';

/// The formatting toolbar, as pure text operations.
///
/// Tested without a widget on purpose: what a toolbar button has to get right
/// is where the markers land and where the selection ends up, and neither needs
/// a keyboard to check. The widget then only has to wire a button to one of
/// these.
void main() {
  /// A convenient way to write "this text with this bit selected".
  ///
  /// `|` marks a caret, `[` and `]` a selection.
  TextEdit at(String marked) {
    if (marked.contains('|')) {
      final index = marked.indexOf('|');
      return TextEdit(
        text: marked.replaceFirst('|', ''),
        start: index,
        end: index,
      );
    }

    final start = marked.indexOf('[');
    final end = marked.indexOf(']') - 1;
    return TextEdit(
      text: marked.replaceFirst('[', '').replaceFirst(']', ''),
      start: start,
      end: end,
    );
  }

  /// The result written back in the same notation, so a failure reads as text
  /// rather than as three numbers.
  String show(TextEdit edit) {
    if (edit.isCollapsed) {
      return '${edit.text.substring(0, edit.start)}|'
          '${edit.text.substring(edit.start)}';
    }
    return '${edit.text.substring(0, edit.start)}['
        '${edit.text.substring(edit.start, edit.end)}]'
        '${edit.text.substring(edit.end)}';
  }

  group('bold', () {
    test('wraps the selection', () {
      expect(
        show(MarkupEditing.toggleBold(at('The [deposit] is due'))),
        'The **[deposit]** is due',
      );
    });

    test('unwraps a selection that is already bold', () {
      expect(
        show(MarkupEditing.toggleBold(at('The **[deposit]** is due'))),
        'The [deposit] is due',
      );
    });

    test('unwraps when the markers are inside the selection', () {
      // What you get by selecting a whole bold word by double-tapping it.
      expect(
        show(MarkupEditing.toggleBold(at('The [**deposit**] is due'))),
        'The [deposit] is due',
      );
    });

    test('with no selection it opens a pair and waits inside it', () {
      expect(
        show(MarkupEditing.toggleBold(at('The |is due'))),
        'The **|** is due'.replaceFirst(' is due', 'is due'),
      );
    });

    test('is a toggle — twice returns the original', () {
      final once = MarkupEditing.toggleBold(at('The [deposit] is due'));
      final twice = MarkupEditing.toggleBold(once);

      expect(twice.text, 'The deposit is due');
    });
  });

  group('italic', () {
    test('wraps the selection', () {
      expect(
        show(MarkupEditing.toggleItalic(at('paid [late] again'))),
        'paid *[late]* again',
      );
    });

    test('unwraps an italic selection', () {
      expect(
        show(MarkupEditing.toggleItalic(at('paid *[late]* again'))),
        'paid [late] again',
      );
    });

    test('does not mistake the inner asterisk of a bold pair for italic', () {
      // `**word**` must not unwrap to `*word*` when italic is pressed.
      final result = MarkupEditing.toggleItalic(at('The **[deposit]** is due'));

      expect(result.text, 'The ***deposit*** is due');
    });

    test('is a toggle', () {
      final once = MarkupEditing.toggleItalic(at('paid [late] again'));
      expect(MarkupEditing.toggleItalic(once).text, 'paid late again');
    });
  });

  group('heading', () {
    test('marks the line the caret is on', () {
      expect(
        MarkupEditing.toggleHeading(at('Tenancy| agreement')).text,
        '## Tenancy agreement',
      );
    });

    test('removes it when pressed again', () {
      expect(
        MarkupEditing.toggleHeading(at('## Tenancy| agreement')).text,
        'Tenancy agreement',
      );
    });

    test('respects the level asked for', () {
      expect(
        MarkupEditing.toggleHeading(at('Title|'), level: 1).text,
        '# Title',
      );
      expect(
        MarkupEditing.toggleHeading(at('Title|'), level: 3).text,
        '### Title',
      );
    });

    test('replaces another block marker rather than stacking on it', () {
      // `# - item` is markup nothing in this app reads.
      expect(
        MarkupEditing.toggleHeading(at('- item|')).text,
        '## item',
      );
    });

    test('leaves the other lines alone', () {
      expect(
        MarkupEditing.toggleHeading(at('first|\nsecond\nthird')).text,
        '## first\nsecond\nthird',
      );
    });
  });

  group('bullet list', () {
    test('marks one line', () {
      expect(MarkupEditing.toggleBullet(at('milk|')).text, '- milk');
    });

    test('marks every line the selection touches', () {
      expect(
        MarkupEditing.toggleBullet(at('[milk\neggs\nbread]')).text,
        '- milk\n- eggs\n- bread',
      );
    });

    test('removes them all when every line already has one', () {
      expect(
        MarkupEditing.toggleBullet(at('[- milk\n- eggs]')).text,
        'milk\neggs',
      );
    });

    test('a mixed selection gains the marker rather than losing it', () {
      // Half-marked means the user is asking for the style, not to lose it.
      expect(
        MarkupEditing.toggleBullet(at('[- milk\neggs]')).text,
        '- milk\n- eggs',
      );
    });
  });

  group('numbered list', () {
    test('counts from one', () {
      expect(
        MarkupEditing.toggleNumbered(at('[milk\neggs\nbread]')).text,
        '1. milk\n2. eggs\n3. bread',
      );
    });

    test('renumbers rather than repeating "1."', () {
      final result = MarkupEditing.toggleNumbered(at('[a\nb\nc\nd]'));

      expect(result.text, '1. a\n2. b\n3. c\n4. d');
    });

    test('toggles off', () {
      expect(
        MarkupEditing.toggleNumbered(at('[1. milk\n2. eggs]')).text,
        'milk\neggs',
      );
    });

    test('converts a bullet list in place', () {
      expect(
        MarkupEditing.toggleNumbered(at('[- milk\n- eggs]')).text,
        '1. milk\n2. eggs',
      );
    });
  });

  group('quote', () {
    test('marks the line', () {
      expect(MarkupEditing.toggleQuote(at('as agreed|')).text, '> as agreed');
    });

    test('toggles off', () {
      expect(MarkupEditing.toggleQuote(at('> as agreed|')).text, 'as agreed');
    });

    test('applies across a selection', () {
      expect(
        MarkupEditing.toggleQuote(at('[one\ntwo]')).text,
        '> one\n> two',
      );
    });
  });

  group('the selection follows the text', () {
    test('a line prefix moves the caret with its line', () {
      final result = MarkupEditing.toggleBullet(at('mi|lk'));

      expect(result.text, '- milk');
      expect(
        result.text.substring(0, result.start),
        '- mi',
        reason: 'the caret must stay between the same two characters',
      );
    });

    test('removing a prefix moves it back', () {
      final result = MarkupEditing.toggleBullet(at('- mi|lk'));

      expect(result.text, 'milk');
      expect(result.text.substring(0, result.start), 'mi');
    });

    test('a wrapped selection still covers the same words', () {
      final result = MarkupEditing.toggleBold(at('The [deposit] is due'));

      expect(result.selected, 'deposit');
    });

    test('an offset is never outside the text it indexes', () {
      const cases = <String>[
        '|',
        'a|',
        '[abc]',
        '|\n\n',
        '[- a\n- b]',
        '**[bold]**',
      ];

      for (final marked in cases) {
        for (final operation in <TextEdit Function(TextEdit)>[
          MarkupEditing.toggleBold,
          MarkupEditing.toggleItalic,
          MarkupEditing.toggleHeading,
          MarkupEditing.toggleBullet,
          MarkupEditing.toggleNumbered,
          MarkupEditing.toggleQuote,
        ]) {
          final result = operation(at(marked));

          expect(result.start, inInclusiveRange(0, result.text.length),
              reason: marked);
          expect(result.end, inInclusiveRange(0, result.text.length),
              reason: marked);
          expect(result.start, lessThanOrEqualTo(result.end), reason: marked);
        }
      }
    });
  });

  group('plain recognised text', () {
    const recognised =
        'Northwind Utilities\nAccount number: NW-4471902\n'
        'Total amount due: 248.60 EUR';

    test('is untouched until a button is pressed', () {
      // Opening a scanned page in the editor must not rewrite it.
      expect(Markup.strip(recognised).text, recognised);
    });

    test('a toolbar press changes only the line it was used on', () {
      final edit = TextEdit(text: recognised, start: 0, end: 0);
      final result = MarkupEditing.toggleHeading(edit);

      expect(result.text, '## Northwind Utilities\n'
          'Account number: NW-4471902\nTotal amount due: 248.60 EUR');
    });
  });

  group('half-typed markup', () {
    test('an unclosed marker is not treated as a wrapper', () {
      // Pressing bold with `**unclosed` before the caret must add a pair, not
      // try to unwrap something that was never wrapped.
      final result = MarkupEditing.toggleBold(at('**unclosed [word]'));

      expect(result.text, '**unclosed **word**');
    });

    test('every operation is total over awkward input', () {
      const nasty = <String>['', '\n', '***', '#', '- ', '1.', '>', '_'];

      for (final text in nasty) {
        final edit = TextEdit(text: text, start: 0, end: text.length);

        for (final operation in <TextEdit Function(TextEdit)>[
          MarkupEditing.toggleBold,
          MarkupEditing.toggleItalic,
          MarkupEditing.toggleHeading,
          MarkupEditing.toggleBullet,
          MarkupEditing.toggleNumbered,
          MarkupEditing.toggleQuote,
        ]) {
          expect(() => operation(edit), returnsNormally, reason: '"$text"');
        }
      }
    });
  });

  group('what the editor draws', () {
    test('tokens cover every character exactly once', () {
      // The invariant live styling rests on: spans whose lengths do not sum to
      // the text length put the caret somewhere other than where it appears.
      const sources = <String>[
        '',
        'plain',
        '# Heading\n- **bold** item\n1. numbered\n> quoted',
        '**a** *b* _c_ ****',
        'Total amount due: 248.60 EUR',
        '2 * 3 = 6',
      ];

      for (final source in sources) {
        final tokens = Markup.tokenize(source);

        var cursor = 0;
        for (final token in tokens) {
          expect(token.start, cursor, reason: 'gap or overlap in "$source"');
          cursor = token.end;
        }
        expect(cursor, source.length, reason: 'tokens stop short of "$source"');
      }
    });

    test('markers are classified apart from the words', () {
      final tokens = Markup.tokenize('The **total** is due');
      const source = 'The **total** is due';

      final markers = tokens
          .where((token) => token.isMarker)
          .map((token) => source.substring(token.start, token.end));

      expect(markers, <String>['**', '**']);
    });

    test('emphasis is reported on the words it applies to', () {
      const source = 'The **total** is due';
      final bold = Markup.tokenize(source)
          .where((token) => token.bold && !token.isMarker)
          .map((token) => source.substring(token.start, token.end))
          .join();

      expect(bold, 'total');
    });

    test('a heading line is reported as one', () {
      final tokens = Markup.tokenize('## Totals\nplain');

      expect(tokens.first.block, MarkupBlockKind.heading2);
      expect(tokens.last.block, MarkupBlockKind.paragraph);
    });

    test('emphasis does not leak across a line break', () {
      const source = '**open\nnext line';
      final bold = Markup.tokenize(
        source,
      ).where((token) => token.bold).toList();

      expect(bold, isEmpty);
    });
  });
}
