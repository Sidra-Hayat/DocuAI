import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_empty_state.dart';
import '../../domain/entities/search_hit.dart';
import '../providers/search_providers.dart';
import '../widgets/search_result_tile.dart';

/// Full-text search across every document's recognised text.
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

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watched for its side effect: it reconciles the index with the library
    // before the first query can run against a stale one.
    ref.watch(searchIndexReadyProvider);

    final state = ref.watch(searchQueryControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _field,
              autocorrect: false,
              textInputAction: TextInputAction.search,
              onChanged: ref.read(searchQueryControllerProvider.notifier).onQueryChanged,
              onSubmitted: ref.read(searchQueryControllerProvider.notifier).run,
              decoration: InputDecoration(
                hintText: 'Search documents, text, or tags',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: state.query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _field.clear();
                          ref.read(searchQueryControllerProvider.notifier).clear();
                        },
                      ),
              ),
            ),
          ),
          Expanded(child: _Results(state: state)),
        ],
      ),
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.state});

  final SearchState state;

  @override
  Widget build(BuildContext context) {
    if (!state.hasQuery) {
      return const AppEmptyState(
        icon: Icons.manage_search_outlined,
        title: 'Find documents',
        message:
            'Search by document name, by a tag, or by any words inside the '
            'pages. Results show which of those matched.\n\n'
            'Looking for an answer rather than a document? The Assistant tab '
            'reads your pages and replies with the passage that answers you.',
      );
    }

    return state.results.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => const AppEmptyState(
        icon: Icons.error_outline,
        title: 'Search is unavailable',
        message:
            'The search index could not be read. Reopening DocuAI rebuilds it.',
      ),
      data: (hits) => hits.isEmpty
          ? _NoMatches(query: state.query.trim())
          : _HitList(hits: hits),
    );
  }
}

class _HitList extends StatelessWidget {
  const _HitList({required this.hits});

  final List<SearchHit> hits;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: hits.length,
      separatorBuilder: (context, index) => const Divider(height: 1, indent: 80),
      itemBuilder: (context, index) => SearchResultTile(hit: hits[index]),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.search_off_outlined,
      title: 'No matches for "$query"',
      // Naming the most likely cause, because a document whose text was never
      // recognised is invisible to search and nothing on this screen would
      // explain why.
      message:
          'Names and tags are always searchable. Page text is searchable once '
          'it has been recognised — open a document to read its pages if that '
          'has not happened yet.',
    );
  }
}
