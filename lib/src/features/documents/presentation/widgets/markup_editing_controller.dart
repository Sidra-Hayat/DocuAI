import 'package:flutter/material.dart';

import '../../../../core/text/markup.dart';
import '../../../../core/text/markup_editing.dart';
import '../../../../core/theme/app_typography.dart';

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
      // Sizes come from [AppTypography] rather than from multipliers chosen
      // here, so a heading is the same size in the editor as it is in the
      // reader. Scaled relative to the base rather than used raw, so a system
      // text-size setting still moves the whole document together.
      MarkupBlockKind.heading1 => base.copyWith(
        fontSize: _scaled(AppTypography.heading1, size),
        fontWeight: FontWeight.w700,
        height: AppTypography.headingHeight,
      ),
      MarkupBlockKind.heading2 => base.copyWith(
        fontSize: _scaled(AppTypography.heading2, size),
        fontWeight: FontWeight.w700,
        height: AppTypography.headingHeight,
      ),
      MarkupBlockKind.heading3 => base.copyWith(
        fontSize: _scaled(AppTypography.heading3, size),
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
        // Teal, not indigo. Indigo is what the app uses for things you press,
        // and a placeholder tinted like a button invites a tap that a text
        // field cannot deliver — the actions for it are the bar above the
        // toolbar. Teal says "this is a thing in your document" instead.
        color: theme.colorScheme.onSecondaryContainer,
        backgroundColor: theme.colorScheme.secondaryContainer,
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

  /// [target] — an absolute size from [AppTypography] — expressed against
  /// whatever size the field is actually set in.
  ///
  /// The scale is a ratio rather than the number itself because [base] carries
  /// the reader's text-size preference and the system font scale. Using 24
  /// directly would give a heading that ignores both, on a screen where the
  /// body text around it does not.
  static double _scaled(double target, double base) =>
      target / AppTypography.body * base;

  /// What kind of line the caret is on.
  ///
  /// Drives the paragraph-style picker, which needs to know *which* heading
  /// rather than merely that there is one — [activeFormats] answers "is this a
  /// heading" and cannot tell Heading 1 from Heading 2.
  MarkupBlockKind get activeBlockKind {
    if (text.isEmpty) return MarkupBlockKind.paragraph;

    final caret = selection.baseOffset < 0
        ? text.length
        : selection.baseOffset.clamp(0, text.length);

    for (final token in Markup.tokenize(text)) {
      if (caret >= token.start && caret <= token.end) return token.block;
    }
    return MarkupBlockKind.paragraph;
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
