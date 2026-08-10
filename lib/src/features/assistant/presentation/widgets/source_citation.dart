import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../documents/presentation/providers/document_providers.dart';
import '../../domain/entities/assistant_answer.dart';

/// Where an answer came from.
///
/// Compact by default and expandable, which is the whole change. Every answer
/// used to arrive with a bordered card per document carrying a three-line
/// excerpt and a row of chips listing the words that matched — a retrieval
/// trace, printed in full, under every reply. The traceability is the point of
/// this assistant and is kept; showing all of it at rest is what made the
/// answers look like output from an index inspector.
///
/// So: one line naming the document and the page, tappable to open that page,
/// with the excerpt one tap further in for anyone who wants to check.
class SourceCitation extends StatelessWidget {
  const SourceCitation({required this.citations, super.key});

  final List<AnswerCitation> citations;

  @override
  Widget build(BuildContext context) {
    if (citations.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);

    final grouped = <String, List<AnswerCitation>>{};
    for (final citation in citations) {
      grouped
          .putIfAbsent(citation.documentId, () => <AnswerCitation>[])
          .add(citation);
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            grouped.length == 1 ? 'SOURCE' : 'SOURCES',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1,
              fontWeight: FontWeight.w700,
            ),
          ),
          AppSpacing.gapXs,
          for (final entry in grouped.entries)
            _Source(documentId: entry.key, citations: entry.value),
        ],
      ),
    );
  }
}

class _Source extends ConsumerStatefulWidget {
  const _Source({required this.documentId, required this.citations});

  final String documentId;
  final List<AnswerCitation> citations;

  @override
  ConsumerState<_Source> createState() => _SourceState();
}

class _SourceState extends ConsumerState<_Source> {
  bool _expanded = false;

  /// Opens the page the answer was lifted from.
  ///
  /// A transcript records the page number as it was when the question was
  /// asked, and pages can be deleted afterwards. Rather than pushing a viewer
  /// at a page that no longer exists — which renders as a blank screen — the
  /// index is checked against the document as it stands now, and a citation
  /// that has outlived its page opens the document instead.
  void _open(int pageIndex) {
    final document = ref.read(documentProvider(widget.documentId)).value;

    if (document == null || !document.hasPages) {
      context.pushNamed(
        AppRoutes.documentDetailName,
        pathParameters: <String, String>{'id': widget.documentId},
      );
      return;
    }

    final page = pageIndex.clamp(0, document.pageCount - 1);
    context.pushNamed(
      AppRoutes.pageViewerName,
      pathParameters: <String, String>{
        'id': widget.documentId,
        'page': '$page',
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = widget.citations.first;
    final pages = widget.citations
        .map((citation) => citation.pageLabel)
        .join(', ');

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: AppRadius.card,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            InkWell(
              onTap: () => _open(first.pageIndex),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.xs,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.description_outlined,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    AppSpacing.gapHorizontalSm,
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            first.documentTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge,
                          ),
                          Text(
                            pages,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: _expanded
                          ? 'Hide the passage'
                          : 'Show the passage',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _expanded = !_expanded),
                    ),
                  ],
                ),
              ),
            ),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final citation in widget.citations) ...<Widget>[
                      Text(
                        citation.snippet,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                      AppSpacing.gapSm,
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
