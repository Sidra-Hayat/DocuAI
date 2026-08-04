import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../domain/entities/document.dart';
import '../providers/document_providers.dart';
import '../widgets/document_tile.dart';

/// Document library — the app's home screen.
///
/// Reads one stream and renders its three states. Because the stream is fed by
/// `box.watch()`, a rename or delete performed anywhere in the app redraws this
/// list without it knowing anything happened.
class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documents = ref.watch(documentsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConstants.appName),
        actions: [
          IconButton(
            onPressed: () => context.pushNamed(AppRoutes.settingsName),
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: documents.when(
        data: (items) => items.isEmpty
            ? const _EmptyLibrary()
            : _DocumentList(documents: items),
        loading: () => const Center(child: CircularProgressIndicator()),
        // Storage failing is not something the user can fix, so this states
        // what happened rather than suggesting an action that would not help.
        error: (error, stackTrace) => const AppEmptyState(
          icon: Icons.error_outline,
          title: 'Could not open your library',
          message:
              'The document database could not be read. Restarting DocuAI '
              'usually clears this.',
        ),
      ),
    );
  }
}

class _DocumentList extends StatelessWidget {
  const _DocumentList({required this.documents});

  final List<Document> documents;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      // Clears the FAB, which would otherwise sit on top of the last row.
      padding: const EdgeInsets.only(top: 8, bottom: 88),
      itemCount: documents.length,
      separatorBuilder: (context, index) => const Divider(height: 1, indent: 80),
      itemBuilder: (context, index) =>
          DocumentTile(document: documents[index]),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.folder_copy_outlined,
      title: 'No documents yet',
      message:
          'Scanned documents will appear here, stored entirely on this device.',
      action: FilledButton.icon(
        onPressed: () => context.pushNamed(AppRoutes.scanName),
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Scan a document'),
      ),
    );
  }
}
