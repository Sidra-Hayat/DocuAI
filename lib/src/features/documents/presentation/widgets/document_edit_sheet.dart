import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/widgets/app_action_sheet.dart';
import '../../domain/entities/document.dart';
import 'page_edit_actions.dart';

/// Everything that changes a document, one tap behind Edit.
///
/// Scoped to the page the user is looking at, which is the whole point: the
/// actions that used to live on the detail screen either applied to the
/// document as a whole or quietly picked a page on the user's behalf. "Edit
/// this page" is a promise the screen can keep, because the page is the one
/// filling the screen behind the sheet.
Future<void> showDocumentEditSheet(
  BuildContext context,
  WidgetRef ref,
  Document document,
  int pageIndex,
) {
  final index = pageIndex.clamp(0, document.pageCount - 1);
  final page = document.hasPages ? document.pages[index] : null;
  final isLastPage = document.pageCount <= 1;

  return showAppActionSheet(
    context,
    title: page == null ? 'Edit' : 'Edit ${page.displayLabel.toLowerCase()}',
    actions: <AppSheetAction>[
      if (page != null)
        AppSheetAction(
          icon: Icons.edit_note_outlined,
          label: page.hasImage
              ? 'Edit the text on this page'
              : 'Edit this page',
          description: page.hasImage
              ? 'Correct anything the camera misread'
              : null,
          onSelected: () => context.pushNamed(
            AppRoutes.editPageName,
            pathParameters: <String, String>{
              'id': document.id,
              'page': page.id,
            },
          ),
        ),
      AppSheetAction(
        icon: Icons.add_photo_alternate_outlined,
        label: 'Add a page',
        onSelected: () => showAddPageSheet(context, ref, document.id),
      ),
      AppSheetAction(
        icon: Icons.reorder,
        label: 'Reorder pages',
        enabled: document.pageCount > 1,
        description: document.pageCount > 1
            ? null
            : 'There is only one page to order',
        onSelected: () => context.pushNamed(
          AppRoutes.managePagesName,
          pathParameters: <String, String>{'id': document.id},
        ),
      ),
      // Rescanning swaps the image for a new capture. A written page has no
      // image to swap, and offering it would mean replacing authored content
      // with a photograph.
      if (page != null && page.hasImage)
        AppSheetAction(
          icon: Icons.document_scanner_outlined,
          label: 'Scan this page again',
          description: 'Replaces the picture and reads it again',
          onSelected: () => replaceDocumentPage(
            context,
            ref,
            documentId: document.id,
            page: page,
          ),
        ),
      if (page != null)
        AppSheetAction(
          icon: Icons.delete_outline,
          label: 'Delete this page',
          // A document with no pages is not a document. Removing the last one
          // is a document delete, which is a different, separately confirmed
          // action rather than something to arrive at by deleting pages.
          enabled: !isLastPage,
          description: isLastPage ? 'A document needs at least one page' : null,
          isDestructive: true,
          onSelected: () => confirmDeletePage(
            context,
            ref,
            document: document,
            pageId: page.id,
          ),
        ),
    ],
  );
}

/// Where a new page comes from.
Future<void> showAddPageSheet(
  BuildContext context,
  WidgetRef ref,
  String documentId,
) {
  return showAppActionSheet(
    context,
    title: 'Add a page',
    actions: <AppSheetAction>[
      AppSheetAction(
        icon: Icons.document_scanner_outlined,
        label: 'Scan',
        description: 'Capture more pages with the camera',
        onSelected: () => addPagesToDocument(context, ref, documentId),
      ),
      AppSheetAction(
        icon: Icons.photo_library_outlined,
        label: 'Import photos',
        description: 'Pictures already on this device',
        onSelected: () => importPagesIntoDocument(context, ref, documentId),
      ),
      AppSheetAction(
        icon: Icons.edit_note_outlined,
        label: 'Write a page',
        description: 'A blank page, opened for typing',
        onSelected: () => addTextPageToDocument(context, ref, documentId),
      ),
    ],
  );
}
