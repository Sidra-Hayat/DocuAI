import 'package:flutter/material.dart';

import 'app_state_view.dart';

/// Shared empty-state panel.
///
/// Now a thin wrapper over [AppStateView], which every screen's empty, busy and
/// error states share. Kept as its own name because a dozen screens already say
/// `AppEmptyState` and read perfectly well doing so — replacing the call sites
/// would be churn for no gain, and the rendering improves for all of them
/// either way.
///
/// Reach for [AppStateView] directly when the state is a wait or a failure
/// rather than an absence: it carries the tone through to the colour and to
/// what a screen reader announces.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    required this.icon,
    required this.title,
    this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? message;

  /// Optional primary call to action, e.g. "Scan your first document".
  final Widget? action;

  @override
  Widget build(BuildContext context) => AppStateView(
    icon: icon,
    title: title,
    message: message,
    action: action,
  );
}
