import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../assistant/presentation/screens/conversations_screen.dart';
import '../../../assistant/presentation/widgets/summarise_button.dart';
import '../../../export/presentation/widgets/export_menu.dart';
import '../../../ocr/presentation/providers/ocr_controller.dart';
import '../../domain/entities/document.dart';
import '../../domain/entities/document_page.dart';
import '../providers/document_providers.dart';
import '../widgets/document_actions.dart';
import '../widgets/document_thumbnail.dart';
import '../widgets/edit_tags_sheet.dart';
import '../widgets/extracted_text_entry.dart';

/// Single document view: pages, metadata, export and the library actions.
///
/// The recognised text lives on its own route — see [ExtractedTextEntry].
class DocumentDetailScreen extends ConsumerWidget {
  const DocumentDetailScreen({required this.documentId, super.key});

  final String documentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref.watch(documentProvider(documentId));

    // The document can vanish underneath this screen — deleted from here, or
    // from the library while it was open — and when it does, leaving is what
    // the user expects rather than a tombstone they have to dismiss.
    //
    // The screen observes the store instead of the delete action calling back.
    // A callback has to run on a context belonging to the subtree the delete
    // destroys: by the time it fires, `documentProvider` has already emitted
    // null, this body has been replaced, and `Navigator.of` on that dead
    // context silently does nothing. Reacting to the state has no such
    // ordering problem.
    ref.listen(documentProvider(documentId), (previous, next) {
      if (!next.hasValue || next.value != null) return;

      final navigator = Navigator.of(context);
      // Nothing to pop when this was opened directly; the body below then
      // explains what happened instead.
      if (navigator.canPop()) navigator.pop();
    });

    return document.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(),
        body: const AppEmptyState(
          icon: Icons.error_outline,
          title: 'Could not open this document',
        ),
      ),
      // Null means the record is gone — deleted from this screen, or from the
      // library while it was open. Either way there is nothing left to show.
      data: (value) => value == null
          ? const _DeletedDocument()
          : _DocumentDetail(document: value),
    );
  }
}

class _DocumentDetail extends ConsumerStatefulWidget {
  const _DocumentDetail({required this.document});

  final Document document;

  @override
  ConsumerState<_DocumentDetail> createState() => _DocumentDetailState();
}

class _DocumentDetailState extends ConsumerState<_DocumentDetail> {
  /// Starts recognition automatically the first time a document with unread
  /// pages is opened — which is what makes a freshly scanned document become
  /// searchable without the user being asked to press anything.
  ///
  /// This cannot loop. The run leaves every page either completed or failed,
  /// so the document's aggregate status is no longer [OcrStatus.pending] and
  /// the condition below is false on every subsequent open. Pages that failed
  /// are retried only on an explicit tap, because a page that cannot be read
  /// will not read any better the second time it is opened.
  @override
  void initState() {
    super.initState();

    final document = widget.document;
    if (document.hasPages && document.ocrStatus == OcrStatus.pending) {
      Future.microtask(() {
        if (!mounted) return;
        ref.read(ocrControllerProvider.notifier).run(document.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(document.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            onPressed: () => toggleDocumentFavorite(context, ref, document),
            tooltip: document.isFavorite
                ? 'Remove favourite'
                : 'Add to favourites',
            icon: Icon(
              document.isFavorite ? Icons.star : Icons.star_border_outlined,
            ),
          ),
          DocumentActionsMenu(document: document),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _PageCarousel(document: document),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(document.title, style: theme.textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  'Added ${DateFormat.yMMMd().format(document.createdAt)} · '
                  '${document.pageCount} '
                  '${document.pageCount == 1 ? 'page' : 'pages'}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                // Shown even when empty, so tagging is discoverable from the
                // document itself rather than only from a menu nobody opens
                // looking for it.
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final tag in document.tags)
                      Chip(
                        label: Text(tag),
                        visualDensity: VisualDensity.compact,
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.sell_outlined, size: 16),
                      label: Text(
                        document.tags.isEmpty ? 'Add tags' : 'Edit tags',
                      ),
                      visualDensity: VisualDensity.compact,
                      onPressed: () =>
                          showEditTagsSheet(context, ref, document),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ExportMenu(document: document),
                    SummariseButton(document: document),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          ListTile(
            leading: Icon(
              Icons.auto_awesome_motion_outlined,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Manage pages'),
            subtitle: Text(
              'Reorder, rescan, add or remove — '
              '${document.pageCount} ${document.pageCount == 1 ? 'page' : 'pages'}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.pushNamed(
              AppRoutes.managePagesName,
              pathParameters: {'id': document.id},
            ),
          ),
          if (document.pages.any((page) => page.isText)) ...[
            const Divider(),
            ListTile(
              leading: Icon(
                Icons.edit_note_outlined,
                color: theme.colorScheme.primary,
              ),
              title: const Text('Edit text'),
              subtitle: const Text(
                'Changes are saved on this device and searchable straight away',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.pushNamed(
                AppRoutes.editPageName,
                pathParameters: {
                  'id': document.id,
                  'page': document.pages
                      .firstWhere((page) => page.isText)
                      .id,
                },
              ),
            ),
          ],
          const Divider(),
          ListTile(
            leading: Icon(
              Icons.auto_awesome_outlined,
              color: theme.colorScheme.primary,
            ),
            title: const Text('Ask about this document'),
            subtitle: const Text(
              'Answers quoted from these pages only, in their own conversation',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openNewConversation(
              context,
              documentId: document.id,
              documentTitle: document.title,
            ),
          ),
          const Divider(),
          ExtractedTextEntry(document: document),
        ],
      ),
    );
  }
}

/// Horizontally pageable view of the scanned pages.
class _PageCarousel extends StatelessWidget {
  const _PageCarousel({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!document.hasPages) {
      return const SizedBox(
        height: 200,
        child: AppEmptyState(
          icon: Icons.image_not_supported_outlined,
          title: 'This document has no pages',
        ),
      );
    }

    return SizedBox(
      height: 320,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        itemCount: document.pageCount,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final page = document.pages[index];
          return InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            // Tapping a page opens it full screen at that page — the first
            // thing anyone does with a thumbnail of dense text.
            onTap: () => context.pushNamed(
              AppRoutes.pageViewerName,
              pathParameters: {'id': document.id, 'page': '$index'},
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                DocumentThumbnail(
                  page: page,
                  width: 200,
                  height: 260,
                  borderRadius: 12,
                ),
                const SizedBox(height: 8),
                Text(page.displayLabel, style: theme.textTheme.labelMedium),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DeletedDocument extends StatelessWidget {
  const _DeletedDocument();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: const AppEmptyState(
        icon: Icons.delete_outline,
        title: 'This document is no longer here',
        message: 'It was deleted from your library.',
      ),
    );
  }
}
