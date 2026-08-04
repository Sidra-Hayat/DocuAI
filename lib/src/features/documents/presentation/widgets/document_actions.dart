import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/document.dart';
import '../../domain/usecases/rename_document.dart';
import '../providers/document_providers.dart';

/// The rename / favourite / delete menu, shared by the library list and the
/// detail screen so both offer exactly the same actions.
enum DocumentAction { rename, toggleFavorite, delete }

class DocumentActionsMenu extends ConsumerWidget {
  const DocumentActionsMenu({
    required this.document,
    this.onDeleted,
    super.key,
  });

  final Document document;

  /// Called after a successful delete. The detail screen uses it to pop itself;
  /// the library list has nothing to do, because the row disappears with the
  /// stream update.
  final VoidCallback? onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<DocumentAction>(
      tooltip: 'Document actions',
      onSelected: (action) => _run(context, ref, action),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: DocumentAction.rename,
          child: ListTile(
            leading: Icon(Icons.drive_file_rename_outline),
            title: Text('Rename'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        PopupMenuItem(
          value: DocumentAction.toggleFavorite,
          child: ListTile(
            leading: Icon(
              document.isFavorite ? Icons.star : Icons.star_border_outlined,
            ),
            title: Text(
              document.isFavorite ? 'Remove favourite' : 'Add to favourites',
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: DocumentAction.delete,
          child: ListTile(
            leading: Icon(Icons.delete_outline),
            title: Text('Delete'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    DocumentAction action,
  ) async {
    switch (action) {
      case DocumentAction.rename:
        await showRenameDocumentDialog(context, ref, document);
      case DocumentAction.toggleFavorite:
        await toggleDocumentFavorite(context, ref, document);
      case DocumentAction.delete:
        await confirmDeleteDocument(context, ref, document, onDeleted: onDeleted);
    }
  }
}

/// Prompts for a new title and applies it.
///
/// The use case is read *before* the dialog is awaited. Reading a provider off
/// a `ref` whose widget has since been disposed throws, and a dialog is exactly
/// the kind of await during which that can happen.
Future<void> showRenameDocumentDialog(
  BuildContext context,
  WidgetRef ref,
  Document document,
) async {
  final rename = ref.read(renameDocumentProvider);
  final messenger = ScaffoldMessenger.of(context);
  final controller = TextEditingController(text: document.title);

  final title = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rename document'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: RenameDocument.maxTitleLength,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Title',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Rename'),
        ),
      ],
    ),
  );

  controller.dispose();
  if (title == null) return;

  final result = await rename(documentId: document.id, title: title);
  result.fold(
    onSuccess: (_) {},
    onFailure: (failure) =>
        messenger.showSnackBar(SnackBar(content: Text(failure.message))),
  );
}

Future<void> toggleDocumentFavorite(
  BuildContext context,
  WidgetRef ref,
  Document document,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await ref.read(toggleFavoriteProvider)(document.id);

  result.fold(
    onSuccess: (_) {},
    onFailure: (failure) =>
        messenger.showSnackBar(SnackBar(content: Text(failure.message))),
  );
}

/// Confirms, then deletes the document, its page images and its PDF.
///
/// Confirmation is not optional here: deletion removes files from disk with no
/// undo and no cloud copy to restore from — the whole point of an offline app.
Future<void> confirmDeleteDocument(
  BuildContext context,
  WidgetRef ref,
  Document document, {
  VoidCallback? onDeleted,
}) async {
  final delete = ref.read(deleteDocumentProvider);
  final messenger = ScaffoldMessenger.of(context);

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete document?'),
      content: Text(
        '"${document.title}" and its ${document.pageCount} '
        '${document.pageCount == 1 ? 'page' : 'pages'} will be permanently '
        'removed from this device. This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.tonal(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );

  if (confirmed != true) return;

  final result = await delete(document.id);
  result.fold(
    onSuccess: (_) => onDeleted?.call(),
    onFailure: (failure) =>
        messenger.showSnackBar(SnackBar(content: Text(failure.message))),
  );
}
