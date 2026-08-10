import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// The label above a group of things.
///
/// One component so that "Recent", "All documents", "Appearance" and "Sources"
/// are the same size, weight and colour wherever they appear — they were four
/// separate hand-rolled `Text` widgets with three different styles between
/// them, which is how a screen stops reading as one product.
class AppSectionHeader extends StatelessWidget {
  const AppSectionHeader({
    required this.label,
    this.action,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.lg,
      AppSpacing.sm,
      AppSpacing.sm,
    ),
    super.key,
  });

  final String label;

  /// A text button or similar, aligned to the right of the label.
  final Widget? action;

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: padding,
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                letterSpacing: .6,
              ),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}
