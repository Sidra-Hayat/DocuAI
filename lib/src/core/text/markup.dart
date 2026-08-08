/// What a line of a document is.
enum MarkupBlockKind {
  paragraph,
  heading1,
  heading2,
  heading3,
  bullet,
  numbered,
  quote,
}

/// A run of text with one set of emphasis applied to all of it.
class MarkupSpan {
  const MarkupSpan(this.text, {this.bold = false, this.italic = false});

  final String text;
  final bool bold;
  final bool italic;

  bool get isPlain => !bold && !italic;

  @override
  bool operator ==(Object other) =>
      other is MarkupSpan &&
      other.text == text &&
      other.bold == bold &&
      other.italic == italic;

  @override
  int get hashCode => Object.hash(text, bold, italic);

  @override
  String toString() =>
      'MarkupSpan("$text"${bold ? ', bold' : ''}${italic ? ', italic' : ''})';
}

/// One line of a document, classified, with its emphasis resolved.
class MarkupBlock {
  const MarkupBlock({
    required this.kind,
    required this.spans,
    this.number,
  });

  final MarkupBlockKind kind;
  final List<MarkupSpan> spans;

  /// The number a [MarkupBlockKind.numbered] item was written with. Kept so an
  /// export can renumber from it rather than assuming the list starts at one.
  final int? number;

  /// The block's text with every marker removed.
  String get text => spans.map((span) => span.text).join();

  bool get isEmpty => text.trim().isEmpty;
}

/// A small Markdown subset, held in the same plain string as recognised text.
///
/// The format is chosen for what it does *not* break. `DocumentPage.text` is
/// what the search index tokenises, what `PassageExtractor` splits into
/// sentences, and what the assistant quotes back to the user. A structured
/// representation — a Delta document, a JSON tree — would have to be kept in
/// step with a plain projection for all three, and the projection would be the
/// second source of truth this model exists to avoid. Markers in a string are
/// invisible to every one of them.
///
/// It also degrades in the right direction: recognised text contains no markers
/// and parses as a run of plain paragraphs, so a scanned document exports
/// exactly as it did before any of this existed.
///
/// Deliberately six constructs. Tables, links and images are not supported —
/// each would need a syntax nobody would discover, and a rendering in three
/// places.
abstract final class Markup {
  /// One line is one block.
  ///
  /// Not "blank lines separate paragraphs", which is the usual Markdown rule
  /// and the wrong one here: recognised text from a form or a table is one
  /// fact per line, and joining consecutive lines into a paragraph would turn
  /// `Account number: NW-4471902` and `Invoice date: 12/03/2026` into a single
  /// sentence containing both. Someone typing prose presses Enter where they
  /// mean a break, so this is right for written text too.
  static List<MarkupBlock> parse(String text) {
    final blocks = <MarkupBlock>[];

    for (final rawLine in text.split('\n')) {
      final line = rawLine.trimRight();
      if (line.trim().isEmpty) continue;

      blocks.add(_parseLine(line));
    }

    return List<MarkupBlock>.unmodifiable(blocks);
  }

  /// [text] with every marker removed and nothing else changed.
  ///
  /// For anywhere the text is read rather than rendered — quoting it back,
  /// copying it out — where `**Total**` would otherwise be shown verbatim.
  static String toPlainText(String text) => parse(
    text,
  ).map((block) => block.text).join('\n');

  /// [toPlainText] on one line, for quoting inside a sentence.
  ///
  /// What the assistant shows. A quoted answer, a summary line and a citation
  /// snippet are all single runs of prose in a chat bubble, and a heading's
  /// hashes or a bullet's dash in the middle of one is the syntax leaking out
  /// where only the words belong.
  ///
  /// **Display only.** Nothing here touches what is stored, what is indexed, or
  /// the offsets a passage carries — it runs on a string that has already been
  /// selected, ranked and cited, at the moment before it is drawn. That
  /// separation is the whole design: strip earlier and every offset behind it
  /// would shift.
  static String toInlineText(String text) => parse(text)
      .map((block) => block.text)
      .join(' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  static final RegExp _heading = RegExp(r'^(#{1,3})\s+(.*)$');
  static final RegExp _bullet = RegExp(r'^\s*[-*•]\s+(.*)$');
  static final RegExp _numbered = RegExp(r'^\s*(\d{1,3})[.)]\s+(.*)$');
  static final RegExp _quote = RegExp(r'^\s*>\s?(.*)$');

  static MarkupBlock _parseLine(String line) {
    final heading = _heading.firstMatch(line);
    if (heading != null) {
      return MarkupBlock(
        kind: switch (heading.group(1)!.length) {
          1 => MarkupBlockKind.heading1,
          2 => MarkupBlockKind.heading2,
          _ => MarkupBlockKind.heading3,
        },
        spans: _spans(heading.group(2)!),
      );
    }

    final numbered = _numbered.firstMatch(line);
    if (numbered != null) {
      return MarkupBlock(
        kind: MarkupBlockKind.numbered,
        spans: _spans(numbered.group(2)!),
        number: int.tryParse(numbered.group(1)!),
      );
    }

    final bullet = _bullet.firstMatch(line);
    if (bullet != null) {
      return MarkupBlock(
        kind: MarkupBlockKind.bullet,
        spans: _spans(bullet.group(1)!),
      );
    }

    final quote = _quote.firstMatch(line);
    if (quote != null) {
      return MarkupBlock(
        kind: MarkupBlockKind.quote,
        spans: _spans(quote.group(1)!),
      );
    }

    return MarkupBlock(kind: MarkupBlockKind.paragraph, spans: _spans(line));
  }

  /// Resolves `**bold**` and `*italic*` / `_italic_` into runs.
  ///
  /// Scanned rather than matched with a regex, so that an unbalanced marker
  /// stays literal instead of swallowing the rest of the line. This runs over
  /// recognised text, where a stray asterisk is a smudge rather than an
  /// intention, and over text being typed, where half a pair exists for as long
  /// as it takes to type the other half. It never throws and never loses a
  /// character: the concatenated spans always equal the input minus the markers
  /// it actually consumed.
  static List<MarkupSpan> _spans(String source) {
    if (source.isEmpty) return const <MarkupSpan>[];

    final spans = <MarkupSpan>[];
    final buffer = StringBuffer();
    var bold = false;
    var italic = false;
    var i = 0;

    void flush() {
      if (buffer.isEmpty) return;
      spans.add(MarkupSpan(buffer.toString(), bold: bold, italic: italic));
      buffer.clear();
    }

    while (i < source.length) {
      final rest = source.length - i;

      if (rest >= 2 && source.startsWith('**', i)) {
        // Only a marker if its partner exists. Otherwise it is two asterisks.
        if (bold || source.indexOf('**', i + 2) != -1) {
          flush();
          bold = !bold;
          i += 2;
          continue;
        }

        // Not a marker, so both characters are literal — and written out
        // together on purpose. Falling through would offer the first asterisk
        // to the italic rule below, which would find its "partner" in the
        // second one and quietly eat the pair: `**unclosed bold` came out as
        // `unclosed bold`.
        buffer.write('**');
        i += 2;
        continue;
      }

      final char = source[i];
      if (char == '*' || char == '_') {
        if (italic || source.indexOf(char, i + 1) != -1) {
          flush();
          italic = !italic;
          i += 1;
          continue;
        }
      }

      buffer.write(char);
      i += 1;
    }

    flush();
    return List<MarkupSpan>.unmodifiable(spans);
  }
}
