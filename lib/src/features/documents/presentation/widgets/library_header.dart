import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';

/// The library's app bar: the mark, the name, and the way out to settings.
///
/// The only place the brand is stated. Every other screen in the app is inside
/// a document, a search or a conversation, and a wordmark repeated at the top of
/// each of them would be a header competing with the thing the screen is for.
class LibraryAppBar extends StatelessWidget implements PreferredSizeWidget {
  const LibraryAppBar({super.key});

  /// Taller than the default toolbar, because the title is two lines.
  ///
  /// `kToolbarHeight` is 56 and the wordmark plus its line of small print needs
  /// more than that at the largest text size the app allows — at 56 the second
  /// line is clipped rather than wrapped, which is the kind of overflow that
  /// only shows up on somebody else's phone.
  @override
  Size get preferredSize => const Size.fromHeight(68);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppBar(
      titleSpacing: AppSpacing.lg,
      title: Row(
        children: <Widget>[
          // Gold, and small. The brand accent earns its place by being rare:
          // this mark and a favourite star are the whole of it, which is what
          // keeps it reading as gold rather than as another button colour.
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: AppRadius.small,
            ),
            child: Icon(
              Icons.description_rounded,
              size: 19,
              color: theme.colorScheme.onTertiaryContainer,
            ),
          ),
          AppSpacing.gapHorizontalMd,
          // Flexible, not bare. A two-line title in a Row is the classic app
          // bar overflow: the wordmark and its line of small print take their
          // intrinsic width, and on a 320dp phone — or at the largest text
          // size — that is wider than what the two action icons leave behind.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  AppConstants.appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                // The promise, stated once where the brand is. It is the whole
                // reason to keep a payslip in this app rather than another, and
                // it was only ever written down in Settings.
                Text(
                  'Private, on this device',
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
      ),
      actions: <Widget>[
        IconButton(
          onPressed: () => context.pushNamed(AppRoutes.helpName),
          icon: const Icon(Icons.help_outline),
          tooltip: 'How DocuAI works',
        ),
        IconButton(
          onPressed: () => context.pushNamed(AppRoutes.settingsName),
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Settings',
        ),
        AppSpacing.gapHorizontalXs,
      ],
    );
  }
}
