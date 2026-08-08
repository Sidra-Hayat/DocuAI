import '../../../../core/text/markup.dart';
import '../../../documents/domain/entities/document.dart';

/// A candidate answer: one span of text, and exactly where it came from.
class Passage {
  const Passage({
    required this.documentId,
    required this.documentTitle,
    required this.pageIndex,
    required this.text,
    required this.start,
    required this.end,
    required this.pageText,
  });

  final String documentId;
  final String documentTitle;
  final int pageIndex;

  /// The passage itself, as it appears in [pageText].
  final String text;

  /// Character range within [pageText]. Kept so overlapping candidates can be
  /// collapsed, and so a citation can be widened to surrounding context
  /// without searching for the passage again.
  final int start;
  final int end;

  /// The full page this came from.
  final String pageText;
}

/// Splits recognised page text into candidate passages.
///
/// Sentences are the unit. They are the smallest span that usually states
/// something complete, which is what an extractive answer needs — a fixed-size
/// window would cut mid-clause and quote half a sentence back at the user.
abstract final class PassageExtractor {
  /// Anything shorter is a fragment — a page number, a stray heading — and
  /// cannot answer a question on its own.
  static const int minPassageChars = 12;

  /// Hard ceiling for a single candidate. OCR output from a dense page can run
  /// for hundreds of characters without a full stop, and one passage spanning a
  /// whole page tells the reader nothing about where the answer is.
  static const int maxPassageChars = 220;

  /// Width of the context a citation is expanded to.
  static const int citationChars = 240;

  /// Boundaries: sentence-ending punctuation followed by space, or a line
  /// break. Line breaks matter more than punctuation here — recognised text
  /// from a form or a table often has no punctuation at all, but always has
  /// lines.
  ///
  /// A colon is deliberately **not** a boundary. On the documents this app
  /// scans a colon binds a label to its value — `Total amount due: £248.60` —
  /// and splitting there leaves the half carrying the words a question matches
  /// on ("total", "amount") with no figure in it, and the half carrying the
  /// figure too short to survive [minPassageChars]. The intent boost then
  /// cannot fire on the one passage that actually answers the question.
  static final RegExp _boundary = RegExp(r'(?<=[.!?;])\s+|\n+');

  static List<Passage> extract(Document document) {
    final passages = <Passage>[];

    for (final page in document.pages) {
      if (!page.hasText) continue;

      for (final range in _ranges(page.text)) {
        final text = page.text.substring(range.$1, range.$2).trim();
        if (text.length < minPassageChars) continue;

        passages.add(
          Passage(
            documentId: document.id,
            documentTitle: document.title,
            pageIndex: page.index,
            text: text,
            start: range.$1,
            end: range.$2,
            pageText: page.text,
          ),
        );
      }
    }

    return List<Passage>.unmodifiable(passages);
  }

  /// Sentence ranges, with anything over [maxPassageChars] split further.
  static List<(int, int)> _ranges(String text) {
    final ranges = <(int, int)>[];

    var start = 0;
    for (final match in _boundary.allMatches(text)) {
      if (match.start > start) ranges.addAll(_split(text, start, match.start));
      start = match.end;
    }
    if (start < text.length) ranges.addAll(_split(text, start, text.length));

    return ranges;
  }

  /// Breaks an over-long span at whitespace, falling back to a hard cut when a
  /// run of characters has no space in it at all.
  static List<(int, int)> _split(String text, int start, int end) {
    if (end - start <= maxPassageChars) return <(int, int)>[(start, end)];

    final parts = <(int, int)>[];
    var cursor = start;

    while (end - cursor > maxPassageChars) {
      final limit = cursor + maxPassageChars;
      var cut = text.lastIndexOf(' ', limit);
      if (cut <= cursor) cut = limit;
      parts.add((cursor, cut));
      cursor = cut;
    }
    if (cursor < end) parts.add((cursor, end));

    return parts;
  }

  /// Widens a passage to about [citationChars] of surrounding page text, so a
  /// citation reads as a quotation rather than a clipping.
  ///
  /// Whitespace collapsing and marker stripping both happen at the very end, on
  /// a string nobody indexes into — unlike search snippets, a citation carries
  /// no highlight offsets, so there is no range to keep in step. The window is
  /// cut from the *original* text using the passage's own offsets first, which
  /// is what keeps the citation pointing at the page it actually came from.
  static String citationSnippet(Passage passage) {
    final padding = ((citationChars - passage.text.length) / 2)
        .clamp(0, citationChars)
        .round();

    final start = (passage.start - padding).clamp(0, passage.pageText.length);
    final end = (passage.end + padding).clamp(0, passage.pageText.length);

    final excerpt = Markup.toInlineText(
      passage.pageText.substring(start, end),
    );

    final prefix = start > 0 ? '…' : '';
    final suffix = end < passage.pageText.length ? '…' : '';

    return '$prefix$excerpt$suffix';
  }
}
