import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_action_sheet.dart';
import '../../../import/presentation/providers/import_providers.dart';
import '../../domain/usecases/create_text_document.dart';
import '../providers/document_providers.dart';

/// The ways a document starts.
///
/// A sheet rather than three floating buttons: creating is one intention with
/// several methods, and the choice belongs at the moment of asking rather than
/// permanently on top of the library.
///
/// Named for what the user is doing, not for the machinery — Scan, Import,
/// Create. Each carries one line saying what it actually does, because "Import"
/// alone does not tell anyone whether it means their camera roll or their
/// downloads folder.
Future<void> showNewDocumentSheet(BuildContext context) {
  return showAppActionSheet(
    context,
    title: 'Add to your library',
    actions: <AppSheetAction>[
      AppSheetAction(
        icon: Icons.document_scanner_outlined,
        label: 'Scan',
        description: 'Use the camera, then read the text on it',
        onSelected: () => context.pushNamed(AppRoutes.scanName),
      ),
      AppSheetAction(
        icon: Icons.photo_library_outlined,
        label: 'Import photos',
        description: 'Pictures already on this device',
        onSelected: () => importPhotosAsDocument(context),
      ),
      AppSheetAction(
        icon: Icons.folder_open_outlined,
        label: 'Import a file',
        description: 'A PDF, a Word file, or a text file',
        onSelected: () => importFileAsDocument(context),
      ),
      AppSheetAction(
        icon: Icons.edit_note_outlined,
        label: 'Create',
        description: 'Write a document yourself',
        onSelected: () => createAndOpenTextDocument(context),
      ),
    ],
  );
}

/// Asks for a title, creates the document, and opens it for writing.
///
/// The title is asked for first because it is what the library row shows, and
/// a list of "Untitled document" is a library nobody can use. It is still
/// optional — [CreateTextDocument.defaultTitle] covers someone who wants to
/// start writing immediately, and the title is renameable from then on.
Future<void> createAndOpenTextDocument(BuildContext context) async {
  final title = await showDialog<String>(
    context: context,
    builder: (context) => const _TitleDialog(),
  );

  // Dismissed rather than confirmed: creating a document nobody asked for
  // would leave it in the library to be deleted by hand.
  if (title == null || !context.mounted) return;

  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);

  final result = await container.read(createTextDocumentProvider)(title: title);

  switch (result) {
    case Success(:final value):
      await router.pushNamed<void>(
        AppRoutes.editPageName,
        pathParameters: <String, String>{
          'id': value.id,
          'page': value.pages.first.id,
        },
      );
    case Failed(:final failure):
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
  }
}

/// Builds a document from photos on the device.
///
/// Every provider, messenger and router this needs is read *before* the picker
/// is awaited. The picker is a platform round trip long enough for the sheet
/// that started it to be gone by the time it returns, and reaching through a
/// dead `BuildContext` afterwards is exactly how a disposed dependency gets
/// touched.
Future<void> importPhotosAsDocument(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);

  final result = await _whileImporting(
    context,
    message: 'Importing your photos…',
    work: () => container.read(importImagesAsDocumentProvider)(
      title: _importTitle(),
    ),
  );

  switch (result) {
    case Success(:final value):
      if (value.rejected.isNotEmpty) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${value.rejected.length} photo(s) could not be read: '
              '${value.rejected.join(', ')}',
            ),
          ),
        );
      }
      await router.pushNamed<void>(
        AppRoutes.documentDetailName,
        pathParameters: <String, String>{'id': value.document.id},
      );
    case Failed(:final failure):
      if (failure is ImportFailure && failure.cancelled) return;
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
  }
}

/// Builds a document from a PDF, a Word file, a text file or a picture.
///
/// A PDF becomes pages and is read like a scan; a Word or text file becomes a
/// document you can edit. Either way what lands in the library is an ordinary
/// document — the point of importing rather than merely opening.
///
/// Every dependency is resolved *before* the picker is awaited, for the same
/// reason the photo import does it: the picker is a platform round trip long
/// enough for the sheet that started it to be gone by the time it returns.
Future<void> importFileAsDocument(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);

  final result = await _whileImporting(
    context,
    message: 'Importing your document…',
    work: () => container.read(importFileAsDocumentProvider)(),
  );

  switch (result) {
    case Success(:final value):
      // Said before the document opens, and left up longer than a normal
      // message, because it is the one thing about this import the user cannot
      // see for themselves: the document looks complete either way.
      if (value.truncatedAt case final kept?) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'That PDF is longer than DocuAI can import. The first $kept '
              'pages were brought in; the rest were not.',
            ),
            duration: const Duration(seconds: 6),
          ),
        );
      }
      await router.pushNamed<void>(
        AppRoutes.documentDetailName,
        pathParameters: <String, String>{'id': value.document.id},
      );
    case Failed(:final failure):
      // Backing out of the picker is not a failure worth reporting.
      if (failure is ImportFailure && failure.cancelled) return;
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
  }
}

/// Asks whether "Import" means a photo or a file, then does that.
///
/// The empty library offers one Import button where the library proper offers
/// two separate ones, and it used to mean photos only — so a first-run user
/// with a PDF had nowhere to go, the file importer being reachable only from
/// the New document sheet that the empty state deliberately hides.
///
/// A choice rather than a fourth button: the empty state is three actions and
/// a sentence, and a fourth would make the first thing anyone sees a menu.
/// Both branches call the same functions the sheet calls — there is one photo
/// import and one file import in this app, and this adds neither.
Future<void> chooseImportSource(BuildContext context) {
  return showAppActionSheet(
    context,
    title: 'Import',
    actions: <AppSheetAction>[
      AppSheetAction(
        icon: Icons.photo_library_outlined,
        label: 'Photo',
        description: 'Choose a photo from your gallery',
        onSelected: () => importPhotosAsDocument(context),
      ),
      AppSheetAction(
        icon: Icons.folder_open_outlined,
        label: 'File',
        description: 'Import a PDF, DOCX or text file',
        onSelected: () => importFileAsDocument(context),
      ),
    ],
  );
}

/// Holds a progress dialog up for as long as an import takes.
///
/// **Why it is raised before the picker rather than after it.** Both imports
/// are a single call that opens the system picker *and* then does the work —
/// normalising every photo, or rasterising every page of a PDF, then copying
/// the results into storage. There is no moment in between for this to hook
/// on to without threading a callback down through the use case and the
/// repository into the data source.
///
/// It does not need one. The picker is a separate Android activity that covers
/// this app's window entirely, so a dialog raised now is behind it and unseen;
/// the first frame the user sees it in is the one after the picker closes,
/// which is exactly when the work starts. Backing out of the picker shows it
/// for the moment it takes the cancellation to travel back.
///
/// No percentage. Neither import reports how far through it is — the photo
/// picker hands over everything at once and the page loop is inside the
/// repository — and a bar that advances on a timer is a lie about how long is
/// left. The PDF tools do show one, because their pipeline genuinely counts
/// pages as it goes.
Future<T> _whileImporting<T>(
  BuildContext context, {
  required String message,
  required Future<T> Function() work,
}) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  var showing = true;

  unawaited(
    showDialog<void>(
      context: context,
      // Neither the barrier nor the back button dismisses it: the work carries
      // on regardless, and a screen with no sign of it is how the same import
      // gets started twice.
      barrierDismissible: false,
      builder: (context) => _ImportingDialog(message: message),
    ).whenComplete(() => showing = false),
  );

  try {
    return await work();
  } finally {
    // In a `finally` so that success, failure and cancellation all take it
    // down. Guarded because the route may already be gone — the whole point of
    // `showing` is that this must never pop somebody else's route.
    if (showing && navigator.mounted) navigator.pop();
  }
}

/// The dialog itself: a spinner, a sentence, and no way to dismiss it.
class _ImportingDialog extends StatelessWidget {
  const _ImportingDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: Semantics(
          // Announced when it appears, so the wait is stated rather than shown.
          liveRegion: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              AppSpacing.gapHorizontalMd,
              Expanded(child: Text(message, style: theme.textTheme.bodyMedium)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Imported documents are named after the day they were brought in.
///
/// Not asked for up front: the photos are already chosen by then, and stopping
/// to name the result before it exists is a form the user did not come for.
/// It is renameable like any other document.
String _importTitle() {
  final now = DateTime.now();
  final month = now.month.toString().padLeft(2, '0');
  final day = now.day.toString().padLeft(2, '0');
  return 'Imported $day/$month/${now.year}';
}

class _TitleDialog extends StatefulWidget {
  const _TitleDialog();

  @override
  State<_TitleDialog> createState() => _TitleDialogState();
}

/// Owns its controller.
///
/// A `TextEditingController` created at the `showDialog` call site is disposed
/// while the dialog is still animating out, which trips the framework's
/// `_dependents.isEmpty` assertion — the defect already fixed once in the
/// rename dialog, and the reason this is a StatefulWidget for four lines of
/// state.
class _TitleDialogState extends State<_TitleDialog> {
  final TextEditingController _title = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_title.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New text document'),
      content: TextField(
        controller: _title,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: 'Title',
          hintText: CreateTextDocument.defaultTitle,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}
