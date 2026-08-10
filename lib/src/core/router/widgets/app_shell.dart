import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Persistent chrome around the three primary destinations.
///
/// Receives the [StatefulNavigationShell] built by [StatefulShellRoute] and is
/// responsible only for presentation — the shell owns branch state.
///
/// Deliberately carries no floating action button. It used to hold one reading
/// "New", and a button in the shell is a button on every screen inside it:
/// creating a document was offered on Search, on the assistant's conversation
/// list, and — because the document routes are nested in the library's branch —
/// on top of the page the user was writing. Creation belongs to the library,
/// which is the only screen that has anywhere to put the result.
class AppShell extends StatelessWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  /// Tapping the destination you are already on pops that branch back to its
  /// root, matching platform convention. That is what `initialLocation: true`
  /// does when the index is unchanged.
  void _onDestinationSelected(int index) {
    navigationShell.goBranch(
      index,
      initialLocation: index == navigationShell.currentIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder),
            label: 'Documents',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome),
            label: 'Assistant',
          ),
        ],
      ),
    );
  }
}
