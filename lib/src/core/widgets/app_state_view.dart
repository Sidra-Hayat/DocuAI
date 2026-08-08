import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// What a screen is showing when it is not showing content.
enum AppStateTone {
  /// Nothing here yet, and that is normal. The user is invited to act.
  empty,

  /// Working. Reversible by waiting.
  busy,

  /// Something went wrong that the user may be able to fix.
  problem,
}

/// The one panel every screen uses when it has no content to show.
///
/// There were three separate treatments before this: `AppEmptyState` for empty,
/// a bare centred spinner in ten files for loading, and an ad-hoc mixture for
/// errors. A blank rectangle with a spinner in it is the least informative
/// thing an app can display — it says something is happening but not what, and
/// it looks identical whether the wait is a hundred milliseconds or a hundred
/// seconds.
///
/// Tone is not decoration. It decides the colour of the icon, whether the icon
/// is a spinner, and — through [Semantics] — what a screen reader announces the
/// region as, so a user who cannot see the panel still learns whether to wait
/// or to act.
class AppStateView extends StatelessWidget {
  const AppStateView({
    required this.title,
    this.icon,
    this.message,
    this.action,
    this.secondaryAction,
    this.tone = AppStateTone.empty,
    this.progress,
    super.key,
  });

  /// Shorthand for a screen that is loading, with an optional explanation.
  const AppStateView.busy({
    required this.title,
    this.message,
    this.progress,
    super.key,
  }) : icon = null,
       action = null,
       secondaryAction = null,
       tone = AppStateTone.busy;

  /// Shorthand for something that failed, where [action] is usually a retry.
  const AppStateView.problem({
    required this.title,
    required IconData this.icon,
    this.message,
    this.action,
    this.secondaryAction,
    super.key,
  }) : tone = AppStateTone.problem,
       progress = null;

  final String title;

  /// Null while [tone] is [AppStateTone.busy], where the spinner takes its
  /// place.
  final IconData? icon;

  final String? message;

  /// The one thing most worth doing from here.
  final Widget? action;

  /// A second, lesser way out. Rendered quieter so the primary stays primary.
  final Widget? secondaryAction;

  final AppStateTone tone;

  /// 0–1 for determinate work, null for indeterminate.
  ///
  /// Worth showing whenever it is known: "reading page 3 of 12" is a different
  /// experience from a spinner, even when the wait is identical.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colours = theme.colorScheme;

    final (iconColour, badgeColour) = switch (tone) {
      AppStateTone.empty => (
        colours.onSurfaceVariant,
        colours.surfaceContainerHighest,
      ),
      AppStateTone.busy => (colours.primary, colours.primaryContainer),
      AppStateTone.problem => (colours.error, colours.errorContainer),
    };

    return Semantics(
      container: true,
      // Announced ahead of the title, so the tone is known before the detail.
      label: switch (tone) {
        AppStateTone.empty => 'Nothing here yet',
        AppStateTone.busy => 'Working',
        AppStateTone.problem => 'Something went wrong',
      },
      liveRegion: tone == AppStateTone.busy,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.xxl,
            vertical: AppSpacing.xl,
          ),
          child: ConstrainedBox(
            // Bounded so the message stays readable on a tablet instead of
            // running the full width of the screen.
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _Badge(
                  icon: icon,
                  tone: tone,
                  progress: progress,
                  iconColour: iconColour,
                  badgeColour: badgeColour,
                ),
                AppSpacing.gapXl,
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (message != null) ...<Widget>[
                  AppSpacing.gapSm,
                  Text(
                    message!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colours.onSurfaceVariant,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (action != null) ...<Widget>[
                  AppSpacing.gapXl,
                  action!,
                ],
                if (secondaryAction != null) ...<Widget>[
                  AppSpacing.gapSm,
                  secondaryAction!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The circle at the top: an icon, or a spinner drawn around one.
class _Badge extends StatelessWidget {
  const _Badge({
    required this.icon,
    required this.tone,
    required this.progress,
    required this.iconColour,
    required this.badgeColour,
  });

  final IconData? icon;
  final AppStateTone tone;
  final double? progress;
  final Color iconColour;
  final Color badgeColour;

  @override
  Widget build(BuildContext context) {
    const size = 84.0;

    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          // The ring sits outside the badge rather than replacing it, so a
          // busy state has the same silhouette as the state it becomes — the
          // panel does not jump when the work finishes.
          if (tone == AppStateTone.busy)
            SizedBox.square(
              dimension: size,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 3,
                strokeCap: StrokeCap.round,
              ),
            ),
          Container(
            width: size - 24,
            height: size - 24,
            decoration: BoxDecoration(color: badgeColour, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: icon == null
                ? Text(
                    progress == null ? '' : '${(progress! * 100).round()}%',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: iconColour,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : Icon(
                    icon,
                    size: 32,
                    color: iconColour,
                    // Decorative: the title says what this is, and a screen
                    // reader announcing "description icon" adds nothing.
                    semanticLabel: null,
                  ),
          ),
        ],
      ),
    );
  }
}
