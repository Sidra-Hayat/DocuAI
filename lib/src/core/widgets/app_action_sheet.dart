import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// One choice in an [showAppActionSheet].
///
/// [onSelected] runs *after* the sheet has closed, so a callback that pushes a
/// route or opens a dialog does not have to reason about a `BuildContext`
/// belonging to a subtree that is mid-dismissal — the defect this app has
/// already fixed by hand in three separate dialogs.
class AppSheetAction {
  const AppSheetAction({
    required this.icon,
    required this.label,
    required this.onSelected,
    this.description,
    this.enabled = true,
    this.isDestructive = false,
  });

  final IconData icon;
  final String label;

  /// One plain line saying what this does, for the actions where the label
  /// alone leaves a reasonable person guessing. Omit it when it would only
  /// restate the label — "Delete · Deletes the document" is noise.
  final String? description;

  final VoidCallback onSelected;
  final bool enabled;

  /// Draws in the error colour and sits below a divider. Reserved for actions
  /// that remove something from the device.
  final bool isDestructive;
}

/// The app's one menu.
///
/// A sheet rather than a `PopupMenuButton` for anything carrying a destructive
/// or secondary action. A popup opens as a small rectangle wherever the icon
/// happened to be, with rows too tight to hit reliably and no room to say what
/// an action does; a sheet arrives at the bottom of the screen, within a
/// thumb's reach, at full-row size.
Future<void> showAppActionSheet(
  BuildContext context, {
  required List<AppSheetAction> actions,
  String? title,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    // Without this the sheet is capped at nine sixteenths of the screen, and a
    // menu of five actions plus a title simply overflows it — the rows past the
    // cap are drawn and unreachable, which for a list ending in Delete is a
    // menu that quietly loses its most consequential item.
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _ActionSheet(title: title, actions: actions),
  );
}

class _ActionSheet extends StatelessWidget {
  const _ActionSheet({required this.actions, this.title});

  final String? title;
  final List<AppSheetAction> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final destructive = actions.where((action) => action.isDestructive);
    final ordinary = actions.where((action) => !action.isDestructive);

    return SafeArea(
      // Scrollable as well as unconstrained: a long menu at the largest text
      // size the app allows can still outgrow a short screen, and a sheet that
      // scrolls is the difference between a cramped menu and a broken one.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (title != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Text(
                  title!,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            for (final action in ordinary) _ActionRow(action: action),
            if (destructive.isNotEmpty) ...<Widget>[
              const Divider(indent: AppSpacing.lg, endIndent: AppSpacing.lg),
              for (final action in destructive) _ActionRow(action: action),
            ],
            AppSpacing.gapSm,
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action});

  final AppSheetAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final colour = !action.enabled
        ? theme.colorScheme.onSurfaceVariant.withValues(alpha: .5)
        : action.isDestructive
        ? theme.colorScheme.error
        : theme.colorScheme.primary;

    return ListTile(
      enabled: action.enabled,
      leading: Icon(action.icon, color: colour),
      title: Text(
        action.label,
        style: action.isDestructive && action.enabled
            ? TextStyle(color: theme.colorScheme.error)
            : null,
      ),
      subtitle: action.description == null ? null : Text(action.description!),
      onTap: () {
        // Closed first, then run. See [AppSheetAction.onSelected].
        Navigator.of(context).pop();
        action.onSelected();
      },
    );
  }
}
