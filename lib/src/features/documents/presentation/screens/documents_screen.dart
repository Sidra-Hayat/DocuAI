import 'dart:async';

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
      //
      // Withheld until there is a library. The empty state already offers Scan,
      // Import and Write as full-sized buttons in the middle of the screen, and
      // a floating "+ New document" over them makes the same offer twice — on
      // the one screen where the user has not yet done anything and the choice
      // should be as small as possible.
      //
      // `?? false` covers loading and failure as well as empty: while the
      // skeleton is up there is no library to add to yet, and when storage
      // could not be read, offering to write to it is offering something that
      // will not work.
      floatingActionButton: (documents.value?.isNotEmpty ?? false)
          ? FloatingActionButton.extended(
              onPressed: () => showNewDocumentSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('New document'),
              tooltip: 'Scan, import or write a document',
            )
          : null,
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
          _EmptyAction(
            caption: 'Capture a page with your camera',
            child: FilledButton.icon(
              onPressed: () => _scanAfterExplainingTheCamera(context),
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Scan a document'),
            ),
          ),
          _EmptyAction(
            // The caption no longer names photos: this button now asks which
            // kind of import is meant, because the file importer's only other
            // door is the New document sheet that this screen hides.
            caption: 'Bring in a photo or a file',
            child: FilledButton.tonalIcon(
              onPressed: () => chooseImportSource(context),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Import'),
            ),
          ),
          _EmptyAction(
            caption: 'Type a document yourself',
            child: FilledButton.tonalIcon(
              onPressed: () => createAndOpenTextDocument(context),
              icon: const Icon(Icons.edit_note_outlined),
              label: const Text('Write one'),
            ),
          ),
        ],
      ),
    );
  }
}

/// One empty-state button with a line underneath saying what it does.
///
/// Three buttons named "Scan a document", "Import" and "Write one" say what
/// they are but not what happens next — whether Import means photos or files,
/// or whether Write one opens a keyboard or a template. The caption answers
/// that before the tap rather than after it.
class _EmptyAction extends StatelessWidget {
  const _EmptyAction({required this.child, required this.caption});

  final Widget child;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ConstrainedBox(
      // A ceiling, not a height. The caption wraps to as many lines as it needs
      // and the column grows with it, so the largest system font size makes
      // this taller rather than making it overflow — and the panel this sits in
      // scrolls, so taller is always available.
      constraints: const BoxConstraints(maxWidth: 176),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          child,
          AppSpacing.gapXs,
          Text(
            caption,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Says what the camera is for, immediately before anything opens it.
///
/// DocuAI declares no camera permission of its own: scanning runs inside Play
/// services' document scanner, which asks for the camera under its own name at
/// the moment it opens. That is exactly the moment this is worth explaining —
/// a system dialog naming Google Play services, arriving with no warning after
/// a tap on "Scan a document", is the point at which a privacy-first app looks
/// like it is doing something else.
///
/// Nothing is requested here and nothing is requested any earlier than before:
/// this is a sentence and a button, and declining it simply does not scan.
Future<void> _scanAfterExplainingTheCamera(BuildContext context) async {
  final proceed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.photo_camera_outlined),
      title: const Text('Scan with the camera'),
      content: const Text(
        'The camera is only used to scan document pages. Your photos are not '
        'uploaded — every page stays on this device.',
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Continue'),
        ),
      ],
    ),
  );

  if (proceed != true || !context.mounted) return;
  // Nothing here waits for the scanner to come back; the library redraws from
  // storage when a document lands in it.
  unawaited(context.pushNamed(AppRoutes.scanName));
}
