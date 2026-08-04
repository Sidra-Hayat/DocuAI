import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/core/observers/app_provider_observer.dart';
import 'src/core/storage/hive_initializer.dart';
import 'src/core/storage/storage_paths.dart';
import 'src/core/storage/storage_providers.dart';
import 'src/features/documents/data/datasources/documents_box.dart';
import 'src/features/search/data/datasources/search_index_local_data_source.dart';

/// Composition root.
///
/// Everything that must exist before the first frame happens here, in order:
///
///  1. bind the Flutter engine,
///  2. install global error handlers,
///  3. lock orientation and configure system chrome,
///  4. open asynchronous resources (Hive, the documents directory),
///  5. inject those resources into Riverpod as overrides, then run the app.
///
/// Keeping this out of `main.dart` means `main()` stays a single readable line
/// and the startup order is documented in one place.
///
/// Note: this takes no `overrides` parameter because Riverpod 3.3.2 does not
/// export its `Override` type publicly, so the parameter cannot be typed. Tests
/// construct their own [ProviderScope] instead — see `test/app_smoke_test.dart`
/// — which is equivalent and keeps the production path free of test hooks.
Future<void> bootstrap() async {
  // Guards against uncaught async errors escaping the framework's zone.
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      _installErrorHandlers();

      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Colors.transparent,
        ),
      );
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

      // Asynchronous resources are resolved here so that every provider that
      // depends on them can be read synchronously later.
      final settingsBox = await HiveInitializer.init();
      final documentsBox = await openDocumentsBox();
      final searchIndexBox = await openSearchIndexBox();
      final storagePaths = await createStoragePaths();

      runApp(
        ProviderScope(
          observers: const [AppProviderObserver()],
          overrides: [
            settingsBoxProvider.overrideWithValue(settingsBox),
            documentsBoxProvider.overrideWithValue(documentsBox),
            searchIndexBoxProvider.overrideWithValue(searchIndexBox),
            storagePathsProvider.overrideWithValue(storagePaths),
          ],
          child: const DocuAiApp(),
        ),
      );
    },
    (error, stackTrace) {
      // Last line of defence. Phase 8 can route this to a local crash log; it
      // must never leave the device, since DocuAI ships with no network layer.
      debugPrint('Uncaught zone error: $error\n$stackTrace');
    },
  );
}

/// Routes framework and platform errors through a single path.
void _installErrorHandlers() {
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (kReleaseMode) {
      debugPrint('Flutter error: ${details.exceptionAsString()}');
    }
  };

  // Errors raised on the platform thread that never reach the Flutter zone.
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    debugPrint('Platform error: $error\n$stackTrace');
    return true;
  };
}
