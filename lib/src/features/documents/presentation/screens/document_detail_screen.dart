import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/storage/storage_paths.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_state_view.dart';
import '../../../assistant/presentation/screens/conversations_screen.dart';
import '../../../assistant/presentation/widgets/summarise_button.dart';
import '../../../ocr/presentation/providers/ocr_controller.dart';
import '../../domain/entities/document.dart';
import '../../domain/entities/document_page.dart';
import '../providers/document_providers.dart';
import '../widgets/document_action_bar.dart';
import '../widgets/document_actions.dart';
import '../widgets/document_thumbnail.dart';
import '../widgets/edit_tags_sheet.dart';

/// One document: its pages, and the three things you can do with them.
///
/// Built around Read / Edit / Share. It used to be a page carousel above four
/// full-width navigation rows — Manage pages, Edit text, Ask about this
/// document, View Extracted Text — plus an export button, a summarise button
/// and a copy of the title already in the app bar. Every one of those was a
/// reasonable idea; all of them at once turned a document into a settings menu.
///
/// The page you are looking at is now the subject of the screen, and the
/// actions follow it: Edit acts on *this* page rather than guessing which one
/// was meant.
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
        body: AppStateView.busy(title: 'Opening this document…'),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(),
        body: const AppStateView.problem(
          icon: Icons.error_outline,
          title: 'Could not open this document',
          message: 'The document could not be read from storage.',
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
  final PageController _pages = PageController();

  /// Which page the screen is showing, and therefore which page Edit acts on.
  int _current = 0;

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
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _goToPage(int index) {
    if (!_pages.hasClients) return;
    _pages.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    final theme = Theme.of(context);

    // Pages can be deleted while this screen is open, which can leave the
    // remembered index past the end of a shorter document.
    final current = document.hasPages
        ? _current.clamp(0, document.pageCount - 1)
        : 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(document.title, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          IconButton(
            onPressed: () => toggleDocumentFavorite(context, ref, document),
            tooltip: document.isFavorite
                ? 'Remove from favourites'
                : 'Add to favourites',
            icon: Icon(
              document.isFavorite ? Icons.star : Icons.star_border_outlined,
              // Gold only once it means something. An outline star is a
              // control; a filled gold one is a mark the user made.
              color: document.isFavorite ? theme.colorScheme.tertiary : null,
            ),
          ),
          DocumentActionsButton(document: document),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: <Widget>[
          _PageHero(
            document: document,
            controller: _pages,
            current: current,
            onPageChanged: (index) => setState(() => _current = index),
          ),
          if (document.pageCount > 1)
            _PageStrip(
              document: document,
              current: current,
              onSelected: _goToPage,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Added ${DateFormat.yMMMd().format(document.createdAt)} · '
                  '${document.pageCount} '
                  '${document.pageCount == 1 ? 'page' : 'pages'}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                AppSpacing.gapMd,
                // Shown even when empty, so tagging is discoverable from the
                // document itself rather than only from a menu nobody opens
                // looking for it.
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
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
                AppSpacing.gapXl,
                DocumentActionBar(document: document, pageIndex: current),
                AppSpacing.gapMd,
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: <Widget>[
                    FilledButton.tonalIcon(
                      onPressed: () => openNewConversation(
                        context,
                        documentId: document.id,
                        documentTitle: document.title,
                      ),
                      icon: const Icon(Icons.auto_awesome_outlined),
                      label: const Text('Ask about this'),
                    ),
                    SummariseButton(document: document),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The document itself, filling the top of the screen.
///
/// A single large page rather than the row of small thumbnails this used to be.
/// A document screen whose largest element is a list row is a screen that never
/// quite shows you your document; the first thing anyone wants from a scan is
/// to see whether it came out straight.
class _PageHero extends ConsumerWidget {
  const _PageHero({
    required this.document,
    required this.controller,
    required this.current,
    required this.onPageChanged,
  });

  final Document document;
  final PageController controller;
  final int current;
  final ValueChanged<int> onPageChanged;

  static const double _height = 340;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    if (!document.hasPages) {
      return const SizedBox(
        height: _height,
        child: AppStateView(
          icon: Icons.image_not_supported_outlined,
          title: 'This document has no pages',
          message: 'Use Edit to add one.',
        ),
      );
    }

    final paths = ref.watch(storagePathsProvider);

    return SizedBox(
      height: _height,
      child: Stack(
        children: <Widget>[
          PageView.builder(
            controller: controller,
            onPageChanged: onPageChanged,
            itemCount: document.pageCount,
            itemBuilder: (context, index) {
              final page = document.pages[index];

              return Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: InkWell(
                  borderRadius: AppRadius.card,
                  // Tapping a page opens it full screen at that page — the
                  // first thing anyone does with a small picture of dense text.
                  onTap: () => context.pushNamed(
                    AppRoutes.pageViewerName,
                    pathParameters: <String, String>{
                      'id': document.id,
                      'page': '$index',
                    },
                  ),
                  child: page.imagePath == null
                      ? _WrittenPagePreview(page: page)
                      : ClipRRect(
                          borderRadius: AppRadius.card,
                          child: Container(
                            color: theme.colorScheme.surfaceContainerLow,
                            width: double.infinity,
                            child: Image.file(
                              File(paths.absolutePath(page.imagePath!)),
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) =>
                                  Center(
                                    child: Icon(
                                      Icons.broken_image_outlined,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                            ),
                          ),
                        ),
                ),
              );
            },
          ),
          if (document.pageCount > 1)
            Positioned(
              right: AppSpacing.xl,
              bottom: AppSpacing.lg,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: .92,
                  ),
                  borderRadius: AppRadius.small,
                ),
                child: Text(
                  '${current + 1} / ${document.pageCount}',
                  style: theme.textTheme.labelMedium,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A page that was written rather than captured, shown as what it is.
class _WrittenPagePreview extends StatelessWidget {
  const _WrittenPagePreview({required this.page});

  final DocumentPage page;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.card,
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: page.hasText
          ? Text(
              page.text,
              maxLines: 10,
              overflow: TextOverflow.fade,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
            )
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.edit_note_outlined,
                    size: 32,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  AppSpacing.gapSm,
                  Text(
                    'This page is blank',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

/// Thumbnails under the page, for jumping around a long document.
class _PageStrip extends StatelessWidget {
  const _PageStrip({
    required this.document,
    required this.current,
    required this.onSelected,
  });

  final Document document;
  final int current;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: document.pageCount,
        separatorBuilder: (context, index) => AppSpacing.gapHorizontalSm,
        itemBuilder: (context, index) {
          final selected = index == current;

          return GestureDetector(
            onTap: () => onSelected(index),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                borderRadius: AppRadius.small,
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  width: 2,
                ),
              ),
              child: DocumentThumbnail(
                page: document.pages[index],
                width: 40,
                height: 52,
                borderRadius: AppRadius.xs,
              ),
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
      body: const AppStateView(
        icon: Icons.delete_outline,
        title: 'This document is no longer here',
        message: 'It was deleted from your library.',
      ),
    );
  }
}
