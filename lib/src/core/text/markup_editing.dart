/// A text field's contents and where the selection sits in it.
///
/// Plain integers rather than Flutter's `TextSelection`, so every toolbar
/// operation is an ordinary function over a string and can be tested without
/// pumping a widget.
class TextEdit {
  const TextEdit({required this.text, required this.start, required this.end});

  final String text;

  /// Selection bounds, `start == end` for a caret.
  final int start;
  final int end;

  bool get isCollapsed => start == end;

  String get selected => text.substring(start, end);
}

/// What the toolbar does to the text.
///
/// Every operation is a *toggle*, because a button that only ever adds is a
/// button you cannot undo without knowing the syntax — which is the thing the
/// toolbar exists to spare people.
///
/// Two families, and they behave differently on purpose:
///
///  * **Inline** — bold and italic wrap the selection, or unwrap it when it is
///    already wrapped. With no selection they insert an empty pair and put the
///    caret inside, so typing continues in that style.
///  * **Line** — headings, lists and quotes are properties of a whole line, so
///    they apply to every line the selection touches. Applying one removes any
///    other: a line cannot be both a heading and a bullet, and silently
///    producing `# - item` would write markup no reader of this format
///    recognises.
abstract final class MarkupEditing {
  static const String boldMarker = '**';
  static const String italicMarker = '*';

  static TextEdit toggleBold(TextEdit edit) => _toggleInline(edit, boldMarker);

  static TextEdit toggleItalic(TextEdit edit) =>
      _toggleInline(edit, italicMarker);

  static TextEdit toggleHeading(TextEdit edit, {int level = 2}) =>
      _toggleLinePrefix(
        edit,
        prefixFor: (_) => '${'#' * level.clamp(1, 3)} ',
        already: _headingPrefix,
      );

  static TextEdit toggleBullet(TextEdit edit) =>
      _toggleLinePrefix(edit, prefixFor: (_) => '- ', already: _bulletPrefix);

  /// Numbered items count from one within the block being toggled.
  ///
  /// The alternative — every line getting `1.` — reads as a mistake, and
  /// renumbering here means the exported list matches what the editor showed.
  static TextEdit toggleNumbered(TextEdit edit) => _toggleLinePrefix(
    edit,
    prefixFor: (index) => '${index + 1}. ',
    already: _numberedPrefix,
  );

  static TextEdit toggleQuote(TextEdit edit) =>
      _toggleLinePrefix(edit, prefixFor: (_) => '> ', already: _quotePrefix);

  // ---- inline ---------------------------------------------------------------

  static TextEdit _toggleInline(TextEdit edit, String marker) {
    final length = marker.length;

    // Already wrapped, with the markers just outside the selection. Removing
    // them is what makes the button a toggle rather than a one-way door.
    final outerStart = edit.start - length;
    if (outerStart >= 0 &&
        edit.end + length <= edit.text.length &&
        _isMarkerAt(edit.text, outerStart, marker) &&
        _isMarkerAt(edit.text, edit.end, marker)) {
      final text =
          edit.text.substring(0, outerStart) +
          edit.selected +
          edit.text.substring(edit.end + length);
      return TextEdit(
        text: text,
        start: outerStart,
        end: outerStart + edit.selected.length,
      );
    }

    // Already wrapped, with the markers inside the selection — what you get by
    // selecting a whole bold word including its asterisks.
    final selected = edit.selected;
    if (selected.length >= length * 2 &&
        selected.startsWith(marker) &&
        selected.endsWith(marker)) {
      final inner = selected.substring(length, selected.length - length);
      final text =
          edit.text.substring(0, edit.start) +
          inner +
          edit.text.substring(edit.end);
      return TextEdit(
        text: text,
        start: edit.start,
        end: edit.start + inner.length,
      );
    }

    final text =
        edit.text.substring(0, edit.start) +
        marker +
        selected +
        marker +
        edit.text.substring(edit.end);

    // With nothing selected the caret lands between the markers, so whatever is
    // typed next is inside them.
    return edit.isCollapsed
        ? TextEdit(
            text: text,
            start: edit.start + length,
            end: edit.start + length,
          )
        : TextEdit(
            text: text,
            start: edit.start + length,
            end: edit.start + length + selected.length,
          );
  }

  /// True when [text] carries [marker] at [at], and it is not part of a longer
  /// run that means something else — `*` inside `**` is bold, not italic.
  static bool _isMarkerAt(String text, int at, String marker) {
    if (at < 0 || at + marker.length > text.length) return false;
    if (!text.startsWith(marker, at)) return false;

    if (marker == italicMarker) {
      final before = at > 0 ? text[at - 1] : '';
      final after = at + 1 < text.length ? text[at + 1] : '';
      if (before == '*' || after == '*') return false;
    }
    return true;
  }

  // ---- line -----------------------------------------------------------------

  static TextEdit _toggleLinePrefix(
    TextEdit edit, {
    required String Function(int index) prefixFor,
    required RegExp already,
  }) {
    final lineStart = _startOfLine(edit.text, edit.start);
    final lineEnd = _endOfLine(edit.text, edit.end);

    final block = edit.text.substring(lineStart, lineEnd);
    final lines = block.split('\n');

    // Recognised by pattern, not by the literal prefix. A numbered list is
    // `1.` then `2.` then `3.`, so comparing every line against the string the
    // first one would get means only the first is ever seen as already
    // numbered — and pressing the button on a finished list renumbers it
    // instead of clearing it.
    //
    // Toggling off only when *every* touched line already has it: a mixed
    // selection means the user is asking for the style, not to lose it.
    final removing = lines.every(already.hasMatch);

    final rewritten = <String>[];
    for (var i = 0; i < lines.length; i++) {
      final bare = _withoutAnyPrefix(lines[i]);
      rewritten.add(removing ? bare : '${prefixFor(i)}$bare');
    }

    final replacement = rewritten.join('\n');
    final text =
        edit.text.substring(0, lineStart) +
        replacement +
        edit.text.substring(lineEnd);

    // The selection follows the text it was on rather than the offsets it had,
    // which have all moved by the prefixes added or removed before them.
    final delta = replacement.length - block.length;
    final firstDelta = rewritten.first.length - lines.first.length;

    return TextEdit(
      text: text,
      start: (edit.start + firstDelta).clamp(lineStart, text.length),
      end: (edit.end + delta).clamp(lineStart, text.length),
    );
  }

  /// Strips whichever block marker a line already carries.
  ///
  /// One line has one kind, so applying a new one replaces the old rather than
  /// stacking on it.
  static String _withoutAnyPrefix(String line) {
    for (final pattern in _blockPrefixes) {
      final match = pattern.firstMatch(line);
      if (match != null) return line.substring(match.end);
    }
    return line;
  }

  static final RegExp _headingPrefix = RegExp(r'^#{1,3}\s+');
  static final RegExp _numberedPrefix = RegExp(r'^\s*\d{1,3}[.)]\s+');
  static final RegExp _bulletPrefix = RegExp(r'^\s*[-*•]\s+');
  static final RegExp _quotePrefix = RegExp(r'^\s*>\s?');

  static final List<RegExp> _blockPrefixes = <RegExp>[
    _headingPrefix,
    _numberedPrefix,
    _bulletPrefix,
    _quotePrefix,
  ];

  static int _startOfLine(String text, int index) {
    final at = index.clamp(0, text.length);

    // The caret at position 0 is already at the start of the first line.
    // Searching backwards from there would find a newline *at* index 0 — which
    // `lastIndexOf` includes — and report the line as starting at 1, past the
    // end of a line that has not begun. `substring(1, 0)` then throws.
    if (at == 0) return 0;

    final newline = text.lastIndexOf('\n', at - 1);
    return newline < 0 ? 0 : newline + 1;
  }

  static int _endOfLine(String text, int index) {
    final newline = text.indexOf('\n', index.clamp(0, text.length));
    return newline < 0 ? text.length : newline;
  }
}
