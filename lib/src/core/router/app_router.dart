import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/assistant/presentation/screens/assistant_screen.dart';
import '../../features/documents/presentation/screens/document_detail_screen.dart';
import '../../features/documents/presentation/screens/documents_screen.dart';
import '../../features/scanner/presentation/screens/scan_screen.dart';
import '../../features/search/presentation/screens/search_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import 'app_routes.dart';
import 'widgets/app_shell.dart';
import 'widgets/route_error_screen.dart';

/// Root navigator key — lets full-screen routes (scan, settings) be pushed
/// *above* the shell so they cover the bottom navigation bar.
final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// The application router.
///
/// Exposed as a provider so routes can later depend on app state (e.g. an
/// onboarding redirect reading Hive) without reaching for a global singleton,
/// and so widget tests can override it wholesale.
///
/// [StatefulShellRoute.indexedStack] gives each bottom-navigation branch its
/// own [Navigator]. That means switching tabs preserves scroll position and
/// nested history per tab — the behaviour users expect, and something a plain
/// `IndexedStack` over three widgets does not provide.
final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.documents,
    // Route logging is a development aid. In release it writes every
    // navigation — including document ids — to logcat, where any app holding
    // READ_LOGS on a rooted device can read it.
    debugLogDiagnostics: kDebugMode,
    errorBuilder: (context, state) => RouteErrorScreen(error: state.error),
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          // ---- Branch 0: document library ---------------------------------
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.documents,
                name: AppRoutes.documentsName,
                builder: (context, state) => const DocumentsScreen(),
                routes: [
                  GoRoute(
                    path: AppRoutes.documentDetail,
                    name: AppRoutes.documentDetailName,
                    builder: (context, state) => DocumentDetailScreen(
                      documentId: state.pathParameters['id']!,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // ---- Branch 1: search -------------------------------------------
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.search,
                name: AppRoutes.searchName,
                builder: (context, state) => const SearchScreen(),
              ),
            ],
          ),

          // ---- Branch 2: offline assistant --------------------------------
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.assistant,
                name: AppRoutes.assistantName,
                builder: (context, state) => const AssistantScreen(),
              ),
            ],
          ),
        ],
      ),

      // ---- Full-screen routes above the shell -----------------------------
      GoRoute(
        path: AppRoutes.settings,
        name: AppRoutes.settingsName,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.scan,
        name: AppRoutes.scanName,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ScanScreen(),
      ),
    ],
  );

  // GoRouter holds native platform resources; dispose it with the provider so
  // hot restart and tests do not leak router instances.
  ref.onDispose(router.dispose);

  return router;
});
