import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_routes.dart';

/// Persistent chrome around the three primary destinations.
///
/// Receives the [StatefulNavigationShell] built by [StatefulShellRoute] and is
/// responsible only for presentation — the shell owns branch state.
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.pushNamed(AppRoutes.scanName),
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Scan'),
        tooltip: 'Scan a new document',
      ),
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
