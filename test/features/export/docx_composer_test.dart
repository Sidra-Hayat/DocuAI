import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:docuai/src/features/export/data/datasources/docx_composer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

/// The Word export.
///
/// A `.docx` is a zip of XML parts, and the failure mode that matters is not a
/// crash — it is a file that builds fine and that Word refuses to open, which
/// nobody discovers until they have sent it to someone. So these assert on the
/// package structure and on well-formedness, not only on the words.
///
/// What they cannot prove is that Word itself opens the result. That needs
/// Word, and is a manual check.
void main() {
  Future<Archive> buildArchive(DocxJob job) async =>
      ZipDecoder().decodeBytes(await composeDocxBytes(job));

  Future<String> partOf(DocxJob job, String path) async {
    final archive = await buildArchive(job);
    final file = archive.findFile(path);
    expect(file, isNotNull, reason: '$path is missing from the package');
    return utf8.decode(file!.content as List<int>);
  }

  Future<String> documentXml(String text) =>
      partOf(DocxJob(pages: <DocxPage>[DocxPage(text)], title: 'T'), 'word/document.xml');

  group('the package', () {
    test('carries every part a reader requires', () async {
      final archive = await buildArchive(
        const DocxJob(pages: <DocxPage>[DocxPage('Hello.')], title: 'Note'),
      );

      final paths = archive.files.map((file) => file.name).toSet();
      expect(paths, containsAll(<String>[
        '[Content_Types].xml',
        '_rels/.rels',
        'word/_rels/document.xml.rels',
        'word/document.xml',
        'word/styles.xml',
        'word/numbering.xml',
      ]));
    });

    test('every part is well-formed XML', () async {
      // One malformed part is a file that opens nowhere, and the error a
      // reader shows for it says nothing useful.
      final archive = await buildArchive(
        const DocxJob(
          pages: <DocxPage>[DocxPage('# Heading\n- item\nText & more')],
          title: 'Note',
        ),
      );

      for (final file in archive.files) {
        expect(
          () => XmlDocument.parse(utf8.decode(file.content as List<int>)),
          returnsNormally,
          reason: '${file.name} is not well-formed',
        );
      }
    });

    test('the content types declare the parts that need declaring', () async {
      final types = await partOf(
        const DocxJob(pages: <DocxPage>[DocxPage('x')], title: 'T'),
        '[Content_Types].xml',
      );

      expect(types, contains('/word/document.xml'));
      expect(types, contains('/word/styles.xml'));
      expect(types, contains('/word/numbering.xml'));
    });

    test('the document relates to its styles and numbering', () async {
      final rels = await partOf(
        const DocxJob(pages: <DocxPage>[DocxPage('x')], title: 'T'),
        'word/_rels/document.xml.rels',
      );

      expect(rels, contains('styles.xml'));
      expect(rels, contains('numbering.xml'));
    });
  });

  group('formatting survives', () {
    test('headings become heading styles, not big text', () async {
      // A style is what puts them in Word's navigation pane and what survives
      // the reader's own theme.
      final xml = await documentXml('# One\n## Two\n### Three');

      expect(xml, contains('w:val="Heading1"'));
      expect(xml, contains('w:val="Heading2"'));
      expect(xml, contains('w:val="Heading3"'));
      expect(xml, isNot(contains('# One')));
    });

    test('bold and italic become runs', () async {
      final xml = await documentXml('The **total** is *due*');

      expect(xml, contains('<w:b/>'));
      expect(xml, contains('<w:i/>'));
      expect(xml, contains('>total<'));
      expect(xml, isNot(contains('**')));
    });

    test('bullets and numbered items use real lists', () async {
      final xml = await documentXml('- one\n- two\n1. first\n2. second');

      // numId 1 is the bullet list, 2 the decimal one.
      expect(xml, contains('<w:numId w:val="1"/>'));
      expect(xml, contains('<w:numId w:val="2"/>'));
      expect(xml, isNot(contains('- one')));
    });

    test('quotes get the quote style', () async {
      expect(await documentXml('> as agreed'), contains('w:val="Quote"'));
    });

    test('paragraphs stay paragraphs', () async {
      final xml = await documentXml('First line.\nSecond line.');
      final document = XmlDocument.parse(xml);

      expect(
        document.findAllElements('w:p').length,
        2,
        reason: 'one line is one paragraph',
      );
    });

    test('spacing between runs is preserved', () async {
      // Without xml:space a reader may collapse the spaces holding words
      // apart across a formatting boundary — "The total is due" becomes
      // "Thetotalisdue".
      final xml = await documentXml('The **total** is due');

      expect(xml, contains('xml:space="preserve"'));
      expect(
        XmlDocument.parse(xml)
            .findAllElements('w:t')
            .map((element) => element.innerText)
            .join(),
        'The total is due',
      );
    });
  });

  group('text that would break the XML', () {
    test('ampersands and angle brackets survive a round trip', () async {
      // Recognised text is full of these. One unescaped ampersand makes the
      // whole package unopenable.
      const nasty = 'Smith & Sons <Ltd> "quoted" 5 > 3';
      final xml = await documentXml(nasty);

      expect(() => XmlDocument.parse(xml), returnsNormally);
      expect(
        XmlDocument.parse(xml)
            .findAllElements('w:t')
            .map((element) => element.innerText)
            .join(),
        nasty,
      );
    });

    test('non-Latin text is carried as written', () async {
      const text = 'Grüße · 中文 · مرحبا';
      final xml = await documentXml(text);

      expect(
        XmlDocument.parse(xml)
            .findAllElements('w:t')
            .map((element) => element.innerText)
            .join(),
        text,
      );
    });
  });

  group('multiple pages', () {
    test('each page after the first starts on a new one', () async {
      final xml = await partOf(
        const DocxJob(
          pages: <DocxPage>[
            DocxPage('Page one.'),
            DocxPage('Page two.'),
            DocxPage('Page three.'),
          ],
          title: 'Three',
        ),
        'word/document.xml',
      );

      expect(
        'w:type="page"'.allMatches(xml).length,
        2,
        reason: 'breaks go between pages, not before the first',
      );
    });

    test('every page contributes its text', () async {
      final xml = await partOf(
        const DocxJob(
          pages: <DocxPage>[DocxPage('First page.'), DocxPage('Second page.')],
          title: 'Two',
        ),
        'word/document.xml',
      );

      expect(xml, contains('First page.'));
      expect(xml, contains('Second page.'));
    });
  });

  test('recognised text with no markers exports as plain paragraphs', () async {
    // The path every existing scanned document takes.
    const recognised =
        'Northwind Utilities\nAccount number: NW-4471902\n'
        'Total amount due: 248.60 EUR';

    final xml = await documentXml(recognised);
    final document = XmlDocument.parse(xml);

    expect(document.findAllElements('w:p').length, 3);
    expect(xml, isNot(contains('pStyle')));
    expect(
      document.findAllElements('w:t').map((e) => e.innerText).join('\n'),
      recognised,
    );
  });
}
