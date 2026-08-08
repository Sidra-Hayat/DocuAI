import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/router/app_routes.dart';
import '../../../import/presentation/providers/import_providers.dart';
import '../../domain/usecases/create_text_document.dart';
import '../providers/document_providers.dart';

/// The two ways a document starts.
///
/// A sheet rather than a second floating button: creating is one intention with
/// two methods, and the choice belongs at the moment of asking rather than
/// permanently on top of the library.
Future<void> showNewDocumentSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  showDragHandle: true,
  builder: (context) => const _NewDocumentSheet(),
);

class _NewDocumentSheet extends StatelessWidget {
  const _NewDocumentSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(
              Icons.document_scanner_outlined,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Scan a document'),
            subtitle: const Text('Use the camera, then read the text on it'),
            onTap: () {
              Navigator.of(context).pop();
              context.pushNamed(AppRoutes.scanName);
            },
          ),
          ListTile(
            leading: Icon(
              Icons.photo_library_outlined,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Import photos'),
            subtitle: const Text('Use pictures already on this device'),
            onTap: () async {
              Navigator.of(context).pop();
              await importPhotosAsDocument(context);
            },
          ),
          ListTile(
            leading: Icon(
              Icons.edit_note_outlined,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Write a text document'),
            subtitle: const Text('Type a note — searchable like any other'),
            onTap: () async {
              Navigator.of(context).pop();
              await createAndOpenTextDocument(context);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
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

  final result = await container.read(importImagesAsDocumentProvider)(
    title: _importTitle(),
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
