import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../../../../core/text/markup.dart';

/// One page's worth of text to set.
class DocxPage {
  const DocxPage(this.text);

  final String text;
}

/// Everything the writer needs, as plain data.
///
/// Holds strings only, for the same reason [PdfJob] does: it crosses an isolate
/// boundary and must carry nothing tied to the sending one.
class DocxJob {
  const DocxJob({required this.pages, required this.title});

  final List<DocxPage> pages;
  final String title;
}

/// Writes a Word document.
///
/// A `.docx` is a zip of XML parts, and the parts a reader actually requires
/// are few enough to write directly. The alternative — a template package with
/// placeholders — would mean shipping a binary asset nobody can review in a
/// diff, to produce a document this app fully controls the structure of.
///
/// **PDF carries the pages; this carries the text.** That is what the two
/// formats are for: a PDF is a faithful copy of what was scanned, and a Word
/// file is wanted because it can be edited. Embedding page images here would
/// produce a document whose text cannot be corrected without deleting a picture
/// of the same words.
///
/// Everything here is offline and dependency-light: `archive` for the zip, and
/// string building for the XML.
Future<Uint8List> composeDocxBytes(DocxJob job) async {
  final archive = Archive();

  void add(String path, String contents) {
    final bytes = utf8.encode(contents);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  add('[Content_Types].xml', _contentTypes);
  add('_rels/.rels', _packageRels);
  add('word/_rels/document.xml.rels', _documentRels);
  add('word/styles.xml', _styles);
  add('word/numbering.xml', _numbering);
  add('word/document.xml', _document(job));

  final zipped = ZipEncoder().encode(archive);
  return Uint8List.fromList(zipped);
}

/// How the composer runs a job. Injected so tests write inline rather than
/// paying an isolate spawn per case — the same shape as `PdfRenderer`.
typedef DocxWriter = Future<Uint8List> Function(DocxJob job);

/// Builds on a background isolate, matching the PDF path.
Future<Uint8List> writeDocxInIsolate(DocxJob job) =>
    Isolate.run(() => composeDocxBytes(job));

// ---- the parts ------------------------------------------------------------

const String _contentTypes =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
    '<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>'
    '</Types>';

const String _packageRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" '
    'Target="word/document.xml"/>'
    '</Relationships>';

const String _documentRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" '
    'Target="styles.xml"/>'
    '<Relationship Id="rId2" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" '
    'Target="numbering.xml"/>'
    '</Relationships>';

/// Named styles, so headings are headings in Word's own navigation pane rather
/// than merely large text.
const String _styles =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
    '<w:style w:type="paragraph" w:default="1" w:styleId="Normal">'
    '<w:name w:val="Normal"/>'
    '<w:pPr><w:spacing w:after="120"/></w:pPr>'
    '<w:rPr><w:sz w:val="22"/></w:rPr>'
    '</w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading1">'
    '<w:name w:val="heading 1"/><w:basedOn w:val="Normal"/>'
    '<w:pPr><w:outlineLvl w:val="0"/><w:spacing w:before="240" w:after="120"/></w:pPr>'
    '<w:rPr><w:b/><w:sz w:val="32"/></w:rPr>'
    '</w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading2">'
    '<w:name w:val="heading 2"/><w:basedOn w:val="Normal"/>'
    '<w:pPr><w:outlineLvl w:val="1"/><w:spacing w:before="200" w:after="100"/></w:pPr>'
    '<w:rPr><w:b/><w:sz w:val="26"/></w:rPr>'
    '</w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading3">'
    '<w:name w:val="heading 3"/><w:basedOn w:val="Normal"/>'
    '<w:pPr><w:outlineLvl w:val="2"/><w:spacing w:before="160" w:after="80"/></w:pPr>'
    '<w:rPr><w:b/><w:sz w:val="24"/></w:rPr>'
    '</w:style>'
    '<w:style w:type="paragraph" w:styleId="ListParagraph">'
    '<w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/>'
    '<w:pPr><w:ind w:left="720"/><w:contextualSpacing/></w:pPr>'
    '</w:style>'
    '<w:style w:type="paragraph" w:styleId="Quote">'
    '<w:name w:val="Quote"/><w:basedOn w:val="Normal"/>'
    '<w:pPr><w:ind w:left="720"/></w:pPr>'
    '<w:rPr><w:i/></w:rPr>'
    '</w:style>'
    '</w:styles>';

/// Two lists: bullets on numId 1, decimals on numId 2.
const String _numbering =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
    '<w:abstractNum w:abstractNumId="0">'
    '<w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="bullet"/>'
    '<w:lvlText w:val="&#8226;"/><w:lvlJc w:val="left"/>'
    '<w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl>'
    '</w:abstractNum>'
    '<w:abstractNum w:abstractNumId="1">'
    '<w:lvl w:ilvl="0"><w:start w:val="1"/><w:numFmt w:val="decimal"/>'
    '<w:lvlText w:val="%1."/><w:lvlJc w:val="left"/>'
    '<w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr></w:lvl>'
    '</w:abstractNum>'
    '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'
    '<w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>'
    '</w:numbering>';

String _document(DocxJob job) {
  final body = StringBuffer();

  for (var i = 0; i < job.pages.length; i++) {
    // A page break between pages, so a multi-page document opens looking like
    // the document it came from rather than one continuous run of text.
    if (i > 0) {
      body.write(
        '<w:p><w:r><w:br w:type="page"/></w:r></w:p>',
      );
    }

    for (final block in Markup.parse(job.pages[i].text)) {
      body.write(_paragraph(block));
    }
  }

  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>'
      '$body'
      '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
      '<w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"/>'
      '</w:sectPr>'
      '</w:body></w:document>';
}

String _paragraph(MarkupBlock block) {
  final properties = switch (block.kind) {
    MarkupBlockKind.heading1 => '<w:pStyle w:val="Heading1"/>',
    MarkupBlockKind.heading2 => '<w:pStyle w:val="Heading2"/>',
    MarkupBlockKind.heading3 => '<w:pStyle w:val="Heading3"/>',
    MarkupBlockKind.quote => '<w:pStyle w:val="Quote"/>',
    MarkupBlockKind.bullet =>
      '<w:pStyle w:val="ListParagraph"/>'
          '<w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr>',
    MarkupBlockKind.numbered =>
      '<w:pStyle w:val="ListParagraph"/>'
          '<w:numPr><w:ilvl w:val="0"/><w:numId w:val="2"/></w:numPr>',
    MarkupBlockKind.paragraph => '',
  };

  final runs = StringBuffer();
  for (final span in block.spans) {
    if (span.text.isEmpty) continue;

    final emphasis = StringBuffer();
    if (span.bold) emphasis.write('<w:b/>');
    if (span.italic) emphasis.write('<w:i/>');

    runs
      ..write('<w:r>')
      ..write(emphasis.isEmpty ? '' : '<w:rPr>$emphasis</w:rPr>')
      // xml:space matters: without it a reader is free to collapse the leading
      // and trailing spaces that hold words apart across runs.
      ..write('<w:t xml:space="preserve">${_escape(span.text)}</w:t>')
      ..write('</w:r>');
  }

  final props = properties.isEmpty ? '' : '<w:pPr>$properties</w:pPr>';
  return '<w:p>$props$runs</w:p>';
}

/// Escapes the five characters XML cannot carry literally.
///
/// Not optional politeness: recognised text routinely contains `&` and `<`
/// from prices, comparisons and OCR noise, and one unescaped ampersand makes
/// the whole package unopenable.
String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
