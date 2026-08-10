import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_search_field.dart';
import '../../../../core/widgets/app_section_header.dart';
import '../../../../core/widgets/app_skeleton.dart';
import '../../../../core/widgets/app_state_view.dart';
import '../../domain/entities/document.dart';
import '../providers/document_providers.dart';
import '../widgets/document_card.dart';
import '../widgets/document_thumbnail.dart';
import '../widgets/library_header.dart';
import '../widgets/new_document_sheet.dart';

/// The document library — the app's home and its workspace.
///
/// It used to be one flat list and nothing else. A workspace has to answer more
/// than "what do I own": what was I last working on, where do I search, which
/// of these did I mark, and how do I add another. Those are the four things
/// this screen now leads with, in that order.
///
/// Reads one stream and renders its three states. Because the stream is fed by
/// `box.watch()`, a rename or delete performed anywhere in the app redraws this
/// list without it knowing anything happened.
class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  _LibraryFilter _filter = _LibraryFilter.all;

  @override
  Widget build(BuildContext context) {
    final documents = ref.watch(documentsProvider);

    return Scaffold(
      appBar: const LibraryAppBar(),
      body: documents.when(
        data: (items) => items.isEmpty
            ? const _EmptyLibrary()
            : _Library(
                documents: items,
                filter: _filter,
                onFilter: (filter) => setState(() => _filter = filter),
              ),
        // Shaped like the list that is coming, so nothing shifts under a
        // thumb already moving when the data lands.
        loading: () => const AppListSkeleton(),
        // Storage failing is not something the user can fix, so this states
        // what happened rather than suggesting an action that would not help.
        error: (error, stackTrace) => const AppStateView.problem(
          icon: Icons.error_outline,
          title: 'Could not open your library',
          message:
              'The document database could not be read. Restarting DocuAI '
              'usually clears this.',
        ),
      ),
      // The app's one creation button, on the app's one screen that has
      // somewhere to put a new document. It is deliberately not in the shell:
      // there is nothing to create on Search, and what the assistant creates is
      // a conversation.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showNewDocumentSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('New document'),
        tooltip: 'Scan, import or write a document',
      ),
    );
  }
}

/// How the library is being narrowed.
///
/// Presentation state, held by the screen rather than by a provider: it
/// describes what this screen is showing right now, not anything the rest of
/// the app or the next launch has any business knowing.
enum _LibraryFilter {
  all('All'),
  favourites('Favourites'),
  scanned('Scanned'),
  written('Written');

  const _LibraryFilter(this.label);

  final String label;

  bool matches(Document document) => switch (this) {
    _LibraryFilter.all => true,
    _LibraryFilter.favourites => document.isFavorite,
    _LibraryFilter.scanned =>
      document.source == DocumentSource.scanned ||
          document.source == DocumentSource.imported,
    _LibraryFilter.written => document.source == DocumentSource.created,
  };
}

class _Library extends StatelessWidget {
  const _Library({
    required this.documents,
    required this.filter,
    required this.onFilter,
  });

  final List<Document> documents;
  final _LibraryFilter filter;
  final ValueChanged<_LibraryFilter> onFilter;

  /// Recent is only worth a row of its own when the list below is long enough
  /// that the newest documents are not already the first thing visible.
  static const int _recentThreshold = 4;

  @override
  Widget build(BuildContext context) {
    final visible = documents.where(filter.matches).toList(growable: false);

    final showRecent =
        filter == _LibraryFilter.all && documents.length >= _recentThreshold;
    final recent = documents.take(5).toList(growable: false);

    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            // Not a working field: it is the Search tab's field, in the place
            // the eye already goes, and tapping it lands there with the
            // keyboard up. Duplicating the search *engine* here would give the
            // app two searches to keep in step.
            child: AppSearchField.button(
              hintText: 'Find documents, text, or tags',
              onTap: () => context.goNamed(AppRoutes.searchName),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _Filters(selected: filter, onSelected: onFilter),
        ),
        if (showRecent) ...<Widget>[
          const SliverToBoxAdapter(child: AppSectionHeader(label: 'Recent')),
          SliverToBoxAdapter(child: _RecentRow(documents: recent)),
        ],
        SliverToBoxAdapter(
          child: AppSectionHeader(
            label: filter == _LibraryFilter.all
                ? 'All documents'
                : filter.label,
            action: Text(
              '${visible.length}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        if (visible.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _NothingInFilter(filter: filter),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.fabClearance,
            ),
            sliver: SliverList.separated(
              itemCount: visible.length,
              separatorBuilder: (context, index) => AppSpacing.gapSm,
              itemBuilder: (context, index) =>
                  DocumentCard(document: visible[index]),
            ),
          ),
      ],
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({required this.selected, required this.onSelected});

  final _LibraryFilter selected;
  final ValueChanged<_LibraryFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Row(
        children: <Widget>[
          for (final filter in _LibraryFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: FilterChip(
                label: Text(filter.label),
                selected: filter == selected,
                showCheckmark: false,
                onSelected: (_) => onSelected(filter),
              ),
            ),
        ],
      ),
    );
  }
}

/// The five most recently touched, as pages rather than as rows.
///
/// Shown large enough to be recognised by sight. The whole reason to repeat
/// documents that are also in the list below is that a thumbnail you can
/// actually see is faster to find than a title you have to read.
class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.documents});

  final List<Document> documents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 176,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: documents.length,
        separatorBuilder: (context, index) => AppSpacing.gapHorizontalMd,
        itemBuilder: (context, index) {
          final document = documents[index];

          return SizedBox(
            width: 108,
            child: InkWell(
              borderRadius: AppRadius.card,
              onTap: () => context.pushNamed(
                AppRoutes.documentDetailName,
                pathParameters: <String, String>{'id': document.id},
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Stack(
                    children: <Widget>[
                      DocumentThumbnail(
                        page: document.coverPage,
                        width: 108,
                        height: 130,
                        borderRadius: AppRadius.md,
                      ),
                      if (document.isFavorite)
                        Positioned(
                          top: AppSpacing.xs,
                          right: AppSpacing.xs,
                          child: Icon(
                            Icons.star,
                            size: 16,
                            color: theme.colorScheme.tertiary,
                          ),
                        ),
                    ],
                  ),
                  AppSpacing.gapSm,
                  Text(
                    document.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(height: 1.2),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A filter that matched nothing.
///
/// Distinct from an empty library: there *are* documents, just none of this
/// kind, and offering "scan your first document" here would be answering a
/// question nobody asked.
class _NothingInFilter extends StatelessWidget {
  const _NothingInFilter({required this.filter});

  final _LibraryFilter filter;

  @override
  Widget build(BuildContext context) {
    return AppStateView(
      icon: switch (filter) {
        _LibraryFilter.favourites => Icons.star_border_outlined,
        _LibraryFilter.written => Icons.edit_note_outlined,
        _ => Icons.folder_outlined,
      },
      title: switch (filter) {
        _LibraryFilter.favourites => 'No favourites yet',
        _LibraryFilter.scanned => 'Nothing scanned or imported yet',
        _LibraryFilter.written => 'Nothing written yet',
        _LibraryFilter.all => 'No documents yet',
      },
      message: switch (filter) {
        _LibraryFilter.favourites =>
          'Star a document and it will be waiting here.',
        _ => 'Use the button below to add one.',
      },
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return AppStateView(
      icon: Icons.folder_copy_outlined,
      title: 'No documents yet',
      message:
          'Scan a page, bring in photos, or write one yourself. Everything '
          'stays on this device, and all of it is searchable.',
      action: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        alignment: WrapAlignment.center,
        children: <Widget>[
          FilledButton.icon(
            onPressed: () => context.pushNamed(AppRoutes.scanName),
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Scan a document'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => importPhotosAsDocument(context),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Import'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => createAndOpenTextDocument(context),
            icon: const Icon(Icons.edit_note_outlined),
            label: const Text('Write one'),
          ),
        ],
      ),
    );
  }
}
