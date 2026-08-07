import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../ocr/presentation/providers/ocr_controller.dart';
import '../../domain/entities/document.dart';
import '../../domain/entities/document_page.dart';

/// The document detail screen's way into the recognised text.
///
/// Replaces the inline text section. The subtitle carries the state that
/// section used to show, so the row still answers "has this been read?"
/// without the detail screen having to render any of the text.
class ExtractedTextEntry extends ConsumerWidget {
  const ExtractedTextEntry({required this.document, super.key});

  final Document document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final ocr = ref.watch(ocrControllerProvider);
    final running = ocr is OcrRunning && ocr.documentId == document.id;

    return ListTile(
      leading: Icon(
        Icons.text_snippet_outlined,
        color: theme.colorScheme.primary,
      ),
      title: const Text('View Extracted Text'),
      subtitle: Text(_status(document, running ? ocr : null)),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.pushNamed(
        AppRoutes.extractedTextName,
        pathParameters: {'id': document.id},
      ),
    );
  }

  /// What the reader will show, said in advance.
  ///
  /// The row stays tappable in every state — the reader itself explains an
  /// empty or failed result and offers the retry, so there is nowhere the tap
  /// leads to a dead end.
  static String _status(Document document, OcrRunning? running) {
    if (running != null) {
      return running.total == 0
          ? 'Reading…'
          : 'Reading page ${running.done} of ${running.total}…';
    }

    if (document.hasText) {
      final characters = document.extractedText.length;
      final failed = document.pages
          .where((page) => page.ocrStatus == OcrStatus.failed)
          .length;

      final read = '${_thousands(characters)} characters';
      return failed == 0
          ? read
          : '$read · $failed ${failed == 1 ? 'page' : 'pages'} unread';
    }

    return switch (document.ocrStatus) {
      OcrStatus.completed => 'No text found on these pages',
      OcrStatus.failed => 'The pages could not be read',
      OcrStatus.pending || OcrStatus.running => 'Not read yet',
    };
  }

  static String _thousands(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();

    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }

    return buffer.toString();
  }
}
