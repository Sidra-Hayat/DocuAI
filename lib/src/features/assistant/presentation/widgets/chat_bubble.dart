import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/assistant_answer.dart';
import '../../domain/entities/chat_message.dart';

/// One turn in the transcript.
class ChatBubble extends StatelessWidget {
  const ChatBubble({required this.message, this.answer, super.key});

  final ChatMessage message;

  /// The full answer, when this bubble is the most recent assistant turn.
  ///
  /// Confidence and the searched-document count are not persisted with the
  /// transcript — they describe how *this* run went, and replaying them
  /// against a library that has since changed would be a claim nobody checked.
  final AssistantAnswer? answer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fromUser = message.isFromUser;

    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.88,
        ),
        child: Column(
          crossAxisAlignment: fromUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: _background(theme, message),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(fromUser ? 16 : 4),
                  bottomRight: Radius.circular(fromUser ? 4 : 16),
                ),
              ),
              child: Text(
                message.hasFailed ? message.errorMessage! : message.text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: _foreground(theme, message),
                  height: 1.45,
                ),
              ),
            ),
            if (!fromUser && answer != null) _AnswerMeta(answer: answer!),
            if (message.citations.isNotEmpty)
              _Citations(citations: message.citations),
          ],
        ),
      ),
    );
  }

  static Color _background(ThemeData theme, ChatMessage message) {
    if (message.hasFailed) return theme.colorScheme.errorContainer;
    return message.isFromUser
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHighest;
  }

  static Color _foreground(ThemeData theme, ChatMessage message) {
    if (message.hasFailed) return theme.colorScheme.onErrorContainer;
    return message.isFromUser
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;
  }
}

/// How well the quote answered, and how much was read to find it.
class _AnswerMeta extends StatelessWidget {
  const _AnswerMeta({required this.answer});

  final AssistantAnswer answer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final confidence = answer.confidence;

    final parts = <String>[
      if (answer.documentsSearched > 0)
        'Searched ${answer.documentsSearched} '
            '${answer.documentsSearched == 1 ? 'document' : 'documents'}',
      if (answer.spansMultipleDocuments)
        'across ${answer.citedDocumentIds.length}',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
      child: Row(
        children: [
          if (confidence != null) ...[
            _ConfidenceChip(confidence: confidence),
            const SizedBox(width: 8),
          ],
          if (parts.isNotEmpty)
            Flexible(
              child: Text(
                parts.join(' · '),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

/// Says "match", never "confident".
///
/// The engine knows how much of the question the passage covered. It knows
/// nothing about whether the document is correct, and the label must not imply
/// otherwise.
class _ConfidenceChip extends StatelessWidget {
  const _ConfidenceChip({required this.confidence});

  final AnswerConfidence confidence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (label, colour, tooltip) = switch (confidence) {
      AnswerConfidence.strong => (
        'Strong match',
        theme.colorScheme.primary,
        'The passage contained every part of your question.',
      ),
      AnswerConfidence.partial => (
        'Partial match',
        theme.colorScheme.tertiary,
        'The passage covered some of your question. Check the source.',
      ),
      AnswerConfidence.weak => (
        'Weak match',
        theme.colorScheme.outline,
        'This was the closest passage, but it covered little of your '
            'question.',
      ),
    };

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          border: Border.all(color: colour.withValues(alpha: .5)),
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: colour),
        ),
      ),
    );
  }
}

/// Where an answer came from, grouped by document.
///
/// Each source shows the page, the words that matched, and the surrounding
/// text — so the citation explains *why* it was cited, not only where it came
/// from. Tapping opens the document.
class _Citations extends StatelessWidget {
  const _Citations({required this.citations});

  final List<AnswerCitation> citations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grouped = <String, List<AnswerCitation>>{};
    for (final citation in citations) {
      grouped
          .putIfAbsent(citation.documentId, () => <AnswerCitation>[])
          .add(citation);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            grouped.length == 1 ? 'Source' : 'Sources',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: .8,
            ),
          ),
          const SizedBox(height: 6),
          for (final entry in grouped.entries)
            _SourceCard(
              documentId: entry.key,
              citations: entry.value,
            ),
        ],
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({required this.documentId, required this.citations});

  final String documentId;
  final List<AnswerCitation> citations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = citations.first.documentTitle;
    final pages = citations.map((citation) => citation.pageLabel).join(', ');

    final terms = <String>{
      for (final citation in citations) ...citation.matchedTerms,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => context.pushNamed(
          AppRoutes.documentDetailName,
          pathParameters: {'id': documentId},
        ),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  Text(
                    pages,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                citations.first.snippet,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              if (terms.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final term in terms)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        child: Text(
                          term,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
