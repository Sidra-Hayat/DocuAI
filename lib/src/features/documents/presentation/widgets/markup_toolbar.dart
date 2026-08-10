import 'package:flutter/material.dart';

import '../../../../core/text/markup_editing.dart';
import '../../../../core/theme/app_spacing.dart';
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
  const MarkupToolbar({required this.controller, super.key});

  final MarkupEditingController controller;

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
                horizontal: AppSpacing.xs,
                vertical: 2,
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
                  _Button(
                    icon: Icons.title,
                    tooltip: 'Heading',
                    active: active.contains(MarkupFormat.heading),
                    onPressed: () =>
                        controller.apply(MarkupEditing.toggleHeading),
                  ),
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
                ],
              ),
            );
          },
        ),
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
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onPressed,
      isSelected: active,
      // Announced as a switch rather than a button, so a screen-reader user
      // learns the state the sighted user reads off the highlight.
      style:
          IconButton.styleFrom(
            foregroundColor: theme.colorScheme.onSurfaceVariant,
            backgroundColor: Colors.transparent,
            highlightColor: theme.colorScheme.primary.withValues(alpha: .12),
          ).copyWith(
            backgroundColor: WidgetStateProperty.resolveWith<Color?>(
              (states) => active ? theme.colorScheme.primaryContainer : null,
            ),
            foregroundColor: WidgetStateProperty.resolveWith<Color?>(
              (states) => active
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
      visualDensity: VisualDensity.compact,
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
