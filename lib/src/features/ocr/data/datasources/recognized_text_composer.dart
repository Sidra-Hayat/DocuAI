import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Rebuilds readable text from ML Kit's recognition hierarchy.
///
/// `RecognizedText.text` is Android's `Text.getText()`, which concatenates
/// **block** texts with newlines. That reads acceptably for a page of prose,
/// where a block is a paragraph — but on the documents this app exists for it
/// falls apart. ML Kit segments a bill or a form by visual grouping, so a
/// heading word, a field label and its value each become their own block, and
/// the flat string comes back as:
///
/// ```
/// Electricity
/// Bill
/// Amount
/// 5000
/// ```
///
/// The information needed to do better was already there and being thrown away:
/// every block, line and element carries a bounding box. This walks
/// block → line → element and reassembles the page geometrically:
///
/// ```
/// Electricity Bill
/// Amount: 5000
/// ```
///
/// Two things this deliberately does **not** do:
///
///  * It never invents characters. Fragments on one row are joined with a
///    single space and nothing else — no inserted colons or dashes to make a
///    label look like a label. The assistant quotes recognised text verbatim,
///    so a fabricated separator would end up inside an answer presented as a
///    quotation from the user's own document.
///  * It assumes left-to-right reading order, which holds for
///    [TextRecognitionScript.latin] — the only script this app configures.
abstract final class RecognizedTextComposer {
  /// How much of the shorter fragment's height must overlap for two fragments
  /// to count as sharing a visual row.
  ///
  /// Generous on purpose. Side-by-side text on one baseline overlaps almost
  /// completely, while a heading and the line beneath it barely overlap at all,
  /// so the gap between the two cases is wide and the exact value is not
  /// delicate. Too high and a slightly raised value breaks away from its label;
  /// too low and consecutive lines collapse into each other.
  static const double rowOverlapThreshold = 0.4;

  /// A vertical gap larger than this many times the median row height is read
  /// as a section break and becomes a blank line.
  static const double paragraphGapFactor = 1.4;

  static String compose(RecognizedText recognized) {
    final fragments = _fragments(recognized);

    // No geometry to work with — an empty result, or a shape this code does
    // not recognise. Falling back to ML Kit's own string is worse output but
    // never *no* output.
    if (fragments.isEmpty) return recognized.text.trim();

    final rows = _groupIntoRows(fragments);
    return _join(rows);
  }

  /// One fragment per text line, with its text rebuilt from the elements
  /// beneath it.
  static List<_Fragment> _fragments(RecognizedText recognized) {
    final fragments = <_Fragment>[];

    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final text = _lineText(line);
        if (text.isEmpty) continue;
        fragments.add(_Fragment(text: text, box: line.boundingBox));
      }
    }

    return fragments;
  }

  /// Rebuilds a line from its elements, in reading order.
  ///
  /// `TextLine.text` is usually identical, but going through the elements is
  /// what makes the hierarchy authoritative: a line whose elements ML Kit
  /// ordered by position rather than by its own concatenation comes out right.
  /// A line with no elements — which is what iOS returns — falls back to the
  /// line's own text rather than vanishing.
  static String _lineText(TextLine line) {
    if (line.elements.isEmpty) return _collapse(line.text);

    final elements = List<TextElement>.of(line.elements)
      ..sort((a, b) => a.boundingBox.left.compareTo(b.boundingBox.left));

    return _collapse(elements.map((element) => element.text).join(' '));
  }

  /// Groups fragments that sit on the same visual row.
  static List<_Row> _groupIntoRows(List<_Fragment> fragments) {
    final ordered = List<_Fragment>.of(fragments)
      ..sort((a, b) {
        final byTop = a.box.top.compareTo(b.box.top);
        return byTop != 0 ? byTop : a.box.left.compareTo(b.box.left);
      });

    final rows = <_Row>[];

    for (final fragment in ordered) {
      final current = rows.isEmpty ? null : rows.last;

      if (current != null &&
          _verticalOverlap(current.box, fragment.box) >= rowOverlapThreshold) {
        current.add(fragment);
      } else {
        rows.add(_Row(fragment));
      }
    }

    return rows;
  }

  /// Overlap of two boxes vertically, as a fraction of the shorter one.
  ///
  /// Measured against the shorter box so that a row which has grown tall — a
  /// heading beside small print, say — does not start absorbing every line
  /// below it.
  static double _verticalOverlap(Rect a, Rect b) {
    final overlap = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
    if (overlap <= 0) return 0;

    final shorter = math.min(a.height, b.height);
    return shorter <= 0 ? 0 : overlap / shorter;
  }

  static String _join(List<_Row> rows) {
    final median = _medianHeight(rows);
    final buffer = StringBuffer();

    for (var i = 0; i < rows.length; i++) {
      buffer.write(rows[i].text);
      if (i == rows.length - 1) continue;

      final gap = rows[i + 1].box.top - rows[i].box.bottom;
      // A blank line marks a section break, which is what lets the assistant's
      // passage extractor treat a heading and the paragraph under it as
      // separate candidates.
      buffer.write(gap > median * paragraphGapFactor ? '\n\n' : '\n');
    }

    return buffer.toString().trim();
  }

  static double _medianHeight(List<_Row> rows) {
    final heights = rows.map((row) => row.box.height).toList()..sort();
    if (heights.isEmpty) return 1;

    final middle = heights[heights.length ~/ 2];
    // Guards the gap comparison against a degenerate box: without this a
    // zero-height row makes every gap look like a section break.
    return middle <= 0 ? 1 : middle;
  }

  static String _collapse(String text) =>
      text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

class _Fragment {
  const _Fragment({required this.text, required this.box});

  final String text;
  final Rect box;
}

/// Fragments sharing one visual row, kept in reading order.
class _Row {
  _Row(_Fragment first)
    : _fragments = <_Fragment>[first],
      box = first.box;

  final List<_Fragment> _fragments;

  /// Union of the fragments' boxes.
  Rect box;

  void add(_Fragment fragment) {
    _fragments.add(fragment);
    box = box.expandToInclude(fragment.box);
  }

  /// Joined left to right. A single space between fragments, never anything
  /// the page did not contain.
  String get text {
    final ordered = List<_Fragment>.of(_fragments)
      ..sort((a, b) => a.box.left.compareTo(b.box.left));

    return ordered.map((fragment) => fragment.text).join(' ');
  }
}
