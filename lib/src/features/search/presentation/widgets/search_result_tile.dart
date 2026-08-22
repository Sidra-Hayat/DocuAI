import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../documents/presentation/widgets/document_thumbnail.dart';
import '../../../documents/presentation/widgets/library_navigation.dart';
import '../../domain/entities/search_hit.dart';
import '../providers/search_providers.dart';

/// One document that matched, and the passages inside it that did.
///
/// Grouped rather than flat. A bill whose text matches on two pages used to
/// render as one row with two excerpts stacked in it and no way to reach
/// either; now the document is a heading and each matching page is its own
/// tappable line that opens *that page*. Finding the words was never the task —
/// getting to them was.
class SearchResultTile extends ConsumerWidget {
  const SearchResultTile({required this.hit, required this.query, super.key});

  final SearchHit hit;

  /// Remembered when the user opens something, which is the moment a query is
  /// known to have been worth typing.
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    void remember() =>
        ref.read(recentSearchesProvider.notifier).remember(query);

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            onTap: () {
              remember();
              // Titles are indexed, so an archive is findable by its file name
              // — and a hit that opened a pager with no pages in it would be a
              // search that found the right thing and then lost it.
              openLibraryItem(context, ref, hit.document);
            },
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DocumentThumbnail(
                    page: hit.document.coverPage,
                    width: 44,
                    height: 58,
                    borderRadius: AppRadius.sm,
                  ),
                  AppSpacing.gapHorizontalMd,
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          hit.document.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        AppSpacing.gapXs,
                        Text(
                          _why(hit),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          for (final snippet in hit.snippets)
            _SnippetRow(
              documentId: hit.document.id,
              snippet: snippet,
              onOpen: remember,
            ),
          AppSpacing.gapSm,
        ],
      ),
    );
  }

  /// Says why this document is in the list, in words rather than in a badge.
  ///
  /// The old row carried a coloured chip reading "Exact title", "Content" or
  /// "Tag" — the names of the ranking buckets, which is information about the
  /// search engine rather than about the document. What a person needs to know
  /// is why *this* is here when the words are not visible in the excerpts, and
  /// that is only worth saying when there are no excerpts to speak for it.
  static String _why(SearchHit hit) {
    if (hit.snippets.isNotEmpty) {
      final pages = hit.snippets.length;
      final where = pages == 1 ? '1 page' : '$pages pages';
      return hit.matchedTags.isEmpty
          ? 'Found on $where'
          : 'Found on $where · tagged '
                '${hit.matchedTags.map((tag) => '#$tag').join(', ')}';
    }

    if (hit.matchedTags.isNotEmpty) {
      return 'Matched the tag '
          '${hit.matchedTags.map((tag) => '#$tag').join(', ')}';
    }

    return 'Matched the title';
  }
}

/// One matching passage, on the page it came from.
class _SnippetRow extends StatelessWidget {
  const _SnippetRow({
    required this.documentId,
    required this.snippet,
    required this.onOpen,
  });

  final String documentId;
  final SearchSnippet snippet;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.45,
    );

    return InkWell(
      onTap: () {
        onOpen();
        // Straight to the page, not to the document. The excerpt is a promise
        // that the words are on page three; landing on page one makes the user
        // find them a second time.
        context.pushNamed(
          AppRoutes.pageViewerName,
          pathParameters: <String, String>{
            'id': documentId,
            'page': '${snippet.pageIndex}',
          },
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.xs,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 56,
              child: Text(
                'Page ${snippet.pageIndex + 1}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: _Excerpt(snippet: snippet, style: body),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _Excerpt extends StatelessWidget {
  const _Excerpt({required this.snippet, required this.style});

  final SearchSnippet snippet;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // An index written by an older version can disagree with the current text,
    // so an out-of-range highlight renders as plain text rather than throwing a
    // RangeError inside build.
    if (!snippet.hasValidHighlight) {
      return Text(
        snippet.text,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }

    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          TextSpan(text: snippet.text.substring(0, snippet.highlightStart)),
          TextSpan(
            text: snippet.text.substring(
              snippet.highlightStart,
              snippet.highlightEnd,
            ),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
              backgroundColor: theme.colorScheme.primaryContainer,
            ),
          ),
          TextSpan(text: snippet.text.substring(snippet.highlightEnd)),
        ],
      ),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}
