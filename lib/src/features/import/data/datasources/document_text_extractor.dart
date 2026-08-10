import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Reads the words out of a file that is already text.
///
/// Plain text needs decoding and nothing else. A Word file needs unzipping
/// first — a `.docx` is a ZIP of XML — which the app can already do, because it
/// *writes* one for export. This is the same knowledge read backwards.
abstract final class DocumentTextExtractor {
  /// Decodes plain text, tolerating a byte-order mark and invalid sequences.
  ///
  /// Malformed bytes become replacement characters rather than an exception:
  /// a text file saved in some other encoding should import mostly-readable and
  /// be correctable by hand, not refuse to open at all.
  static String plainText(Uint8List bytes) {
    final decoded = const Utf8Decoder(allowMalformed: true).convert(bytes);
    return decoded.startsWith('﻿') ? decoded.substring(1) : decoded;
  }

  /// Pulls the readable text out of a `.docx`.
  ///
  /// Word stores a paragraph as `w:p` and its runs of text as `w:t`. Everything
  /// else in the part — styles, revision marks, section properties — is
  /// formatting the app has no use for, so the extraction walks paragraphs and
  /// concatenates their text rather than stripping tags out of the raw string.
  /// Tag-stripping would silently glue the last word of one paragraph to the
  /// first word of the next.
  ///
  /// Returns an empty string for anything that is not a readable Word file,
  /// which the caller reports as a file it could not open.
  static String wordDocument(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return '';
    }

    final part = archive.files
        .where((file) => file.name == 'word/document.xml')
        .firstOrNull;
    if (part == null) return '';

    final XmlDocument xml;
    try {
      xml = XmlDocument.parse(
        const Utf8Decoder(
          allowMalformed: true,
        ).convert(part.content as List<int>),
      );
    } catch (_) {
      return '';
    }

    final paragraphs = <String>[];
    for (final paragraph in xml.findAllElements('w:p')) {
      final buffer = StringBuffer();

      for (final node in paragraph.descendantElements) {
        switch (node.name.qualified) {
          case 'w:t':
            buffer.write(node.innerText);
          // A soft line break inside a paragraph is a line break in the text.
          case 'w:br':
            buffer.write('\n');
          case 'w:tab':
            buffer.write('\t');
        }
      }

      paragraphs.add(buffer.toString().trimRight());
    }

    // Runs of blank paragraphs collapse to one. Word documents are full of
    // empty paragraphs used as spacing, and carrying every one of them into a
    // plain-text page produces a document that is mostly gaps.
    final cleaned = <String>[];
    for (final paragraph in paragraphs) {
      if (paragraph.isEmpty && (cleaned.isEmpty || cleaned.last.isEmpty)) {
        continue;
      }
      cleaned.add(paragraph);
    }

    return cleaned.join('\n').trim();
  }
}
