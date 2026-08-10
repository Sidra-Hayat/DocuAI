import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_action_sheet.dart';
import '../../../documents/domain/entities/document.dart';
import '../providers/export_controller.dart';

/// The two ways a document leaves the app.
///
/// One intention with two products, and the descriptions say which is which: a
/// PDF is a copy of the pages, a Word file is the text to work on. Neither
/// label says "export" — that is a word for the person who wrote the file
/// format, not for the person sending their landlord a copy of a bill.
Future<void> showShareSheet(
  BuildContext context,
  WidgetRef ref,
  Document document,
) {
  // Captured before the sheet opens. Everything below runs after an await, by
  // which point the sheet that started it is gone.
  final messenger = ScaffoldMessenger.of(context);
  final state = ref.read(exportControllerProvider);
  final failedBefore =
      state is ExportFailedState && state.documentId == document.id;

  return showAppActionSheet(
    context,
    title: 'Share this document',
    actions: <AppSheetAction>[
      AppSheetAction(
        icon: Icons.picture_as_pdf_outlined,
        label: 'Share as PDF',
        description: 'The pages, as they look',
        enabled: document.hasPages,
        onSelected: () => _share(
          messenger,
          ref,
          document,
          // After a failure the recorded PDF is the likeliest culprit — usually
          // cleared from storage — so the retry composes a fresh one rather
          // than reaching for it again.
          () => ref
              .read(exportControllerProvider.notifier)
              .shareAsPdf(document, rebuild: failedBefore),
        ),
      ),
      AppSheetAction(
        icon: Icons.description_outlined,
        label: 'Share as Word',
        // Offered even with nothing read yet. The repository explains what is
        // missing and what to do about it, which is more use than a greyed-out
        // row that says nothing.
        description: document.hasText
            ? 'The text, ready to edit'
            : 'Needs the text from the pages first',
        enabled: document.hasPages,
        onSelected: () => _share(
          messenger,
          ref,
          document,
          () =>
              ref.read(exportControllerProvider.notifier).shareAsDocx(document),
        ),
      ),
    ],
  );
}

/// Runs an export and reports only what the user cannot already see.
///
/// Success needs no message: the system share sheet appearing *is* the
/// confirmation, and a snackbar sliding in underneath it would be the app
/// talking over the thing it just opened.
Future<void> _share(
  ScaffoldMessengerState messenger,
  WidgetRef ref,
  Document document,
  Future<void> Function() run,
) async {
  await run();

  final state = ref.read(exportControllerProvider);
  if (state is ExportFailedState && state.documentId == document.id) {
    messenger.showSnackBar(SnackBar(content: Text(state.message)));
  }
}
