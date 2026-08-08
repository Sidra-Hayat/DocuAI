import 'package:flutter/material.dart';

import '../../../../core/text/markup_editing.dart';
import 'markup_editing_controller.dart';

/// Formatting buttons above the keyboard.
///
/// Every one is a toggle, so the syntax never has to be known — pressing bold
/// on bold text takes it off again. That is the whole justification for the
/// toolbar: the format is deliberately a plain string so that search, the
/// assistant and both exports can read it, and this is what stops that decision
/// costing the user anything.
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
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(top: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            children: <Widget>[
              _Button(
                icon: Icons.format_bold,
                tooltip: 'Bold',
                onPressed: () => controller.apply(MarkupEditing.toggleBold),
              ),
              _Button(
                icon: Icons.format_italic,
                tooltip: 'Italic',
                onPressed: () => controller.apply(MarkupEditing.toggleItalic),
              ),
              const _Divider(),
              _Button(
                icon: Icons.title,
                tooltip: 'Heading',
                onPressed: () =>
                    controller.apply(MarkupEditing.toggleHeading),
              ),
              _Button(
                icon: Icons.format_list_bulleted,
                tooltip: 'Bullet list',
                onPressed: () => controller.apply(MarkupEditing.toggleBullet),
              ),
              _Button(
                icon: Icons.format_list_numbered,
                tooltip: 'Numbered list',
                onPressed: () => controller.apply(MarkupEditing.toggleNumbered),
              ),
              _Button(
                icon: Icons.format_quote,
                tooltip: 'Quote',
                onPressed: () => controller.apply(MarkupEditing.toggleQuote),
              ),
            ],
          ),
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
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
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
