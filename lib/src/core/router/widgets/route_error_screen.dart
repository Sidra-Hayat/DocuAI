import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_routes.dart';

/// Shown when GoRouter cannot match a location.
///
/// A real screen rather than GoRouter's red debug page, so a bad deep link in
/// production degrades into something recoverable instead of alarming.
class RouteErrorScreen extends StatelessWidget {
  const RouteErrorScreen({this.error, super.key});

  final Exception? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Page not found')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.explore_off_outlined,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'We could not open that page',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                error?.toString() ?? 'The link may be broken or out of date.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => context.go(AppRoutes.documents),
                icon: const Icon(Icons.home_outlined),
                label: const Text('Back to documents'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
