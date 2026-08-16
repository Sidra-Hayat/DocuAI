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

      final trace = _StartupTrace()..mark('binding');

      // Off the critical path deliberately. Orientation and the edge-to-edge
      // flag are two platform round trips that were awaited before the first
      // frame, and neither has to be: the window is already the right shape,
      // and the system bars settle a frame later without anything having been
      // drawn wrongly in between.
      unawaited(_configureSystemChrome());

      // Started before the Hive sequence rather than after it. Resolving the
      // documents directory is an independent platform call, so it has no
      // reason to queue behind four box opens — it overlaps all of them.
      final storagePathsFuture = createStoragePaths();

      // Must complete first: `initFlutter` resolves Hive's own directory, and
      // adapters have to be registered before any box holding them is opened.
      await HiveInitializer.prepare();
      trace.mark('hive init');

      // All four opened at once rather than one after another. They were
      // strictly sequential, so a cold start paid the sum of four file reads
      // and four deserialisations; started together it pays the slowest one.
      //
      // They are still all awaited before the first frame. The search index
      // and the chat history are genuinely not needed by the library screen —
      // deferring them outright would be a further win — but both are injected
      // into synchronous providers, and making those asynchronous is a change
      // to the shape of two features rather than to startup. See the report.
      //
      // Safe to overlap: Hive holds one open-box future per name and the four
      // names are distinct, so each gets its own file, its own lock file and
      // its own backend. A box that fails to open still aborts the boot the way
      // it did when these ran one after another — the difference is only that
      // the ones after it were already in flight.
      final settingsFuture = HiveInitializer.openSettingsBox();
      final documentsFuture = openDocumentsBox();
      final searchIndexFuture = openSearchIndexBox();
      final chatHistoryFuture = openChatHistoryBox();

      final settingsBox = await settingsFuture;
      trace.mark('settings box');
      final documentsBox = await documentsFuture;
      trace.mark('documents box', () => '${documentsBox.length} documents');
      final searchIndexBox = await searchIndexFuture;
      trace.mark('search index box', () => '${searchIndexBox.length} entries');
      final chatHistoryBox = await chatHistoryFuture;
      trace.mark('chat history box', () => '${chatHistoryBox.length} messages');

      final storagePaths = await storagePathsFuture;
      trace
        ..mark('storage paths')
        ..report();

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

/// Orientation and system-bar configuration, off the startup critical path.
///
/// Awaited by nobody. Both calls are one-way messages to the platform, and a
/// frame drawn a few milliseconds before they land is a frame drawn at the same
/// size with the same colours — there is nothing for the user to see.
Future<void> _configureSystemChrome() async {
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
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
}

/// Where the time before the first frame actually went.
///
/// Debug builds only — `debugPrint` is a no-op away from a developer, and
/// `kReleaseMode` is a compile-time constant so the whole class is removed by
/// the tree shaker.
///
/// It exists because "the app takes a while to open" is not a diagnosis. Cold
/// start on a real phone is dominated by engine and Dart VM startup, which this
/// cannot see and cannot change; what it can show is how much of the remainder
/// belongs to each box — and, in particular, whether the search index has grown
/// large enough to be worth deferring off this path entirely.
class _StartupTrace {
  final Stopwatch _watch = Stopwatch()..start();
  final List<(String, int, String)> _marks = <(String, int, String)>[];
  int _last = 0;

  /// [detail] carries how much work the step actually had to do — the number of
  /// records in the box it opened. A duration on its own says a step was slow;
  /// a duration beside "1,842 entries" says *why*, and whether the fix is to
  /// defer the step or to stop the box growing.
  ///
  /// A callback rather than a string so that a release build never builds one.
  /// `'${box.length} entries'` at the call site would be interpolated on every
  /// cold start of the shipped app to be handed to a method that discards it.
  void mark(String label, [String Function()? detail]) {
    if (kReleaseMode) return;
    final now = _watch.elapsedMilliseconds;
    _marks.add((label, now - _last, detail?.call() ?? ''));
    _last = now;
  }

  void report() {
    if (kReleaseMode) return;

    final lines = _marks
        .map(
          (mark) =>
              '  ${mark.$2.toString().padLeft(5)}ms  ${mark.$1}'
              '${mark.$3.isEmpty ? '' : '  (${mark.$3})'}',
        )
        .join('\n');

    debugPrint(
      'DocuAI startup — ${_watch.elapsedMilliseconds}ms of Dart work before '
      'runApp\n$lines\n'
      // Said in the log because it is the first thing anyone reading this
      // number needs to know: a debug build carries the JIT and the observatory
      // and starts several times slower than the AOT build a user installs.
      // Optimising against a debug figure is optimising against the toolchain.
      '  NOTE: debug build. Measure a release build before drawing '
      'conclusions.',
    );
  }
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
