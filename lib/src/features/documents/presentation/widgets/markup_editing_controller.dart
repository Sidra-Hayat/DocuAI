import 'package:flutter/material.dart';

import '../../../../core/text/markup.dart';
import '../../../../core/text/markup_editing.dart';

/// A formatting the toolbar can switch on or off.
///
/// Named for the button rather than for the syntax: the toolbar's whole purpose
/// is that nobody has to know the text says `**` or `> `.
enum MarkupFormat { bold, italic, heading, bullet, numbered, quote }

/// A text controller that styles markup as it is typed.
///
/// The markers stay on screen — this is not WYSIWYG, and pretending otherwise
/// would be worse than showing them, because the text being edited *is* the
/// text that gets stored. What changes is that they stop shouting: a bold run
/// renders bold, a heading renders large, and the `**` and `#` around them fade
/// into the background instead of competing with the words.
///
/// The invariant everything here rests on: the spans returned by
/// [buildTextSpan] must cover exactly `text.length` characters. Flutter maps
/// caret and selection positions through that span tree, so a single character
/// unaccounted for puts the cursor somewhere other than where it appears.
/// `Markup.tokenize` tiles its input without gaps, which is what makes that
/// hold by construction rather than by care.
class MarkupEditingController extends TextEditingController {
  MarkupEditingController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final theme = Theme.of(context);
    final markerColour = theme.colorScheme.onSurfaceVariant.withValues(
      alpha: .45,
    );

    final tokens = Markup.tokenize(text);
    if (tokens.isEmpty) return TextSpan(text: text, style: base);

    return TextSpan(
      style: base,
      children: <InlineSpan>[
        for (final token in tokens)
          TextSpan(
            text: text.substring(token.start, token.end),
            // A picture's line is a marker from end to end, so it would
            // otherwise render as dimmed syntax. It is the one marker meant to
            // be *seen*: it stands in for something the user put there.
            style: token.isMarker && token.block != MarkupBlockKind.image
                ? base.copyWith(color: markerColour)
                : _styleFor(token, base, theme),
          ),
      ],
    );
  }

  static TextStyle _styleFor(
    MarkupToken token,
    TextStyle base,
    ThemeData theme,
  ) {
    final size = base.fontSize ?? 16;

    final block = switch (token.block) {
      MarkupBlockKind.heading1 => base.copyWith(
        fontSize: size * 1.5,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      MarkupBlockKind.heading2 => base.copyWith(
        fontSize: size * 1.28,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      MarkupBlockKind.heading3 => base.copyWith(
        fontSize: size * 1.12,
        fontWeight: FontWeight.w600,
      ),
      MarkupBlockKind.quote => base.copyWith(
        fontStyle: FontStyle.italic,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      // A picture cannot be drawn inside a text field — a widget span occupies
      // exactly one character and the reference is many, which would put the
      // caret somewhere other than where it appears. So the line is styled to
      // read as an object instead of as text: tinted, compact, and set apart
      // from the writing around it.
      MarkupBlockKind.image => base.copyWith(
        fontSize: size * 0.92,
        color: theme.colorScheme.onPrimaryContainer,
        backgroundColor: theme.colorScheme.primaryContainer,
        fontWeight: FontWeight.w600,
      ),
      MarkupBlockKind.bullet ||
      MarkupBlockKind.numbered ||
      MarkupBlockKind.paragraph => base,
    };

    return block.copyWith(
      // Emphasis composes with the block: a bold word inside a heading stays
      // heading-sized.
      fontWeight: token.bold ? FontWeight.w700 : block.fontWeight,
      fontStyle: token.italic ? FontStyle.italic : block.fontStyle,
    );
  }

  /// The formats in force where the caret is.
  ///
  /// Read from the same tokeniser that draws the field, so the lit buttons and
  /// the styled text can never disagree — a toolbar that says "bold" while the
  /// word under the caret is plain is worse than a toolbar with no state at
  /// all, because it is confidently wrong.
  Set<MarkupFormat> get activeFormats {
    if (text.isEmpty) return const <MarkupFormat>{};

    final offset = selection.isValid
        ? selection.start.clamp(0, text.length)
        : text.length;

    final tokens = Markup.tokenize(text);
    if (tokens.isEmpty) return const <MarkupFormat>{};

    // A caret sitting exactly on a boundary belongs to both neighbours. The
    // content run wins over the marker, because the marker is the thing the
    // user is not supposed to be thinking about.
    MarkupToken? best;
    for (final token in tokens) {
      if (offset < token.start || offset > token.end) continue;
      if (best == null || (best.isMarker && !token.isMarker)) best = token;
    }
    if (best == null) return const <MarkupFormat>{};

    return <MarkupFormat>{
      if (best.bold) MarkupFormat.bold,
      if (best.italic) MarkupFormat.italic,
      if (best.block == MarkupBlockKind.heading1 ||
          best.block == MarkupBlockKind.heading2 ||
          best.block == MarkupBlockKind.heading3)
        MarkupFormat.heading,
      if (best.block == MarkupBlockKind.bullet) MarkupFormat.bullet,
      if (best.block == MarkupBlockKind.numbered) MarkupFormat.numbered,
      if (best.block == MarkupBlockKind.quote) MarkupFormat.quote,
    };
  }

  /// The picture the caret is sitting on, or null if it is not on one.
  ///
  /// How the editor knows to offer Preview and Remove. A tap inside a text
  /// field places the caret — it does not reach a gesture recogniser on a span,
  /// which is why the actions appear beside the field rather than on the line
  /// itself.
  String? get imageAtCaret {
    if (!selection.isValid || text.isEmpty) return null;

    final at = selection.start.clamp(0, text.length);
    final start = at == 0 ? 0 : text.lastIndexOf('\n', at - 1) + 1;
    final newline = text.indexOf('\n', at);
    final end = newline < 0 ? text.length : newline;

    if (start > end) return null;
    return Markup.imageNameIn(text.substring(start, end));
  }

  /// Applies a toolbar operation, keeping the selection on the text it was on.
  ///
  /// The controller owns this rather than the toolbar so that the value and the
  /// selection move together in one assignment — setting `text` on its own
  /// resets the selection to the end, which would throw the caret to the bottom
  /// of the document on every button press.
  void apply(TextEdit Function(TextEdit edit) operation) {
    final current = TextEdit(
      text: text,
      start: selection.start < 0 ? text.length : selection.start,
      end: selection.end < 0 ? text.length : selection.end,
    );

    final next = operation(current);

    value = TextEditingValue(
      text: next.text,
      selection: TextSelection(
        baseOffset: next.start.clamp(0, next.text.length),
        extentOffset: next.end.clamp(0, next.text.length),
      ),
    );
  }
}
