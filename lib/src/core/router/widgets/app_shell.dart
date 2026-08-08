import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../features/documents/presentation/widgets/new_document_sheet.dart';

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
      // One button for "add a document", because scanning and writing are two
      // methods of one intention. A second floating button would have to sit
      // somewhere permanently, and neither method deserves that over the other.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showNewDocumentSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('New'),
        tooltip: 'Scan or write a new document',
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
