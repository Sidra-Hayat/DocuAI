import 'package:docuai/src/core/text/markup.dart';
import 'package:flutter_test/flutter_test.dart';

/// The formatting layer.
///
/// It runs over two very different inputs: text a person typed, where a marker
/// is an intention, and recognised text, where an asterisk is a smudge. It has
/// to be total over both — parsing happens on every export and every render, so
/// there is no input for which throwing is an acceptable answer.
void main() {
  List<MarkupBlockKind> kindsOf(String text) =>
      Markup.parse(text).map((block) => block.kind).toList();

  group('block structure', () {
    test('one line is one block', () {
      // Not "blank lines separate paragraphs": a form is one fact per line, and
      // joining them would read "Account number: NW-4471902 Invoice date: ..."
      // as a single sentence.
      final blocks = Markup.parse(
        'Account number: NW-4471902\nInvoice date: 12/03/2026',
      );

      expect(blocks, hasLength(2));
      expect(blocks.first.text, 'Account number: NW-4471902');
      expect(blocks.last.text, 'Invoice date: 12/03/2026');
    });

    test('blank lines produce no blocks', () {
      expect(Markup.parse('First.\n\n\nSecond.'), hasLength(2));
      expect(Markup.parse('   \n\t\n'), isEmpty);
      expect(Markup.parse(''), isEmpty);
    });

    test('headings are recognised at three depths', () {
      expect(kindsOf('# One\n## Two\n### Three'), <MarkupBlockKind>[
        MarkupBlockKind.heading1,
        MarkupBlockKind.heading2,
        MarkupBlockKind.heading3,
      ]);
      expect(Markup.parse('## Totals').single.text, 'Totals');
    });

    test('a fourth hash is not a heading', () {
      expect(kindsOf('#### Four'), <MarkupBlockKind>[
        MarkupBlockKind.paragraph,
      ]);
    });

    test('a hash with no space is not a heading', () {
      // "#1 priority" is prose, and treating it as a heading would silently
      // eat the hash.
      expect(kindsOf('#1 priority'), <MarkupBlockKind>[
        MarkupBlockKind.paragraph,
      ]);
      expect(Markup.parse('#1 priority').single.text, '#1 priority');
    });

    test('bullets are recognised in the forms people type', () {
      expect(kindsOf('- one\n* two\n• three'), <MarkupBlockKind>[
        MarkupBlockKind.bullet,
        MarkupBlockKind.bullet,
        MarkupBlockKind.bullet,
      ]);
    });

    test('numbered items keep the number they were written with', () {
      final blocks = Markup.parse('3. third\n4) fourth');

      expect(blocks.first.kind, MarkupBlockKind.numbered);
      expect(blocks.first.number, 3);
      expect(blocks.first.text, 'third');
      expect(blocks.last.number, 4);
    });

    test('a date at the start of a line is not a numbered item', () {
      // "12. 03. 2026" would otherwise become a list, which is how a naive
      // rule mangles a European date.
      expect(kindsOf('12/03/2026 is the due date'), <MarkupBlockKind>[
        MarkupBlockKind.paragraph,
      ]);
    });

    test('quotes are recognised', () {
      expect(kindsOf('> as agreed'), <MarkupBlockKind>[MarkupBlockKind.quote]);
      expect(Markup.parse('> as agreed').single.text, 'as agreed');
    });
  });

  group('emphasis', () {
    List<MarkupSpan> spansOf(String text) => Markup.parse(text).single.spans;

    test('bold and italic are resolved into runs', () {
      expect(spansOf('The **total** is *due*'), <MarkupSpan>[
        const MarkupSpan('The '),
        const MarkupSpan('total', bold: true),
        const MarkupSpan(' is '),
        const MarkupSpan('due', italic: true),
      ]);
    });

    test('underscores italicise too', () {
      expect(spansOf('_quietly_'), <MarkupSpan>[
        const MarkupSpan('quietly', italic: true),
      ]);
    });

    test('bold and italic can be combined', () {
      final spans = spansOf('**_both_**');

      expect(spans.single.bold, isTrue);
      expect(spans.single.italic, isTrue);
      expect(spans.single.text, 'both');
    });

    test('an unbalanced marker stays literal', () {
      // Half a pair exists for as long as it takes to type the other half, and
      // a stray asterisk in a scan is a smudge. Neither should swallow the
      // rest of the line.
      expect(Markup.parse('2 * 3 = 6').single.text, '2 * 3 = 6');
      expect(Markup.parse('**unclosed bold').single.text, '**unclosed bold');
    });

    test('no character is ever lost', () {
      // The invariant that matters: spans concatenated equal the input minus
      // exactly the markers that were consumed. Anything else means text
      // vanished between the editor and the export.
      const inputs = <String>[
        'plain',
        '**bold** and *italic*',
        'a * b * c',
        '****',
        '*',
        '_ _',
        'Total: 500.00 EUR **due 12/03/2026**',
        'T0tal amaunt due 5OO.OO EUR',
      ];

      for (final input in inputs) {
        final joined = Markup.parse(input).single.text;
        final stripped = input.replaceAll('*', '').replaceAll('_', '');

        expect(
          joined.replaceAll('*', '').replaceAll('_', ''),
          stripped,
          reason: 'characters disappeared from "$input"',
        );
      }
    });
  });

  group('toPlainText', () {
    test('strips markers and keeps the words', () {
      expect(
        Markup.toPlainText('# Invoice\n\n- **Total** 500.00 EUR'),
        'Invoice\nTotal 500.00 EUR',
      );
    });

    test('leaves recognised text exactly as it was', () {
      // A scan has no markers, so this must be the identity — otherwise every
      // existing document would read differently after this shipped.
      const recognised =
          'Northwind Utilities\nAccount number: NW-4471902\n'
          'Total amount due: 248.60 EUR';

      expect(Markup.toPlainText(recognised), recognised);
    });
  });

  group('totality', () {
    test('nothing throws, whatever it is given', () {
      const nasty = <String>[
        '',
        '\n\n\n',
        '#',
        '##',
        '-',
        '>',
        '1.',
        '***',
        '_'
            '**a*b**c*',
        '> # - 1. **',
        'æøå 中文 🙂 **emoji**',
      ];

      for (final input in nasty) {
        expect(() => Markup.parse(input), returnsNormally, reason: input);
        expect(() => Markup.toPlainText(input), returnsNormally, reason: input);
      }
    });
  });
}
