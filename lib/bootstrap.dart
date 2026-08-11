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
import 'src/features/assistant/data/datasources/chat_history_local_data_source.dart';
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
      final chatHistoryBox = await openChatHistoryBox();
      final storagePaths = await createStoragePaths();

      runApp(
        ProviderScope(
          observers: const [AppProviderObserver()],
          overrides: [
            settingsBoxProvider.overrideWithValue(settingsBox),
            documentsBoxProvider.overrideWithValue(documentsBox),
            searchIndexBoxProvider.overrideWithValue(searchIndexBox),
            chatHistoryBoxProvider.overrideWithValue(chatHistoryBox),
            storagePathsProvider.overrideWithValue(storagePaths),
          ],
          child: const DocuAiApp(),
        ),
      );
    },
    (error, stackTrace) {
      // Last line of defence. A local crash log could be routed from here; it
      // must never leave the device, since DocuAI ships with no network layer.
      _report('Uncaught zone error', error, stackTrace);
    },
  );
}

/// Routes framework and platform errors through a single path.
void _installErrorHandlers() {
  FlutterError.onError = (details) {
    // `presentError` writes the error to the console, and in a release build
    // the console is logcat. See [_report].
    if (kReleaseMode) return;
    FlutterError.presentError(details);
  };

  // Errors raised on the platform thread that never reach the Flutter zone.
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    _report('Platform error', error, stackTrace);
    // Handled either way: swallowing the error keeps the app running, and that
    // decision is separate from whether anything is printed about it.
    return true;
  };
}

/// Prints a failure where there is a developer to read it, and nowhere else.
///
/// Release builds say nothing. An exception string from this app routinely
/// carries a document title or a path into the sandbox — `NotFoundException`
/// names the id it could not find, storage failures name the file — and in a
/// release build the only reader of logcat is another application on a rooted
/// device. That is the same leak the router's route logging is already gated
/// for, arriving by a different door.
///
/// This costs nothing in diagnostics that anyone was actually getting: there is
/// no crash reporter, so a release trace printed here was only ever read by
/// whoever had the phone plugged in. If production diagnostics are wanted
/// later, the answer is a local crash log the user can export — not logcat.
void _report(String label, Object error, StackTrace stackTrace) {
  if (kReleaseMode) return;
  debugPrint('$label: $error\n$stackTrace');
}
