import 'package:docuai/src/features/documents/domain/entities/document_block.dart';
import 'package:flutter_test/flutter_test.dart';

/// The seam between the page's stored text and the editor's rows.
///
/// Everything the block editor is allowed to claim rests on one property: a
/// page's text goes through [DocumentBlocks.parse] and [DocumentBlocks.serialize]
/// and comes back *identical*. If that holds, no Hive model changes, no
/// migration runs, the Markup parser sees what it always saw, and a document
/// written before the editor existed opens in it and saves back byte for byte.
///
/// If it does not hold, every document in the library rewrites itself the first
/// time it is opened — which is why this file leads with the round trip and
/// checks it against every shape a real page takes.
void main() {
  var counter = 0;
  String newId() => 'b${counter++}';

  setUp(() => counter = 0);

  List<DocumentBlock> parse(String text) =>
      DocumentBlocks.parse(text, newId: newId);

  String roundTrip(String text) =>
      DocumentBlocks.serialize(parse(text));

  group('the round trip', () {
    test('leaves plain text exactly as it was', () {
      const text = 'The deposit is 500.00 EUR.\nPayable on signing.';

      expect(roundTrip(text), text);
    });

    test('leaves formatted text exactly as it was', () {
      const text =
          '# Tenancy agreement\n'
          '\n'
          'The **tenant** is Aisha Rahman.\n'
          '- One month notice\n'
          '- Deposit before the start date\n'
          '> Signed in duplicate';

      expect(roundTrip(text), text);
    });

    test('leaves a page of text and pictures exactly as it was', () {
      const text =
          'Before the picture\n'
          '![Image](abc123.jpg)\n'
          'After the picture';

      expect(roundTrip(text), text);
    });

    test('preserves the blank lines the old inserter wrote', () {
      // What `MarkupEditing.insertImage` produced before this editor existed.
      // Blank lines separate paragraphs for the reader and for the passage
      // extractor, so losing one would change what the assistant quotes.
      const text =
          'Notes\n'
          '\n'
          '![Image](a.jpg)\n'
          '\n'
          'More notes';

      expect(roundTrip(text), text);
    });

    test('handles a page that opens with a picture', () {
      const text = '![Image](a.jpg)\nUnderneath';

      expect(roundTrip(text), text);
    });

    test('handles a page that ends with a picture', () {
      const text = 'Above\n![Image](a.jpg)';

      expect(roundTrip(text), text);
    });

    test('handles two pictures in a row', () {
      const text = '![Image](a.jpg)\n![Image](b.jpg)';

      expect(roundTrip(text), text);
    });

    test('handles a page that is nothing but a picture', () {
      const text = '![Image](only.jpg)';

      expect(roundTrip(text), text);
    });

    test('leaves an empty page empty', () {
      expect(roundTrip(''), '');
    });

    test('leaves recognised text from a scan untouched', () {
      // The commonest page in the library by far, and the one with no pictures
      // in it at all. It must survive the editor without gaining a character.
      const text =
          'Northwind Utilities quarterly electricity statement.\n'
          'Account number: NW-4471902\n'
          'Total amount due: 248.60 EUR';

      expect(roundTrip(text), text);
    });
  });

  group('parsing', () {
    test('gives every picture a text block to sit between', () {
      // Without one there is nowhere to put the caret to type above a picture
      // that starts the page, or between two that are adjacent.
      final blocks = parse('![Image](a.jpg)\n![Image](b.jpg)');

      expect(blocks.map((block) => block.runtimeType).toList(), <Type>[
        TextBlock,
        ImageBlock,
        TextBlock,
        ImageBlock,
        TextBlock,
      ]);
    });

    test('reads a picture as a picture, not as text', () {
      final blocks = parse('Above\n![Image](photo.jpg)\nBelow');

      expect(blocks, hasLength(3));
      expect((blocks[0] as TextBlock).text, 'Above');
      expect((blocks[1] as ImageBlock).imageName, 'photo.jpg');
      expect((blocks[2] as TextBlock).text, 'Below');
    });

    test('a reference inside a sentence stays ordinary text', () {
      // Only a line that is *entirely* a reference is a picture — the same rule
      // the Markup parser has always followed.
      final blocks = parse('See ![Image](a.jpg) here');

      expect(blocks, hasLength(1));
      expect(blocks.single, isA<TextBlock>());
    });

    test('keeps blank lines inside a text block', () {
      final blocks = parse('One\n\nTwo');

      expect((blocks.single as TextBlock).text, 'One\n\nTwo');
    });

    test('ids are unique, so a row can key a widget', () {
      final blocks = parse('a\n![Image](x.jpg)\nb\n![Image](y.jpg)\nc');
      final ids = blocks.map((block) => block.id).toSet();

      expect(ids, hasLength(blocks.length));
    });
  });

  group('serializing', () {
    test('drops the empty text blocks the editor needs', () {
      // They exist so there is a caret position beside every picture. Written
      // out, a document would gain a blank line every time it was opened.
      final blocks = <DocumentBlock>[
        const TextBlock(id: '0', text: ''),
        const ImageBlock(id: '1', imageName: 'a.jpg'),
        const TextBlock(id: '2', text: ''),
      ];

      expect(DocumentBlocks.serialize(blocks), '![Image](a.jpg)');
    });

    test('opening and closing a page repeatedly does not grow it', () {
      var text = 'Notes\n![Image](a.jpg)\nMore';

      for (var i = 0; i < 5; i++) {
        text = roundTrip(text);
      }

      expect(text, 'Notes\n![Image](a.jpg)\nMore');
    });

    test('writes the reference in the format the rest of the app reads', () {
      final blocks = <DocumentBlock>[
        const ImageBlock(id: '0', imageName: 'x.jpg'),
      ];

      // The PDF composer, the reader and the orphan sweep all match on this
      // exact shape.
      expect(DocumentBlocks.serialize(blocks), '![Image](x.jpg)');
    });

    test('lists the pictures a page refers to, in order', () {
      final blocks = parse('a\n![Image](one.jpg)\nb\n![Image](two.jpg)');

      expect(DocumentBlocks.imageNames(blocks), <String>[
        'one.jpg',
        'two.jpg',
      ]);
    });
  });
}
