import 'package:flutter/material.dart';

import 'app_empty_state.dart';

/// Temporary body used by screens whose feature has not been built yet.
///
/// Every occurrence of this widget is a deliberate, greppable marker of
/// unfinished work — `grep -r PhasePlaceholder lib` lists exactly what remains.
/// Each one is deleted by the phase named in [phase].
class PhasePlaceholder extends StatelessWidget {
  const PhasePlaceholder({
    required this.icon,
    required this.title,
    required this.description,
    required this.phase,
    super.key,
  });

  final IconData icon;
  final String title;
  final String description;

  /// Human-readable name of the roadmap phase that replaces this screen.
  final String phase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppEmptyState(
      icon: icon,
      title: title,
      message: description,
      action: Chip(
        avatar: const Icon(Icons.construction_outlined, size: 18),
        label: Text('Arrives in $phase'),
        backgroundColor: theme.colorScheme.secondaryContainer,
        labelStyle: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
        side: BorderSide.none,
      ),
    );
  }
}
