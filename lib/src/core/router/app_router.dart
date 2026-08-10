import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/assistant/presentation/assistant_intent_codec.dart';
import '../../features/assistant/presentation/screens/assistant_screen.dart';
import '../../features/assistant/presentation/screens/conversations_screen.dart';
import '../../features/documents/presentation/screens/document_detail_screen.dart';
import '../../features/documents/presentation/screens/documents_screen.dart';
import '../../features/documents/presentation/screens/extracted_text_screen.dart';
import '../../features/documents/presentation/screens/manage_pages_screen.dart';
import '../../features/documents/presentation/screens/page_viewer_screen.dart';
import '../../features/documents/presentation/screens/text_editor_screen.dart';
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
                    // Everything below opens *above* the shell.
                    //
                    // These are the screens that are one document and nothing
                    // else: a page filling the display, a page being written,
                    // the text being read. Nested inside the branch they kept
                    // the navigation bar and the shell's floating button, so
                    // the "full screen" page viewer drew its own black chrome
                    // and then had a tab bar rendered on top of it.
                    //
                    // Only the navigator changes. The paths, names and helpers
                    // in [AppRoutes] are untouched, so every existing link and
                    // deep link still resolves — and Back still lands on the
                    // document, because that is what sits underneath.
                    routes: [
                      GoRoute(
                        path: AppRoutes.extractedText,
                        name: AppRoutes.extractedTextName,
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (context, state) => ExtractedTextScreen(
                          documentId: state.pathParameters['id']!,
                        ),
                      ),
                      GoRoute(
                        path: AppRoutes.pageViewer,
                        name: AppRoutes.pageViewerName,
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (context, state) => PageViewerScreen(
                          documentId: state.pathParameters['id']!,
                          // A malformed page number opens the first page
                          // rather than failing the route.
                          initialPage:
                              int.tryParse(
                                state.pathParameters['page'] ?? '',
                              ) ??
                              0,
                        ),
                      ),
                      GoRoute(
                        path: AppRoutes.managePages,
                        name: AppRoutes.managePagesName,
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (context, state) => ManagePagesScreen(
                          documentId: state.pathParameters['id']!,
                        ),
                      ),
                      GoRoute(
                        path: AppRoutes.editPage,
                        name: AppRoutes.editPageName,
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (context, state) => TextEditorScreen(
                          documentId: state.pathParameters['id']!,
                          pageId: state.pathParameters['page']!,
                        ),
                      ),
                    ],
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
                builder: (context, state) => const ConversationsScreen(),
                routes: [
                  GoRoute(
                    path: AppRoutes.conversation,
                    name: AppRoutes.conversationName,
                    // Above the shell, like the document screens: a
                    // conversation is a composer, a keyboard and a transcript,
                    // and a navigation bar between the composer and the bottom
                    // of the screen is chrome nobody reaches for mid-question.
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => AssistantScreen(
                      conversationId: state.pathParameters['conversation']!,
                      documentId: state.uri.queryParameters['document'],
                      // Passed rather than looked up so the bar has a title on
                      // the first frame instead of flashing a placeholder
                      // while a stream resolves.
                      documentTitle: state.uri.queryParameters['title'],
                      // Set by Summarise, Explain and the reader's selection —
                      // this route arriving with the action already chosen.
                      // Decoded to an intent here rather than carried as a
                      // sentence, so nothing downstream has to parse it.
                      initialIntent: AssistantIntentCodec.decode(
                        action: state
                            .uri
                            .queryParameters[AssistantIntentCodec.actionKey],
                        selection: state
                            .uri
                            .queryParameters[AssistantIntentCodec.selectionKey],
                      ),
                    ),
                  ),
                ],
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
