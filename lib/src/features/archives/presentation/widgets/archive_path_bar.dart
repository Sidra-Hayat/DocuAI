import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';

/// Where in the archive you are, and a way back to anywhere above it.
///
/// A breadcrumb rather than a plain "up" button. Four folders deep, an up
/// button is four taps to the root and no indication of how far in you went;
/// the trail says both at once and makes every level a single tap.
///
/// It scrolls horizontally because folder names inside somebody else's archive
/// are not written to fit a phone — `Statements_2026_Q1_final(2)` is a real
/// folder name — and a trail that wrapped onto three lines would push the files
/// off the screen.
class ArchivePathBar extends StatelessWidget {
  const ArchivePathBar({
    required this.archiveName,
    required this.folder,
    required this.onGoTo,
    super.key,
  });

  /// Shown as the first crumb: the archive itself is the root folder.
  final String archiveName;

  /// Slash-separated, empty at the root.
  final String folder;

  /// Called with the folder path to move to — the empty string for the root.
  final ValueChanged<String> onGoTo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segments = folder.isEmpty ? const <String>[] : folder.split('/');

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        children: <Widget>[
          _Crumb(
            label: archiveName,
            icon: Icons.folder_zip_outlined,
            isCurrent: segments.isEmpty,
            onTap: () => onGoTo(''),
          ),
          for (var index = 0; index < segments.length; index++) ...<Widget>[
            Icon(
              Icons.chevron_right,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            _Crumb(
              label: segments[index],
              isCurrent: index == segments.length - 1,
              onTap: () => onGoTo(segments.take(index + 1).join('/')),
            ),
          ],
        ],
      ),
    );
  }
}

class _Crumb extends StatelessWidget {
  const _Crumb({
    required this.label,
    required this.isCurrent,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool isCurrent;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: InkWell(
        // The crumb you are already standing on is not a link. Leaving it
        // tappable would make the trail's last item do nothing, which reads as
        // a bug rather than as a position.
        onTap: isCurrent ? null : onTap,
        borderRadius: AppRadius.small,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(
                  icon,
                  size: 16,
                  color: isCurrent
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.primary,
                ),
                AppSpacing.gapHorizontalXs,
              ],
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: isCurrent
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.primary,
                  fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
