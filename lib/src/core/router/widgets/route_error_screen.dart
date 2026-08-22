import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_routes.dart';

/// Shown when GoRouter cannot match a location.
///
/// A real screen rather than GoRouter's red debug page, so a bad deep link in
/// production degrades into something recoverable instead of alarming.
class RouteErrorScreen extends StatelessWidget {
  const RouteErrorScreen({this.error, this.message, super.key});

  final Exception? error;

  /// A sentence written for the user, used in place of [error].
  ///
  /// GoRouter hands this screen an exception, whose `toString` is a developer's
  /// sentence with a class name in front of it. The routes that build this
  /// screen deliberately — an archive whose file has gone, a reader restored
  /// with nothing to read — know exactly what happened and can say it plainly,
  /// so they pass a sentence instead of manufacturing an exception to carry
  /// one.
  final String? message;

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
                message ??
                    error?.toString() ??
                    'The link may be broken or out of date.',
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
