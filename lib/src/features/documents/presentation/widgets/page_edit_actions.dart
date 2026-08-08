import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../import/presentation/providers/import_providers.dart';
import '../../domain/entities/document.dart';
import '../../domain/entities/document_page.dart';
import '../providers/document_providers.dart';

enum PageAction { replace, delete }

/// Replace or delete the page currently being looked at.
///
/// Shared by the viewer and the page manager so both offer the same actions
/// with the same confirmations — a page deleted from one place should not be
/// easier to lose than from the other.
class PageEditActions extends ConsumerWidget {
  const PageEditActions({
    required this.document,
    required this.pageIndex,
    super.key,
  });

  final Document document;
  final int pageIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = document.pages[pageIndex];
    final isLastPage = document.pageCount <= 1;

    return PopupMenuButton<PageAction>(
      tooltip: 'Page actions',
      onSelected: (action) => switch (action) {
        PageAction.replace => replaceDocumentPage(
          context,
          ref,
          documentId: document.id,
          page: page,
        ),
        PageAction.delete => confirmDeletePage(
          context,
          ref,
          document: document,
          pageId: page.id,
        ),
      },
      itemBuilder: (context) => <PopupMenuEntry<PageAction>>[
        // Rescanning swaps the image for a new capture. A written page has no
        // image to swap, and offering it would mean replacing authored content
        // with a photograph.
        if (page.hasImage)
          const PopupMenuItem(
            value: PageAction.replace,
            child: ListTile(
              leading: Icon(Icons.document_scanner_outlined),
              title: Text('Rescan this page'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        PopupMenuItem(
          value: PageAction.delete,
          // A document with no pages is not a document. Removing the last one
          // is a document delete, which is a different, separately confirmed
          // action rather than something to arrive at by deleting pages.
          enabled: !isLastPage,
          child: ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete this page'),
            subtitle: isLastPage
                ? const Text('A document needs at least one page')
                : null,
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ],
    );
  }
}

/// Re-captures a page in place, keeping its position.
///
/// Confirmed only when the page carries a correction. Rescanning always
/// discards the old image and text, but recognised text can be recognised
/// again — text a person typed cannot be recovered by any means the app has,
/// so that is the case worth stopping for. Confirming every rescan would put a
/// dialog in front of the ordinary fix for a bad capture.
Future<void> replaceDocumentPage(
  BuildContext context,
  WidgetRef ref, {
  required String documentId,
  required DocumentPage page,
}) async {
  final replace = ref.read(replacePageProvider);
  final messenger = ScaffoldMessenger.of(context);

  if (page.hasEditedText) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace your corrected text?'),
        content: Text(
          'You corrected the text on ${page.displayLabel.toLowerCase()}. '
          'Rescanning replaces the image and reads it again, so that '
          'correction is lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Rescan anyway'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
  }

  final result = await replace(documentId: documentId, pageId: page.id);

  result.fold(
    onSuccess: (_) => messenger.showSnackBar(
      const SnackBar(
        content: Text('Page replaced. Recognise the text again to update it.'),
      ),
    ),
    onFailure: (failure) {
      // Backing out of the scanner is not a failure worth reporting — the user
      // knows they cancelled.
      if (failure is ScanFailure && failure.cancelled) return;
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    },
  );
}

/// Confirms, then removes one page and its image.
Future<void> confirmDeletePage(
  BuildContext context,
  WidgetRef ref, {
  required Document document,
  required String pageId,
}) async {
  final delete = ref.read(deleteDocumentPageProvider);
  final messenger = ScaffoldMessenger.of(context);

  final page = document.pages.where((page) => page.id == pageId).firstOrNull;
  if (page == null) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete ${page.displayLabel.toLowerCase()}?'),
      content: const Text(
        'The image is removed from this device permanently. The rest of the '
        'document is kept.',
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

  final result = await delete(documentId: document.id, pageId: pageId);
  result.fold(
    onSuccess: (_) {},
    onFailure: (failure) =>
        messenger.showSnackBar(SnackBar(content: Text(failure.message))),
  );
}

/// Adds pages from photos already on the device.
///
/// Reads the use case before the picker is awaited, and captures the messenger
/// with it: the picker is a platform round trip long enough for this widget to
/// be gone by the time it returns, and reaching for `ref` or `context` then is
/// exactly how a disposed dependency gets touched.
Future<void> importPagesIntoDocument(
  BuildContext context,
  WidgetRef ref,
  String documentId,
) async {
  final import = ref.read(importImagesIntoDocumentProvider);
  final messenger = ScaffoldMessenger.of(context);

  final result = await import(documentId);

  result.fold(
    onSuccess: (imported) => messenger.showSnackBar(
      SnackBar(
        content: Text(
          imported.rejected.isEmpty
              ? 'Pages added. Recognise the text to include them.'
              : 'Pages added. ${imported.rejected.length} could not be read: '
                    '${imported.rejected.join(', ')}',
        ),
      ),
    ),
    onFailure: (failure) {
      // Dismissing the picker is not a failure worth reporting.
      if (failure is ImportFailure && failure.cancelled) return;
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    },
  );
}

/// Appends an empty page to write on.
Future<void> addTextPageToDocument(
  BuildContext context,
  WidgetRef ref,
  String documentId,
) async {
  final add = ref.read(addTextPageProvider);
  final messenger = ScaffoldMessenger.of(context);

  final result = await add(documentId);

  result.fold(
    onSuccess: (_) => messenger.showSnackBar(
      const SnackBar(content: Text('A blank page was added at the end.')),
    ),
    onFailure: (failure) =>
        messenger.showSnackBar(SnackBar(content: Text(failure.message))),
  );
}

/// Captures more pages and appends them.
Future<void> addPagesToDocument(
  BuildContext context,
  WidgetRef ref,
  String documentId,
) async {
  final add = ref.read(addPagesProvider);
  final messenger = ScaffoldMessenger.of(context);

  final result = await add(documentId);

  result.fold(
    onSuccess: (document) => messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Added to ${document.title}. Recognise the text to include the new '
          'pages.',
        ),
      ),
    ),
    onFailure: (failure) {
      if (failure is ScanFailure && failure.cancelled) return;
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    },
  );
}
