import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/phase_placeholder.dart';

/// Single document view: pages, extracted text, export and share actions.
///
/// Phase 2 wires [documentId] to a repository lookup; Phase 4 adds the OCR text
/// tab and Phase 5 the PDF export action.
class DocumentDetailScreen extends ConsumerWidget {
  const DocumentDetailScreen({required this.documentId, super.key});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('Document')),
      body: PhasePlaceholder(
        icon: Icons.description_outlined,
        title: 'Document $documentId',
        description:
            'Pages, extracted text and export options will be shown here.',
        phase: 'Phase 2',
      ),
    );
  }
}
