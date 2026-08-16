import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// The assistant's mark: a sparkle on a teal ground.
///
/// Teal rather than the indigo every button uses. The assistant is not an
/// action, it is a *part of the app that speaks*, and giving it the primary
/// colour would make its avatar read as something to press. One mark, used in
/// the bar and again beside every answer, is what stops the feature looking
/// like a chat window that happens to be installed here.
class AssistantMark extends StatelessWidget {
  const AssistantMark({this.size = 32, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Icon(
        Icons.auto_awesome,
        size: size * 0.56,
        color: theme.colorScheme.onSecondaryContainer,
      ),
    );
  }
}

/// The mark, a name and a line saying what it answers from.
///
/// Used as an app-bar title. The subtitle is the whole claim of the feature —
/// answers come from the user's own pages — and it belongs where the feature
/// is named rather than only in an empty state nobody sees twice.
class AssistantIdentity extends StatelessWidget {
  const AssistantIdentity({required this.subtitle, this.title, super.key});

  /// Defaults to the feature's name. A conversation about one document passes
  /// that document's title instead.
  final String? title;

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: <Widget>[
        const AssistantMark(),
        AppSpacing.gapHorizontalMd,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title ?? 'Assistant',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
