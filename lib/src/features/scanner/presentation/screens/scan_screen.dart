import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../domain/usecases/scan_new_document.dart';
import '../providers/scan_controller.dart';

/// Launch pad for the ML Kit scanner.
///
/// The scanner itself is a native activity, so this screen never shows a camera
/// — it explains what is about to happen, starts the flow, and handles what
/// comes back.
///
/// It starts on an explicit tap rather than automatically on first frame. An
/// auto-launching screen relaunches the scanner every time the user navigates
/// back onto it, which after saving a document means backing out of that
/// document reopens the camera — a loop with no exit but killing the app.
class ScanScreen extends ConsumerWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<ScanState>(scanControllerProvider, (previous, next) {
      switch (next) {
        case ScanSaved(:final document):
          ref.read(scanControllerProvider.notifier).reset();
          // Leave this screen behind before opening the document, so Back from
          // the document returns to the library rather than here.
          context.pop();
          context.pushNamed(
            AppRoutes.documentDetailName,
            pathParameters: {'id': document.id},
          );
        case ScanCancelled():
          ref.read(scanControllerProvider.notifier).reset();
          context.pop();
        case ScanIdle():
        case ScanRunning():
        case ScanFailedState():
          break;
      }
    });

    final state = ref.watch(scanControllerProvider);
    final availability = ref.watch(scannerAvailabilityProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Scan document')),
      body: switch (state) {
        ScanRunning() => const _Busy(),
        ScanFailedState(:final message) => _Failed(message: message),
        _ => availability.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => const _Unavailable(),
          data: (available) => available ? const _Ready() : const _Unavailable(),
        ),
      },
    );
  }
}

class _Ready extends ConsumerWidget {
  const _Ready();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return AppEmptyState(
      icon: Icons.document_scanner_outlined,
      title: 'Ready to scan',
      message:
          'Edges, perspective and shadows are corrected automatically. You can '
          'capture up to ${ScanNewDocument.defaultPageLimit} pages in one '
          'document, or pick an existing photo instead.',
      action: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            onPressed: () => ref.read(scanControllerProvider.notifier).start(),
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Start scanning'),
          ),
          const SizedBox(height: 12),
          Text(
            'Pages are saved to this device only.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 20),
          Text('Saving your pages…'),
        ],
      ),
    );
  }
}

class _Failed extends ConsumerWidget {
  const _Failed({required this.message});

  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppEmptyState(
      icon: Icons.error_outline,
      title: 'Scanning did not finish',
      message: message,
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () {
              ref.read(scanControllerProvider.notifier).reset();
              context.pop();
            },
            child: const Text('Back'),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: () => ref.read(scanControllerProvider.notifier).start(),
            child: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

/// Shown when Google Play Services cannot provide the scanner module.
///
/// States the reason rather than offering a retry, because nothing on this
/// screen would change the answer — and says plainly that the rest of the app
/// still works, so a non-GMS device is not left looking broken.
class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.no_photography_outlined,
      title: 'Scanning is not available here',
      message:
          'DocuAI scans with a Google Play Services module, which this device '
          'does not have. Everything else — your library, search and the '
          'assistant — works normally.',
      action: TextButton(
        onPressed: () => context.pop(),
        child: const Text('Back to library'),
      ),
    );
  }
}
