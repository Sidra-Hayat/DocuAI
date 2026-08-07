import 'package:flutter/material.dart';

/// Tappable questions — suggestions before the first ask, recents afterwards.
///
/// Chips rather than a list because these are shortcuts, not content: they
/// should be reachable without reading, and take no more room than they earn.
class QuestionChips extends StatelessWidget {
  const QuestionChips({
    required this.questions,
    required this.onSelected,
    this.label,
    this.icon,
    super.key,
  });

  final List<String> questions;
  final ValueChanged<String> onSelected;
  final String? label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: .8,
            ),
          ),
          const SizedBox(height: 10),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final question in questions)
              ActionChip(
                avatar: icon == null ? null : Icon(icon, size: 16),
                label: Text(question),
                onPressed: () => onSelected(question),
              ),
          ],
        ),
      ],
    );
  }
}
