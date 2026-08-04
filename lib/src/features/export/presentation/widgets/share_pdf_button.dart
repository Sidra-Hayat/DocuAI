import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../documents/domain/entities/document.dart';
import '../providers/export_controller.dart';

/// Composes and shares the document as a PDF.
///
/// One button rather than separate "export" and "share" actions: from the
/// user's side sharing is the goal, and whether a PDF already exists is an
/// implementation detail they should never have to think about.
class SharePdfButton extends ConsumerWidget {
  const SharePdfButton({required this.document, super.key});

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

    return FilledButton.icon(
      onPressed: busy || !document.hasPages
          ? null
          : () => ref
                .read(exportControllerProvider.notifier)
                // After a failure the recorded PDF is the likeliest culprit —
                // most often it has been cleared from storage — so the retry
                // composes a fresh one rather than reaching for it again.
                .shareAsPdf(document, rebuild: failed),
      icon: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(failed ? Icons.refresh : Icons.picture_as_pdf_outlined),
      label: Text(
        switch ((busy, failed)) {
          (true, _) => 'Preparing PDF…',
          (false, true) => 'Try again',
          (false, false) => 'Share as PDF',
        },
      ),
    );
  }
}
