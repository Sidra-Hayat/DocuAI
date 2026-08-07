import 'package:flutter/material.dart';

/// One paragraph of recognised text, with any search matches emphasised.
///
/// Split out of the reader so the highlight arithmetic is testable on its own
/// and so the list item stays cheap to rebuild while a query is being typed.
class ReaderParagraph extends StatelessWidget {
  const ReaderParagraph({
    required this.text,
    required this.query,
    required this.scale,
    super.key,
  });

  final String text;

  /// Empty when nothing is being searched for.
  final String query;

  /// Reader font scale, applied on top of whatever the system asked for.
  final double scale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final base = theme.textTheme.bodyLarge!.copyWith(
      fontSize: (theme.textTheme.bodyLarge?.fontSize ?? 16) * scale,
      // Generous leading: recognised text has no typographic structure of its
      // own, so line spacing is what stops a page of it reading as a wall.
      height: 1.62,
    );

    if (query.isEmpty) {
      return Text(text, style: base);
    }

    return Text.rich(
      TextSpan(children: _spans(text, query, theme, base)),
      style: base,
    );
  }

  /// Splits [text] on every case-insensitive occurrence of [query].
  ///
  /// Offsets come from a lower-cased copy but every slice is taken from the
  /// original, so the text rendered is exactly the text recognised — matching
  /// must never alter what the user sees.
  static List<TextSpan> _spans(
    String text,
    String query,
    ThemeData theme,
    TextStyle base,
  ) {
    final spans = <TextSpan>[];
    final haystack = text.toLowerCase();
    final needle = query.toLowerCase();

    final highlight = base.copyWith(
      backgroundColor: theme.colorScheme.primaryContainer,
      color: theme.colorScheme.onPrimaryContainer,
      fontWeight: FontWeight.w600,
    );

    var start = 0;
    var index = haystack.indexOf(needle);

    while (index >= 0) {
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + needle.length),
          style: highlight,
        ),
      );
      start = index + needle.length;
      index = haystack.indexOf(needle, start);
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return spans;
  }
}
