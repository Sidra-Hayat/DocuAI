import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/widgets/phase_placeholder.dart';

/// Document library — the app's home screen.
///
/// Phase 2 replaces the placeholder body with a Hive-backed grid/list driven by
/// a `documentsProvider`.
class DocumentsScreen extends ConsumerWidget {
  const DocumentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      body: const PhasePlaceholder(
        icon: Icons.folder_copy_outlined,
        title: 'No documents yet',
        description:
            'Scanned documents will appear here, stored entirely on this '
            'device.',
        phase: 'Phase 2',
      ),
    );
  }
}
