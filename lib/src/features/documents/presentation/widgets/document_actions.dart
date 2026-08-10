import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_action_sheet.dart';
import '../../../export/presentation/widgets/share_sheet.dart';
import '../../domain/entities/document.dart';
import '../../domain/usecases/rename_document.dart';
import '../providers/document_providers.dart';
import 'edit_tags_sheet.dart';

/// The rename / tags / favourite / share / delete button, shared by the library
/// and the detail screen so both offer exactly the same actions.
///
/// A sheet rather than the popup menu this used to be. The actions here include
/// one that permanently removes files from the device, and a popup puts that
/// row in a small rectangle at the top of the screen, one line tall, next to
/// the four rows that do not.
class DocumentActionsButton extends ConsumerWidget {
  const DocumentActionsButton({required this.document, super.key});

  final Document document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      tooltip: 'More',
      icon: const Icon(Icons.more_vert),
      onPressed: () => showDocumentActionsSheet(context, ref, document),
    );
  }
}

/// The same actions, opened from wherever the caller wants them.
Future<void> showDocumentActionsSheet(
  BuildContext context,
  WidgetRef ref,
  Document document,
) {
  return showAppActionSheet(
    context,
    title: document.title,
    actions: <AppSheetAction>[
      AppSheetAction(
        icon: Icons.drive_file_rename_outline,
        label: 'Rename',
        onSelected: () => showRenameDocumentDialog(context, ref, document),
      ),
      AppSheetAction(
        icon: Icons.sell_outlined,
        label: document.tags.isEmpty ? 'Add tags' : 'Edit tags',
        description: 'Tags make a document easier to find later',
        onSelected: () => showEditTagsSheet(context, ref, document),
      ),
      AppSheetAction(
        icon: document.isFavorite ? Icons.star : Icons.star_border_outlined,
        label: document.isFavorite
            ? 'Remove from favourites'
            : 'Add to favourites',
        onSelected: () => toggleDocumentFavorite(context, ref, document),
      ),
      AppSheetAction(
        icon: Icons.ios_share,
        label: 'Share',
        description: 'Send a PDF or a Word file',
        enabled: document.hasPages,
        onSelected: () => showShareSheet(context, ref, document),
      ),
      AppSheetAction(
        icon: Icons.delete_outline,
        label: 'Delete',
        isDestructive: true,
        onSelected: () => confirmDeleteDocument(context, ref, document),
      ),
    ],
  );
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

  final title = await showDialog<String>(
    context: context,
    builder: (context) => _RenameDialog(initialTitle: document.title),
  );

  if (title == null) return;

  final result = await rename(documentId: document.id, title: title);
  result.fold(
    onSuccess: (_) {},
    onFailure: (failure) =>
        messenger.showSnackBar(SnackBar(content: Text(failure.message))),
  );
}

/// The rename dialog's body.
///
/// A `StatefulWidget` purely so that the [TextEditingController] is owned by
/// something inside the dialog's own subtree.
///
/// The controller used to be created next to `showDialog` and disposed as soon
/// as its future completed. That future completes when `Navigator.pop` is
/// called — `Route.didPop` completes the popped completer immediately — not
/// when the dismiss animation ends. For the length of that animation the
/// dialog is still mounted and still rebuilding, so the `TextField` reattached
/// listeners to a controller that had already been disposed. The visible
/// failure was three frames downstream: a controller-used-after-dispose
/// assertion aborted an element update mid-flight, which left an
/// `InheritedElement` holding a dependent that never deactivated, and the
/// framework then failed `_dependents.isEmpty` while tearing the route down.
///
/// Tying the controller to `State.dispose` removes the timing question
/// entirely: it is released when the route actually unmounts, whenever that is.
///
/// The dialog stays deliberately ignorant of what makes a title valid — it
/// returns raw text, and `RenameDocument` decides. Trimming or rejecting here
/// would put a business rule in a widget and let the two definitions drift.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initialTitle});

  final String initialTitle;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialTitle,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename document'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: RenameDocument.maxTitleLength,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Title',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Rename')),
      ],
    );
  }
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
  Document document,
) async {
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
  // Nothing to do on success: whichever screens are showing this document
  // react to it leaving the store. Telling them directly would mean calling
  // back into a widget the delete may already have unmounted.
  result.fold(
    onSuccess: (_) {},
    onFailure: (failure) =>
        messenger.showSnackBar(SnackBar(content: Text(failure.message))),
  );
}
