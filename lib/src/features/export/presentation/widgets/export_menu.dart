import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../documents/domain/entities/document.dart';
import '../providers/export_controller.dart';

enum _ExportFormat { pdf, docx }

/// Shares the document, in whichever format suits what is being sent.
///
/// One button with a choice rather than two buttons, because it is one
/// intention. The two formats are genuinely different products and the labels
/// say so: a PDF is a copy of the pages, a Word file is the text to work on.
class ExportMenu extends ConsumerWidget {
  const ExportMenu({required this.document, super.key});

  final Document document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(exportControllerProvider);
    final isThisDocument = state.documentId == document.id;

    final busy = isThisDocument && state is ExportRunning;
    final failed = isThisDocument && state is ExportFailedState;

    ref.listen<ExportState>(exportControllerProvider, (previous, next) {
      if (next is ExportFailedState && next.documentId == document.id) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.message)));
      }
    });

    return PopupMenuButton<_ExportFormat>(
      enabled: !busy && document.hasPages,
      tooltip: 'Share this document',
      onSelected: (format) {
        final controller = ref.read(exportControllerProvider.notifier);

        switch (format) {
          case _ExportFormat.pdf:
            // After a failure the recorded PDF is the likeliest culprit —
            // usually cleared from storage — so the retry composes a fresh one
            // rather than reaching for it again.
            controller.shareAsPdf(document, rebuild: failed);
          case _ExportFormat.docx:
            controller.shareAsDocx(document);
        }
      },
      itemBuilder: (context) => <PopupMenuEntry<_ExportFormat>>[
        const PopupMenuItem(
          value: _ExportFormat.pdf,
          child: ListTile(
            leading: Icon(Icons.picture_as_pdf_outlined),
            title: Text('Share as PDF'),
            subtitle: Text('The pages, as they look'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: _ExportFormat.docx,
          // Offered even with nothing recognised yet. The repository explains
          // what is missing and what to do about it, which is more use than a
          // greyed-out row that says nothing.
          child: ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Share as Word'),
            subtitle: Text(
              document.hasText
                  ? 'The text, ready to edit'
                  : 'Needs recognised text',
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
      child: AbsorbPointer(
        child: FilledButton.icon(
          onPressed: document.hasPages ? () {} : null,
          icon: busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(failed ? Icons.refresh : Icons.ios_share),
          label: Text(
            switch ((busy, failed)) {
              (true, _) => 'Preparing…',
              (false, true) => 'Try again',
              (false, false) => 'Share',
            },
          ),
        ),
      ),
    );
  }
}
