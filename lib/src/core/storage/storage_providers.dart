import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// The opened settings box, injected at startup.
///
/// This provider intentionally throws: the box is an *asynchronous* resource
/// that `bootstrap()` opens before `runApp`, then supplies via a
/// `ProviderScope` override. Declaring it this way means:
///
///  * widgets read the box synchronously, with no loading state to handle;
///  * tests can override it with an in-memory box in one line;
///  * forgetting the override fails loudly at startup instead of silently
///    returning empty data.
final settingsBoxProvider = Provider<Box<dynamic>>(
  (ref) => throw UnimplementedError(
    'settingsBoxProvider was not overridden. '
    'It must be provided by bootstrap() via ProviderScope.overrides.',
  ),
);
