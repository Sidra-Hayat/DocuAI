import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_empty_state.dart';
import '../../domain/entities/document.dart';
import '../../domain/entities/document_page.dart';
import '../providers/document_providers.dart';
import '../widgets/document_thumbnail.dart';
import '../widgets/page_edit_actions.dart';

/// Where a new page comes from.
enum _AddPage { scan, import, text }

/// Reorder, delete, rescan and add pages.
///
/// A screen of its own rather than an edit mode on the detail screen: dragging
/// rows around is a different posture from reading a document, and mixing them
/// means every tap on the detail screen has to first ask which mode it is in.
class ManagePagesScreen extends ConsumerWidget {
  const ManagePagesScreen({required this.documentId, super.key});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref.watch(documentProvider(documentId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage pages'),
        actions: [
          if (document.value != null)
            PopupMenuButton<_AddPage>(
              tooltip: 'Add a page',
              icon: const Icon(Icons.add),
              onSelected: (choice) => switch (choice) {
                _AddPage.scan => addPagesToDocument(context, ref, documentId),
                _AddPage.import => importPagesIntoDocument(
                  context,
                  ref,
                  documentId,
                ),
                _AddPage.text => addTextPageToDocument(
                  context,
                  ref,
                  documentId,
                ),
              },
              itemBuilder: (context) => const <PopupMenuEntry<_AddPage>>[
                PopupMenuItem(
                  value: _AddPage.scan,
                  child: ListTile(
                    leading: Icon(Icons.document_scanner_outlined),
                    title: Text('Scan pages'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: _AddPage.import,
                  child: ListTile(
                    leading: Icon(Icons.photo_library_outlined),
                    title: Text('Import photos'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem(
                  value: _AddPage.text,
                  child: ListTile(
                    leading: Icon(Icons.edit_note_outlined),
                    title: Text('Add a text page'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
        ],
      ),
      body: document.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const AppEmptyState(
          icon: Icons.error_outline,
          title: 'Could not open this document',
        ),
        data: (value) => value == null
            ? const AppEmptyState(
                icon: Icons.delete_outline,
                title: 'This document is no longer here',
              )
            : _PageList(document: value),
      ),
    );
  }
}

class _PageList extends ConsumerWidget {
  const _PageList({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Drag to reorder. Page numbers follow the order here.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.only(bottom: 24),
            itemCount: document.pageCount,
            onReorder: (oldIndex, newIndex) =>
                _reorder(ref, oldIndex, newIndex),
            itemBuilder: (context, index) {
              final page = document.pages[index];

              return ListTile(
                key: ValueKey<String>(page.id),
                leading: DocumentThumbnail(page: page, width: 40, height: 54),
                title: Text(page.displayLabel),
                subtitle: Text(_status(page)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PageEditActions(document: document, pageIndex: index),
                    ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(Icons.drag_handle),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _reorder(WidgetRef ref, int oldIndex, int newIndex) async {
    // ReorderableListView reports the target as an insertion point, which is
    // one past the intended index when moving down the list.
    final target = newIndex > oldIndex ? newIndex - 1 : newIndex;

    final ids = document.pages.map((page) => page.id).toList();
    final moved = ids.removeAt(oldIndex);
    ids.insert(target, moved);

    await ref.read(reorderPagesProvider)(
      documentId: document.id,
      orderedPageIds: ids,
    );
  }

  /// What the row says under the page number.
  ///
  /// Written pages are described by what they are rather than by an OCR state
  /// they were never in: "not read yet" on a page nobody scanned would be
  /// reporting on work that was never outstanding.
  static String _status(DocumentPage page) {
    final provenance = switch (page.kind) {
      PageKind.text => 'Written',
      PageKind.imported => 'Imported',
      PageKind.scanned => 'Scanned',
    };

    if (!page.hasImage) {
      return page.hasText
          ? '$provenance · ${page.text.length} characters'
          : '$provenance · blank';
    }

    final text = switch (page.ocrStatus) {
      OcrStatus.completed =>
        page.hasText ? '${page.text.length} characters' : 'No text found',
      OcrStatus.failed => 'Could not be read',
      OcrStatus.running => 'Reading…',
      OcrStatus.pending => 'Not read yet',
    };

    return '$provenance · $text';
  }
}
