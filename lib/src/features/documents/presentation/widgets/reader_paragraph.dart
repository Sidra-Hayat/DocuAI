import 'package:flutter/material.dart';

import '../../../../core/text/markup.dart';
import 'markup_view.dart';

/// One line of a document, rendered as what it is.
///
/// It used to hand its text straight to a `Text`, which is why a page saved
/// with a heading was read back as `## Deposit` and a bold total as
/// `**248.60**`. It now parses the line and delegates to [MarkupBlockView] —
/// the same renderer the page viewer and the document preview use, and the
/// Flutter counterpart of what the PDF composer has always done.
///
/// The name and the API are kept because the reader is built around them, and
/// because "a paragraph of the document, with matches emphasised" is still
/// exactly what this is.
class ReaderParagraph extends StatelessWidget {
  const ReaderParagraph({
    required this.text,
    required this.query,
    required this.scale,
    this.documentId = '',
    super.key,
  });

  /// One line of the page, in its stored form — markers and all.
  final String text;

  /// Empty when nothing is being searched for.
  final String query;

  /// Reader font scale, applied on top of whatever the system asked for.
  final double scale;

  /// Only needed for a line that turns out to be a picture; the reader draws
  /// those itself, so in practice this is never reached with one.
  final String documentId;

  @override
  Widget build(BuildContext context) {
    final blocks = Markup.parse(text);

    // A line that is entirely whitespace parses to nothing. Rendering an empty
    // box for it keeps the caller from having to check first.
    if (blocks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final block in blocks)
          MarkupBlockView(
            block: block,
            documentId: documentId,
            query: query,
            scale: scale,
          ),
      ],
    );
  }
}
