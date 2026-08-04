import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../ocr/presentation/providers/ocr_controller.dart';
import '../../domain/entities/document.dart';
import '../../domain/entities/document_page.dart';

/// Recognised text for one document, plus the controls to produce it.
///
/// Reads the document's own OCR status rather than the controller for
/// everything except live progress: the status is persisted, so reopening a
/// document shows the right thing without a run having happened this session.
class DocumentTextSection extends ConsumerWidget {
  const DocumentTextSection({required this.document, super.key});

  final Document document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ocr = ref.watch(ocrControllerProvider);
    final theme = Theme.of(context);

    // A run for a different document must not paint progress here.
    final running = ocr is OcrRunning && ocr.documentId == document.id
        ? ocr
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Recognised text',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (running == null && document.hasText)
                IconButton(
                  tooltip: 'Read the pages again',
                  onPressed: () => ref
                      .read(ocrControllerProvider.notifier)
                      .run(document.id, force: true),
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (running != null)
            _Progress(state: running)
          else
            ..._body(context, ref, theme),
        ],
      ),
    );
  }

  List<Widget> _body(BuildContext context, WidgetRef ref, ThemeData theme) {
    final failedPages = document.pages
        .where((page) => page.ocrStatus == OcrStatus.failed)
        .length;

    return <Widget>[
      if (document.hasText) ...[
        if (failedPages > 0) ...[
          _Notice(
            icon: Icons.warning_amber_outlined,
            message: failedPages == 1
                ? 'One page could not be read. The text below is from the rest.'
                : '$failedPages pages could not be read. The text below is '
                      'from the rest.',
            onRetry: () =>
                ref.read(ocrControllerProvider.notifier).run(document.id),
          ),
          const SizedBox(height: 12),
        ],
        SelectableText(
          document.extractedText,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
        ),
      ] else
        switch (document.ocrStatus) {
          // Recognition ran and genuinely found nothing — a photograph of a
          // blank page is a valid result, not an error.
          OcrStatus.completed => _Notice(
            icon: Icons.text_fields_outlined,
            message:
                'No text was found on these pages. Photos of drawings or blank '
                'pages have nothing to read.',
            onRetry: () => ref
                .read(ocrControllerProvider.notifier)
                .run(document.id, force: true),
            retryLabel: 'Read again',
          ),
          OcrStatus.failed => _Notice(
            icon: Icons.error_outline,
            message:
                'The pages could not be read. This usually means the images '
                'are too blurred or were taken at too steep an angle.',
            onRetry: () =>
                ref.read(ocrControllerProvider.notifier).run(document.id),
          ),
          OcrStatus.pending || OcrStatus.running => _Notice(
            icon: Icons.text_snippet_outlined,
            message:
                'Reading the text makes this document searchable and lets the '
                'assistant answer questions about it.',
            onRetry: () =>
                ref.read(ocrControllerProvider.notifier).run(document.id),
            retryLabel: 'Recognise text',
          ),
        },
    ];
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.state});

  final OcrRunning state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // A determinate bar once the page count is known; the first moments of
        // a run have nothing to divide by.
        LinearProgressIndicator(value: state.fraction),
        const SizedBox(height: 10),
        Text(
          state.total == 0
              ? 'Preparing…'
              : 'Reading page ${state.done} of ${state.total}…',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.message,
    required this.onRetry,
    this.retryLabel = 'Try again',
  });

  final IconData icon;
  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: onRetry,
              child: Text(retryLabel),
            ),
          ),
        ],
      ),
    );
  }
}
