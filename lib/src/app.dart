import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';

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
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
