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

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

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
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: theme.colorScheme.tertiaryContainer,
              borderRadius: AppRadius.small,
            ),
            child: Icon(
              Icons.description_rounded,
              size: 18,
              color: theme.colorScheme.tertiary,
            ),
          ),
          AppSpacing.gapHorizontalMd,
          Text(AppConstants.appName),
        ],
      ),
      actions: <Widget>[
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
