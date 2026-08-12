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
import '../widgets/library_actions.dart';
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

/// The library, in the order someone reads it.
///
/// Search, then how to add something, then the tools, then what you already
/// have. That order is the change: the screen used to open with a search field
/// and a row of filter chips over a flat list, so the four ways of getting a
/// document *in* were behind a single "+" and the things you could do with one
/// were invisible until you opened it.
///
/// Recent documents appear once. There used to be a horizontal "Recent" strip
/// above an "All documents" list that began with the same five documents —
/// the newest documents rendered twice, a few hundred pixels apart, which is
/// two answers to "what was I last working on".
class _Library extends StatelessWidget {
  const _Library({
    required this.documents,
    required this.filter,
    required this.onFilter,
  });

  final List<Document> documents;
  final _LibraryFilter filter;
  final ValueChanged<_LibraryFilter> onFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = documents.where(filter.matches).toList(growable: false);

    return CustomScrollView(
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.lg,
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
        const SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          sliver: SliverToBoxAdapter(child: LibraryPrimaryActions()),
        ),
        const SliverPadding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            0,
          ),
          sliver: SliverToBoxAdapter(child: LibraryTools()),
        ),
        SliverToBoxAdapter(
          child: AppSectionHeader(
            // Named for what it is only when it *is* that. Under a filter the
            // list is no longer "recent anything" — it is every favourite, or
            // everything written — and a heading that said otherwise would be
            // describing a list the user is not looking at.
            label: filter == _LibraryFilter.all
                ? 'Recent documents'
                : filter.label,
            action: Text(
              '${visible.length}',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: _Filters(selected: filter, onSelected: onFilter),
        ),
        AppSpacing.gapMd.asSliver,
        if (visible.isEmpty)
          SliverToBoxAdapter(child: _NothingInFilter(filter: filter))
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

/// Puts a plain widget in a sliver list without a wrapper at every call site.
extension on Widget {
  Widget get asSliver => SliverToBoxAdapter(child: this);
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
