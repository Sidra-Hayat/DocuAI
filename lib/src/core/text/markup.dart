/// One run of characters that share a classification.
///
/// Tokens tile their source exactly — no gaps, no overlaps — which is what lets
/// an editor turn them into text spans without the caret drifting from what is
/// drawn.
class MarkupToken {
  const MarkupToken({
    required this.start,
    required this.end,
    required this.isMarker,
    required this.bold,
    required this.italic,
    required this.block,
  });

  /// Range in the source, end exclusive.
  final int start;
  final int end;

  /// True for syntax rather than content: `**`, a leading `# `, a bullet's
  /// dash. Removed for display, dimmed in an editor.
  final bool isMarker;

  /// Emphasis in force across this run. A closing marker carries the emphasis
  /// of the run it closes, so it reads as part of that run.
  final bool bold;
  final bool italic;

  /// The kind of line this run sits on.
  final MarkupBlockKind block;

  int get length => end - start;
}

/// Text with its markers removed, and where every character went.
class StrippedText {
  const StrippedText(this.text, this.offsets);

  /// The text as it will be shown.
  final String text;

  /// `offsets[i]` is where source character `i` now sits in [text]. One longer
  /// than the source, so an exclusive end index maps too.
  final List<int> offsets;

  /// Maps a range in the source onto the same range in [text].
  ///
  /// Clamped rather than trusted: a caller working from a stale index should
  /// get an unhighlighted snippet, not a `RangeError` inside a `build`.
  (int, int) mapRange(int start, int end) {
    final from = offsets[start.clamp(0, offsets.length - 1)];
    final to = offsets[end.clamp(0, offsets.length - 1)];
    return (from, to < from ? from : to);
  }
}

/// What a line of a document is.
enum MarkupBlockKind {
  paragraph,
  heading1,
  heading2,
  heading3,
  bullet,
  numbered,
  quote,

  /// A picture the user placed in a written document.
  ///
  /// The odd one out: it holds no words. The whole line is a reference, which
  /// is why it is classified as a marker from end to end — so it disappears
  /// from every consumer that wants text, and appears only in the ones that
  /// draw.
  image,
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
    this.imageName,
  });

  final MarkupBlockKind kind;
  final List<MarkupSpan> spans;

  /// For [MarkupBlockKind.image], the file's name inside the document's own
  /// `inline/` folder — never a path, and never one from outside the sandbox.
  ///
  /// A name rather than a path because the folder is derivable: an inline image
  /// belongs to the document whose text references it, and that document knows
  /// its own id. Storing the full path would bake the id into the text, where
  /// it would be one more thing to rewrite if a document were ever copied.
  final String? imageName;

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
  static String toPlainText(String text) =>
      parse(text).map((block) => block.text).join('\n');

  /// Stripped text together with a map from where every character *was* to
  /// where it now is.
  ///
  /// The map is what makes a search highlight survive the cleaning. A snippet
  /// carries `highlightStart`/`highlightLength` into the string it renders, so
  /// removing characters without moving those offsets would leave the
  /// highlight sitting over the wrong words — later in the line by exactly the
  /// number of markers removed before it.
  ///
  /// `offsets` has one entry per source character plus one, so an exclusive end
  /// index maps as cleanly as a start does. Characters that were removed map to
  /// the position their successor took, which is what makes a match that begins
  /// or ends inside a marker collapse onto the text rather than beside it.
  static StrippedText strip(String source) {
    final offsets = List<int>.filled(source.length + 1, 0);
    final buffer = StringBuffer();

    for (final token in tokenize(source)) {
      for (var i = token.start; i < token.end; i++) {
        offsets[i] = buffer.length;
        if (!token.isMarker) buffer.write(source[i]);
      }
    }

    offsets[source.length] = buffer.length;
    return StrippedText(buffer.toString(), offsets);
  }

  /// Every character of [source], classified, in order and without gaps.
  ///
  /// The primitive the rest of this file is built on. [strip] keeps the text
  /// tokens and maps the markers onto their neighbours; an editor renders the
  /// text tokens styled and the markers dimmed. One scanner rather than one per
  /// consumer, because three traversals that each decide what a marker is would
  /// eventually disagree — and the disagreement would show up as a highlight in
  /// the wrong place or a caret out of step, neither of which looks like a
  /// parsing bug.
  ///
  /// Tokens tile the input exactly: the first starts at 0, each begins where
  /// the last ended, and the last ends at `source.length`. An editor depends on
  /// that, since spans whose lengths do not sum to the text length desynchronise
  /// the caret from what is drawn.
  static List<MarkupToken> tokenize(String source) {
    final tokens = <MarkupToken>[];

    var i = 0;
    var lineStart = true;
    var lineEnd = _lineEndFrom(source, 0);
    var block = MarkupBlockKind.paragraph;
    var bold = false;
    var italic = false;

    void emit(int length, {required bool isMarker}) {
      tokens.add(
        MarkupToken(
          start: i,
          end: i + length,
          isMarker: isMarker,
          bold: bold,
          italic: italic,
          block: block,
        ),
      );
      i += length;
    }

    while (i < source.length) {
      if (lineStart) {
        lineStart = false;
        final line = source.substring(i, lineEnd);
        block = _blockKindOf(line);

        final prefix = _prefixLength(line);
        if (prefix > 0) {
          emit(prefix, isMarker: true);
          continue;
        }
      }

      final char = source[i];

      if (char == '\n') {
        // Emphasis and block kind both reset: a marker cannot pair across a
        // line break, which is the rule [parse] follows by working line by
        // line.
        bold = false;
        italic = false;
        block = MarkupBlockKind.paragraph;
        emit(1, isMarker: false);
        lineStart = true;
        lineEnd = _lineEndFrom(source, i);
        continue;
      }

      if (i + 1 < lineEnd && source.startsWith('**', i)) {
        final partner = source.indexOf('**', i + 2);
        if (bold || (partner != -1 && partner < lineEnd)) {
          bold = !bold;
          // Emitted *after* the flip so the closing marker carries the same
          // styling as the run it closes, which is what makes it read as part
          // of that run rather than of the text after it.
          tokens.add(
            MarkupToken(
              start: i,
              end: i + 2,
              isMarker: true,
              bold: !bold,
              italic: italic,
              block: block,
            ),
          );
          i += 2;
          continue;
        }
        // Not a marker, so both characters are literal — kept together so the
        // second cannot then be read as an italic opener.
        emit(2, isMarker: false);
        continue;
      }

      if (char == '*' || char == '_') {
        final partner = source.indexOf(char, i + 1);
        if (italic || (partner != -1 && partner < lineEnd)) {
          italic = !italic;
          tokens.add(
            MarkupToken(
              start: i,
              end: i + 1,
              isMarker: true,
              bold: bold,
              italic: !italic,
              block: block,
            ),
          );
          i += 1;
          continue;
        }
      }

      emit(1, isMarker: false);
    }

    return _merged(tokens);
  }

  /// Joins neighbouring runs that are classified the same.
  ///
  /// The scanner works a character at a time, so without this a paragraph
  /// becomes one token per letter — and an editor one `TextSpan` per letter,
  /// which is a great deal of work for a page of text and makes the tokens
  /// awkward to reason about. Merging preserves the tiling, since two adjacent
  /// ranges become one range covering both.
  static List<MarkupToken> _merged(List<MarkupToken> tokens) {
    final merged = <MarkupToken>[];

    for (final token in tokens) {
      final previous = merged.isEmpty ? null : merged.last;

      if (previous != null &&
          previous.end == token.start &&
          previous.isMarker == token.isMarker &&
          previous.bold == token.bold &&
          previous.italic == token.italic &&
          previous.block == token.block) {
        merged[merged.length - 1] = MarkupToken(
          start: previous.start,
          end: token.end,
          isMarker: token.isMarker,
          bold: token.bold,
          italic: token.italic,
          block: token.block,
        );
        continue;
      }

      merged.add(token);
    }

    return List<MarkupToken>.unmodifiable(merged);
  }

  /// Which block a line is, without parsing its contents.
  static MarkupBlockKind _blockKindOf(String line) {
    if (_image.hasMatch(line)) return MarkupBlockKind.image;

    final heading = _heading.firstMatch(line);
    if (heading != null) {
      return switch (heading.group(1)!.length) {
        1 => MarkupBlockKind.heading1,
        2 => MarkupBlockKind.heading2,
        _ => MarkupBlockKind.heading3,
      };
    }
    if (_numbered.hasMatch(line)) return MarkupBlockKind.numbered;
    if (_bullet.hasMatch(line)) return MarkupBlockKind.bullet;
    if (_quote.hasMatch(line)) return MarkupBlockKind.quote;
    return MarkupBlockKind.paragraph;
  }

  static int _lineEndFrom(String source, int index) {
    final newline = source.indexOf('\n', index);
    return newline < 0 ? source.length : newline;
  }

  /// How many characters at the start of [line] are a block marker.
  ///
  /// Mirrors the patterns [parse] classifies on, in the same order, so the two
  /// cannot disagree about what counts as a marker.
  static int _prefixLength(String line) {
    // An image line is a marker from end to end. There is no content after the
    // prefix because the line *is* the reference, and treating it this way is
    // what makes every text consumer drop it without knowing images exist:
    // `strip` removes markers, and the offset map it returns already accounts
    // for their removal.
    if (_image.hasMatch(line)) return line.length;

    for (final pattern in _prefixes) {
      final match = pattern.firstMatch(line);
      if (match != null) return match.end;
    }
    return 0;
  }

  static final List<RegExp> _prefixes = <RegExp>[
    RegExp(r'^#{1,3}\s+'),
    RegExp(r'^\s*\d{1,3}[.)]\s+'),
    RegExp(r'^\s*[-*•]\s+'),
    RegExp(r'^\s*>\s?'),
  ];

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
  static String toInlineText(String text) =>
      strip(text).text.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// [text] with every picture reference taken out, line and all.
  ///
  /// The one function that keeps images away from search and from the
  /// assistant. Both index words, and the name of a JPEG is not a word anybody
  /// meant to write — left in, `9c2e1f4a.jpg` would be three searchable tokens
  /// and a passage the assistant could quote.
  ///
  /// The line goes with the reference, rather than being blanked, so a document
  /// does not gain an empty paragraph everywhere a picture was.
  ///
  /// **For text containing no pictures this returns its input unchanged**, which
  /// is what makes it safe to put in front of the existing index: every
  /// document written before this feature produces the same string, therefore
  /// the same tokens, therefore the same results.
  static String withoutImages(String text) {
    if (!text.contains('](')) return text;

    final kept = <String>[
      for (final line in text.split('\n'))
        if (!_image.hasMatch(line)) line,
    ];

    return kept.join('\n');
  }

  /// Whether [text] holds at least one picture.
  static bool hasImages(String text) => imageNames(text).isNotEmpty;

  /// Whether one line is a picture reference and nothing else.
  static bool isImageLine(String line) => _image.hasMatch(line);

  /// Whether one line is a heading.
  ///
  /// Exposed for the same reason [isImageLine] is: a consumer scanning raw page
  /// text a line at a time needs to know what kind of line it is on, and the
  /// alternative — re-deriving the rule from the `#` character — would be a
  /// second definition of a heading to keep in step with this one.
  static bool isHeadingLine(String line) => _heading.hasMatch(line);

  /// The file a picture line names, or null if it is not one.
  static String? imageNameIn(String line) =>
      _image.firstMatch(line)?.group(2)?.trim();

  /// Every picture [text] refers to, in the order it refers to them.
  ///
  /// Duplicates are kept: the same file placed twice is two references, and the
  /// sweep that deletes unreferenced files has to see that removing one of them
  /// leaves the other.
  static List<String> imageNames(String text) => <String>[
    for (final block in parse(text))
      if (block.kind == MarkupBlockKind.image && block.imageName != null)
        block.imageName!,
  ];

  /// A picture on a line of its own: `![Image](9c2e1f4a.jpg)`.
  ///
  /// Markdown's own syntax, because the format is already a Markdown subset and
  /// a reader who has met one has met the other. The label in the brackets is
  /// what the editor shows; the name in the parentheses is the file.
  ///
  /// Anchored to the whole line on purpose. A reference in the middle of a
  /// sentence would have to flow inside a paragraph, and this format is
  /// line-based — one line is one block — so a picture is a line.
  static final RegExp _image = RegExp(r'^\s*!\[([^\]]*)\]\(([^)\s]+)\)\s*$');

  static final RegExp _heading = RegExp(r'^(#{1,3})\s+(.*)$');
  static final RegExp _bullet = RegExp(r'^\s*[-*•]\s+(.*)$');
  static final RegExp _numbered = RegExp(r'^\s*(\d{1,3})[.)]\s+(.*)$');
  static final RegExp _quote = RegExp(r'^\s*>\s?(.*)$');

  static MarkupBlock _parseLine(String line) {
    final image = _image.firstMatch(line);
    if (image != null) {
      return MarkupBlock(
        kind: MarkupBlockKind.image,
        spans: const <MarkupSpan>[],
        imageName: image.group(2)!.trim(),
      );
    }

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
