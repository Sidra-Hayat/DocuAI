import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../constants/hive_boxes.dart';

/// Owns Hive's one-time startup sequence.
///
/// Called from `bootstrap()` before `runApp`, so that every provider can assume
/// its box is already open and read synchronously — no `AsyncValue` loading
/// state just to reach local preferences.
///
/// Note this project uses **hive_ce** (Community Edition), not the original
/// `hive` package: upstream Hive is unmaintained and its code generator no
/// longer works on modern Dart SDKs.
abstract final class HiveInitializer {
  /// Initialises Hive and opens the boxes needed at startup.
  ///
  /// Only [HiveBoxes.settings] is opened here. The document, index and chat
  /// boxes are opened lazily by their own features once their type adapters
  /// exist, which keeps cold start fast as the database grows.
  static Future<Box<dynamic>> init() async {
    await Hive.initFlutter();

    _registerAdapters();

    return Hive.openBox<dynamic>(HiveBoxes.settings);
  }

  /// Registers every [TypeAdapter] in the app.
  ///
  /// Empty until Phase 2 introduces the persisted models. Adapters must be
  /// registered here — before any box holding them is opened — and their type
  /// ids come from [HiveTypeIds] so two models can never collide.
  static void _registerAdapters() {
    // Phase 2:
    //   Hive.registerAdapter(DocumentModelAdapter());
    //   Hive.registerAdapter(DocumentPageModelAdapter());
  }

  /// Flushes and closes all open boxes. Used by tests and by any future
  /// "clear all data" action in settings.
  static Future<void> close() => Hive.close();
}
