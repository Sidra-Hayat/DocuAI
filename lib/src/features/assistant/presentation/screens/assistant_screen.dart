import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/phase_placeholder.dart';

/// Offline document assistant.
///
/// Phase 7 builds the retrieval engine (BM25 over OCR text) and the chat UI;
/// the optional on-device language model is layered on afterwards behind a
/// settings toggle.
class AssistantScreen extends ConsumerWidget {
  const AssistantScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Assistant')),
      body: const PhasePlaceholder(
        icon: Icons.auto_awesome_outlined,
        title: 'Ask about your documents',
        description:
            'Ask questions and get answers drawn from your own scans. Runs '
            'entirely offline — nothing is ever uploaded.',
        phase: 'Phase 7',
      ),
    );
  }
}
