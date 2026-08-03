import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/phase_placeholder.dart';

/// Entry point for a new scan.
///
/// Phase 3 replaces this with the ML Kit Document Scanner flow. Because that
/// scanner is a Google Play Services module downloaded on demand, this screen
/// also becomes the place where an unavailable-module fallback is handled.
class ScanScreen extends ConsumerWidget {
  const ScanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan document')),
      body: const PhasePlaceholder(
        icon: Icons.document_scanner_outlined,
        title: 'Scanner',
        description:
            'Auto-crop, perspective correction and shadow removal via ML Kit, '
            'followed by on-device text recognition.',
        phase: 'Phase 3',
      ),
    );
  }
}
