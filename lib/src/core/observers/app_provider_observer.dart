import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Logs provider failures during development.
///
/// Registered on the root [ProviderScope] in debug builds only. Without this, a
/// provider that throws inside `build()` can fail silently behind an
/// `AsyncValue.error` that no widget happens to display — a genuinely hard bug
/// to track down once repositories and use cases are in play.
final class AppProviderObserver extends ProviderObserver {
  const AppProviderObserver();

  @override
  void providerDidFail(
    ProviderObserverContext context,
    Object error,
    StackTrace stackTrace,
  ) {
    if (!kDebugMode) return;

    developer.log(
      'Provider failed: ${context.provider.name ?? context.provider.runtimeType}',
      name: 'DocuAI/Riverpod',
      error: error,
      stackTrace: stackTrace,
    );
  }
}
