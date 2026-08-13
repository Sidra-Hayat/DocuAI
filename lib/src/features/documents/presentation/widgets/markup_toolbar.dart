import 'package:flutter/material.dart';

import '../../../../core/text/markup.dart';
import '../../../../core/text/markup_editing.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import 'markup_editing_controller.dart';

/// Formatting buttons above the keyboard.
///
/// Every one is a toggle, so the syntax never has to be known — pressing bold
/// on bold text takes it off again. That is the whole justification for the
/// toolbar: the format is deliberately a plain string so that search, the
/// assistant and both exports can read it, and this is what stops that decision
/// costing the user anything.
///
/// The buttons light up for the formatting under the caret, which is what turns
/// them from a row of actions into a readout of the text. Without it, the only
/// way to know whether you are inside a heading is to recognise `##` — the
/// thing the toolbar exists so that nobody has to do.
///
/// Scrolls horizontally rather than wrapping. On a narrow phone a wrapping row
/// would take a second line away from the text, and the text is the point.
class MarkupToolbar extends StatelessWidget {
  const MarkupToolbar({
    required this.controller,
    this.onInsertImage,
    super.key,
  });

  final MarkupEditingController controller;

  /// Adds a picture at the caret. Absent where there is nowhere to put one —
  /// the button then does not appear at all, rather than appearing and
  /// refusing.
  final Future<void> Function()? onInsertImage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SafeArea(
        top: false,
        // Rebuilt on every value change, which includes the selection moving —
        // the caret crossing into a heading has to relight the buttons even
        // though the text did not change.
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final active = controller.activeFormats;

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: <Widget>[
                  _Button(
                    icon: Icons.format_bold,
                    tooltip: 'Bold',
                    active: active.contains(MarkupFormat.bold),
                    onPressed: () => controller.apply(MarkupEditing.toggleBold),
                  ),
                  _Button(
                    icon: Icons.format_italic,
                    tooltip: 'Italic',
                    active: active.contains(MarkupFormat.italic),
                    onPressed: () =>
                        controller.apply(MarkupEditing.toggleItalic),
                  ),
                  const _Divider(),
                  _StyleMenu(controller: controller),
                  _Button(
                    icon: Icons.format_list_bulleted,
                    tooltip: 'Bullet list',
                    active: active.contains(MarkupFormat.bullet),
                    onPressed: () =>
                        controller.apply(MarkupEditing.toggleBullet),
                  ),
                  _Button(
                    icon: Icons.format_list_numbered,
                    tooltip: 'Numbered list',
                    active: active.contains(MarkupFormat.numbered),
                    onPressed: () =>
                        controller.apply(MarkupEditing.toggleNumbered),
                  ),
                  _Button(
                    icon: Icons.format_quote,
                    tooltip: 'Quote',
                    active: active.contains(MarkupFormat.quote),
                    onPressed: () =>
                        controller.apply(MarkupEditing.toggleQuote),
                  ),
                  if (onInsertImage != null) ...<Widget>[
                    const _Divider(),
                    // Not a toggle like the six before it — it inserts
                    // something rather than restyling what is there. Given the
                    // accent colour so the difference is visible rather than
                    // only true.
                    _Button(
                      icon: Icons.add_photo_alternate_outlined,
                      tooltip: 'Add a picture',
                      active: false,
                      accent: true,
                      onPressed: () => onInsertImage!(),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Normal text, Heading 1 or Heading 2 — the one control here that is a choice
/// rather than a switch.
///
/// A line is exactly one of these, so a row of toggles would be the wrong
/// shape: it would let a user press Heading 1 and Heading 2 and leave them
/// wondering which won. A menu that says what the current line *is* also
/// answers the question a toggle cannot — whether this heading is the big one
/// or the small one.
///
/// Deliberately three entries. Heading 3 exists in the format so that an
/// imported document keeps its structure, but a third level is a nesting depth
/// nobody writing a note reaches for, and this is not a word processor.
class _StyleMenu extends StatelessWidget {
  const _StyleMenu({required this.controller});

  final MarkupEditingController controller;

  static const Map<MarkupBlockKind, String> _labels =
      <MarkupBlockKind, String>{
        MarkupBlockKind.heading1: 'Heading 1',
        MarkupBlockKind.heading2: 'Heading 2',
        MarkupBlockKind.heading3: 'Heading 3',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = controller.activeBlockKind;
    final heading = AppTypography.isHeading(kind);

    return PopupMenuButton<MarkupBlockKind>(
      tooltip: 'Text style',
      position: PopupMenuPosition.over,
      onSelected: (chosen) => controller.apply(
        (edit) => switch (chosen) {
          MarkupBlockKind.heading1 =>
            MarkupEditing.setHeading(edit, level: 1),
          MarkupBlockKind.heading2 =>
            MarkupEditing.setHeading(edit, level: 2),
          _ => MarkupEditing.setParagraph(edit),
        },
      ),
      itemBuilder: (context) => <PopupMenuEntry<MarkupBlockKind>>[
        _entry(context, MarkupBlockKind.paragraph, 'Normal text', kind),
        _entry(context, MarkupBlockKind.heading1, 'Heading 1', kind),
        _entry(context, MarkupBlockKind.heading2, 'Heading 2', kind),
      ],
      child: Container(
        constraints: const BoxConstraints(
          minHeight: AppAccessibility.minTouchTarget,
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              // The current style, named. A lone "T" icon says a style menu is
              // here but not which style you are in.
              heading ? _labels[kind]! : 'Normal',
              style: theme.textTheme.labelLarge?.copyWith(
                color: heading
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: heading ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<MarkupBlockKind> _entry(
    BuildContext context,
    MarkupBlockKind value,
    String label,
    MarkupBlockKind current,
  ) {
    final theme = Theme.of(context);
    // Heading 3 is not offered, but a line that already is one should still
    // show as something rather than as "Normal".
    final selected = value == current ||
        (value == MarkupBlockKind.paragraph &&
            !AppTypography.isHeading(current));

    return PopupMenuItem<MarkupBlockKind>(
      value: value,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                // Each entry set at the size it produces, so the menu shows
                // the outcome rather than describing it.
                fontSize: AppTypography.sizeFor(value),
                fontWeight: AppTypography.isHeading(value)
                    ? FontWeight.w700
                    : FontWeight.w400,
              ),
            ),
          ),
          if (selected)
            Icon(Icons.check, size: 18, color: theme.colorScheme.primary),
        ],
      ),
    );
  }
}

class _Button extends StatelessWidget {
  const _Button({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.active,
    this.accent = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;

  /// Marks a button that inserts rather than toggles.
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final resting = accent
        ? theme.colorScheme.secondary
        : theme.colorScheme.onSurfaceVariant;

    return IconButton(
      icon: Icon(icon, size: 21),
      tooltip: tooltip,
      onPressed: onPressed,
      isSelected: active,
      // Announced as a switch rather than a button, so a screen-reader user
      // learns the state the sighted user reads off the highlight.
      style:
          IconButton.styleFrom(
            foregroundColor: resting,
            backgroundColor: Colors.transparent,
            highlightColor: theme.colorScheme.primary.withValues(alpha: .12),
          ).copyWith(
            backgroundColor: WidgetStateProperty.resolveWith<Color?>(
              (states) => active ? theme.colorScheme.primaryContainer : null,
            ),
            foregroundColor: WidgetStateProperty.resolveWith<Color?>(
              (states) =>
                  active ? theme.colorScheme.onPrimaryContainer : resting,
            ),
          ),
      // Full-size targets. `VisualDensity.compact` shaved these to about 40dp,
      // which is under the 48 the rest of the app is held to — and a formatting
      // bar is used mid-sentence with a thumb, which is the worst case for a
      // small target.
      visualDensity: VisualDensity.standard,
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: SizedBox(
        height: 20,
        child: VerticalDivider(
          width: 1,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    );
  }
}
