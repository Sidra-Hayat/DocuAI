import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../documents/presentation/widgets/document_thumbnail.dart';
import '../../domain/entities/search_hit.dart';

/// One match in the results list: which document, and the passages that
/// matched.
class SearchResultTile extends StatelessWidget {
  const SearchResultTile({required this.hit, super.key});

  final SearchHit hit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: () => context.pushNamed(
        AppRoutes.documentDetailName,
        pathParameters: {'id': hit.document.id},
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DocumentThumbnail(page: hit.document.coverPage),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hit.document.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _MatchBadge(hit: hit),
                  const SizedBox(height: 6),
                  if (hit.snippets.isEmpty)
                    Text(
                      hit.matchedTags.isEmpty
                          ? 'Matched the title'
                          : 'Matched the tag '
                                '${hit.matchedTags.map((t) => '#$t').join(', ')}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    )
                  else
                    for (final snippet in hit.snippets) ...[
                      _Snippet(snippet: snippet),
                      const SizedBox(height: 6),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Says where the match came from.
///
/// Results are ordered by match kind, so without a badge the order looks
/// arbitrary — a document whose title matched sitting above one with the query
/// all over its pages reads as a bug until you can see why.
class _MatchBadge extends StatelessWidget {
  const _MatchBadge({required this.hit});

  final SearchHit hit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final colour = switch (hit.kind) {
      SearchMatchKind.exactTitle ||
      SearchMatchKind.partialTitle => theme.colorScheme.primary,
      SearchMatchKind.content => theme.colorScheme.onSurfaceVariant,
      SearchMatchKind.tag => theme.colorScheme.tertiary,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: colour.withValues(alpha: .45)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        hit.kind.label,
        style: theme.textTheme.labelSmall?.copyWith(color: colour),
      ),
    );
  }
}

class _Snippet extends StatelessWidget {
  const _Snippet({required this.snippet});

  final SearchSnippet snippet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.4,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Page ${snippet.pageIndex + 1}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 2),
        // An index written by an older version can disagree with the current
        // text, so an out-of-range highlight renders as plain text rather than
        // throwing a RangeError inside build.
        if (!snippet.hasValidHighlight)
          Text(snippet.text, maxLines: 3, overflow: TextOverflow.ellipsis, style: body)
        else
          Text.rich(
            TextSpan(
              children: [
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
            style: body,
          ),
      ],
    );
  }
}
