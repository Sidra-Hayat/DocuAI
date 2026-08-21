import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/storage/storage_paths.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_state_view.dart';
import '../../../../core/widgets/page_image_decoding.dart';
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
import '../widgets/markup_view.dart';

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
                // The title, on the page rather than only in the bar. An app
                // bar title is one line, small, and ellipsised — which for a
                // document called "Tenancy agreement — 14 Marlowe Street" is
                // most of the name missing from the screen that is about it.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        document.title,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                        ),
                      ),
                    ),
                    AppSpacing.gapHorizontalSm,
                    // A second, larger favourite control beside the title. The
                    // one in the app bar is easy to miss and hard to reach
                    // one-handed on a tall phone; this one sits next to the
                    // thing it marks.
                    IconButton.filledTonal(
                      onPressed: () =>
                          toggleDocumentFavorite(context, ref, document),
                      tooltip: document.isFavorite
                          ? 'Remove from favourites'
                          : 'Add to favourites',
                      icon: Icon(
                        document.isFavorite
                            ? Icons.star
                            : Icons.star_border_outlined,
                        color: document.isFavorite
                            ? theme.colorScheme.tertiary
                            : null,
                      ),
                    ),
                  ],
                ),
                AppSpacing.gapSm,
                _DocumentMeta(document: document),
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
                _AssistantPanel(document: document),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What kind of document this is, how big, and when it arrived.
///
/// One muted line under the title, with the origin as a badge — the same
/// treatment the library card uses, so a document looks like itself in both
/// places.
class _DocumentMeta extends StatelessWidget {
  const _DocumentMeta({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (icon, origin) = switch (document.source) {
      DocumentSource.scanned => (Icons.document_scanner_outlined, 'Scanned'),
      DocumentSource.imported => (Icons.photo_library_outlined, 'Imported'),
      DocumentSource.created => (Icons.edit_note_outlined, 'Written'),
    };

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: 2,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: AppRadius.chip,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 12,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              AppSpacing.gapHorizontalXs,
              Text(
                origin,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Text(
          '${document.pageCount} '
          '${document.pageCount == 1 ? 'page' : 'pages'} · '
          'Added ${DateFormat.yMMMd().format(document.createdAt)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// The assistant, offered on the document it would be asked about.
///
/// Given a panel of its own rather than two tonal buttons in the run of the
/// screen. Ask and Summarise are not more actions alongside Read, Edit and
/// Share — they are a different faculty, and the teal ground says so in the one
/// place a user is most likely to discover it: looking at a document they do
/// not want to read all of.
class _AssistantPanel extends StatelessWidget {
  const _AssistantPanel({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withValues(alpha: .45),
        borderRadius: AppRadius.card,
        border: Border.all(
          color: theme.colorScheme.secondary.withValues(alpha: .3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.auto_awesome,
                size: 16,
                color: theme.colorScheme.secondary,
              ),
              AppSpacing.gapHorizontalSm,
              Expanded(
                child: Text(
                  'Ask DocuAI about this document',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          AppSpacing.gapSm,
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: <Widget>[
              FilledButton.tonalIcon(
                onPressed: () => openNewConversation(
                  context,
                  documentId: document.id,
                  documentTitle: document.title,
                ),
                icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                label: const Text('Ask about this'),
              ),
              SummariseButton(document: document),
            ],
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
                      ? _WrittenPagePreview(page: page, documentId: document.id)
                      : ClipRRect(
                          borderRadius: AppRadius.card,
                          child: Container(
                            color: theme.colorScheme.surfaceContainerLow,
                            width: double.infinity,
                            child: Image.file(
                              File(paths.absolutePath(page.imagePath!)),
                              fit: BoxFit.contain,
                              // The card is [_PageHero._height] tall and the
                              // fit is `contain`, so height is what the page
                              // is scaled to. A thirty-page document keeps
                              // three of these alive at once in the PageView;
                              // at full size that was ninety megabytes of
                              // bitmap for three cards.
                              cacheHeight: pageDecodeExtent(
                                context,
                                _PageHero._height,
                              ),
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
  const _WrittenPagePreview({required this.page, required this.documentId});

  final DocumentPage page;
  final String documentId;

  /// How tall a picture may be inside the preview card.
  ///
  /// The card is [_PageHero._height] tall and loses its own padding twice
  /// over, leaving a little under 300 logical pixels. A picture allowed the
  /// full-page 360 would be the only thing in the card and the writing after it
  /// would never appear; at 140 a page reads as what it is — words, then the
  /// photograph, then more words.
  static const double _previewImageHeight = 140;

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
          // Rendered, and clipped rather than ellipsised: this is a glance at
          // the page, and it used to be a glance at its markup — heading
          // hashes, bold asterisks and the file name of every picture.
          //
          // Pictures are drawn, not named. They were captioned here on the
          // reasoning that a thumbnail in a card this size shows nothing and
          // the full-screen viewer is one tap away. On a real phone that reads
          // as a document that lost its photograph: the preview is where you
          // look to check what you just saved, and a "Picture" chip where the
          // picture should be looks like the picture is gone. Smaller than on a
          // full page, so the writing around it still shows — see
          // [_previewImageHeight].
          //
          // Laid out unbounded and then clipped, rather than squeezed into the
          // card's height. A `Column` given a height smaller than its children
          // overflows — the yellow-and-black stripe — where a scroll view with
          // scrolling switched off gives it the room to lay out and trims what
          // does not fit.
          ? SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: MarkupView(
                text: page.text,
                documentId: documentId,
                maxBlocks: 8,
                imageMaxHeight: _previewImageHeight,
              ),
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
