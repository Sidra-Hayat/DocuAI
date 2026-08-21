import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'features/incoming/presentation/incoming_files_listener.dart';

/// Root widget.
///
/// Deliberately thin: it wires the router and the two themes together and does
/// nothing else. All startup work happens in `bootstrap()` before this is ever
/// built, so there is no loading state to represent here.
class DocuAiApp extends ConsumerWidget {
  const DocuAiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      // Owned by the listener below, which has no route context of its own and
      // still has to be able to say "that file could not be opened".
      scaffoldMessengerKey: IncomingFilesListener.messengerKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      // Clamp text scaling: DocuAI is a document app and accessibility settings
      // above 1.4x break page thumbnails and OCR overlays. Users who need more
      // can still zoom the document view itself.
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(
            textScaler: mediaQuery.textScaler.clamp(
              minScaleFactor: 0.8,
              maxScaleFactor: 1.4,
            ),
          ),
          // Wraps the navigator rather than sitting inside a screen, because a
          // file handed over by another app can arrive whatever is on screen —
          // including nothing, on a cold start. It renders its child and
          // nothing else.
          child: IncomingFilesListener(
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
