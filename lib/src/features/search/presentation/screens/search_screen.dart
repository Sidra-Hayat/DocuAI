import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_search_field.dart';
import '../../../../core/widgets/app_section_header.dart';
import '../../../../core/widgets/app_state_view.dart';
import '../../domain/entities/search_hit.dart';
import '../providers/search_providers.dart';
import '../widgets/search_result_tile.dart';

/// Find a document, a page, or the words on it.
///
/// Search finds; the assistant explains. The two used to be hard to tell apart
/// — both a bare app-bar title over one centred panel of identical weight, each
/// of whose empty states spent a paragraph describing the other tab. This one
/// leads with the field, because a screen whose whole purpose is a query should
/// look like somewhere to type one.
///
/// Typing is debounced by `AppConstants.searchDebounce` — the index is fast
/// enough to query on every keystroke, but re-rendering a result list that
/// changes shape under the user's fingers is worse than waiting a moment for
/// one that holds still.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _field = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _field.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _search(String query) {
    _field.text = query;
    _field.selection = TextSelection.collapsed(offset: query.length);
    ref.read(searchQueryControllerProvider.notifier).run(query);
    _focus.unfocus();
  }

  void _submit(String query) {
    ref.read(recentSearchesProvider.notifier).remember(query);
    ref.read(searchQueryControllerProvider.notifier).run(query);
  }

  void _clear() {
    _field.clear();
    ref.read(searchQueryControllerProvider.notifier).clear();
  }

  @override
  Widget build(BuildContext context) {
    // Watched for its side effect: it reconciles the index with the library
    // before the first query can run against a stale one.
    ref.watch(searchIndexReadyProvider);

    final state = ref.watch(searchQueryControllerProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: AppSearchField(
                controller: _field,
                focusNode: _focus,
                hintText: 'Find documents, text, or tags',
                hasText: state.query.isNotEmpty,
                onChanged: ref
                    .read(searchQueryControllerProvider.notifier)
                    .onQueryChanged,
                onSubmitted: _submit,
                onClear: _clear,
              ),
            ),
            Expanded(
              child: _Results(state: state, onSearch: _search),
            ),
          ],
        ),
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.state, required this.onSearch});

  final SearchState state;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    if (!state.hasQuery) return _Suggestions(onSearch: onSearch);

    return state.results.when(
      loading: () => const AppStateView.busy(title: 'Searching…'),
      error: (error, stackTrace) => const AppStateView.problem(
        icon: Icons.error_outline,
        title: 'Search is unavailable',
        message:
            'The list of words in your documents could not be read. Reopening '
            'DocuAI rebuilds it.',
      ),
      data: (hits) => hits.isEmpty
          ? _NoMatches(query: state.query.trim())
          : _HitList(hits: hits, query: state.query.trim()),
    );
  }
}

class _HitList extends StatelessWidget {
  const _HitList({required this.hits, required this.query});

  final List<SearchHit> hits;
  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pages = hits.fold<int>(0, (sum, hit) => sum + hit.snippets.length);

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      itemCount: hits.length + 1,
      separatorBuilder: (context, index) => AppSpacing.gapSm,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              pages == 0
                  ? '${hits.length} ${hits.length == 1 ? 'document' : 'documents'}'
                  : '$pages ${pages == 1 ? 'page' : 'pages'} in '
                        '${hits.length} '
                        '${hits.length == 1 ? 'document' : 'documents'}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }

        return SearchResultTile(hit: hits[index - 1], query: query);
      },
    );
  }
}

/// What to offer before anything has been typed.
///
/// The screen used to explain, in a paragraph, that the other tab exists. Tags
/// and earlier searches are more use than an explanation: they are one tap, and
/// they are made of the user's own words.
class _Suggestions extends ConsumerWidget {
  const _Suggestions({required this.onSearch});

  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recent = ref.watch(recentSearchesProvider);
    final tags = ref.watch(libraryTagsProvider);

    if (recent.isEmpty && tags.isEmpty) {
      return const AppStateView(
        icon: Icons.manage_search_outlined,
        title: 'Search your documents',
        message:
            'Type a name, a tag, or any words from inside the pages. Results '
            'show the page each one was found on.',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: <Widget>[
        if (recent.isNotEmpty) ...<Widget>[
          const AppSectionHeader(label: 'Recent searches'),
          _ChipRow(values: recent, icon: Icons.history, onSelected: onSearch),
        ],
        if (tags.isNotEmpty) ...<Widget>[
          const AppSectionHeader(label: 'Your tags'),
          _ChipRow(values: tags, label: (tag) => '#$tag', onSelected: onSearch),
        ],
      ],
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({
    required this.values,
    required this.onSelected,
    this.icon,
    this.label,
  });

  final List<String> values;
  final ValueChanged<String> onSelected;
  final IconData? icon;
  final String Function(String value)? label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: <Widget>[
          for (final value in values)
            ActionChip(
              avatar: icon == null ? null : Icon(icon, size: 16),
              label: Text(label == null ? value : label!(value)),
              onPressed: () => onSelected(value),
            ),
        ],
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return AppStateView(
      icon: Icons.search_off_outlined,
      title: 'Nothing found for "$query"',
      // Naming the most likely cause, because a document whose pages have not
      // been read yet is invisible to search and nothing on this screen would
      // otherwise explain why.
      message:
          'Names and tags are always searchable. The words inside a page can '
          'only be found once that page has been read — open a document to '
          'start that if it has not happened yet.',
    );
  }
}
