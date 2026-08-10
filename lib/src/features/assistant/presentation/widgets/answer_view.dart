import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/chat_message.dart';
import 'answer_copy.dart';
import 'source_citation.dart';

/// One turn in the conversation.
///
/// The two sides are drawn differently on purpose. A question is a bubble,
/// right-aligned, because it is something the user said. An answer is not:
/// it is a passage out of the user's own papers, and setting it as running text
/// on the page — the way the document it came from is set — says that better
/// than a grey speech balloon does.
class ChatTurn extends StatelessWidget {
  const ChatTurn({required this.message, super.key});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    return message.isFromUser
        ? _Question(message: message)
        : _Answer(message: message);
  }
}

class _Question extends StatelessWidget {
  const _Question({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.82,
        ),
        child: Container(
          margin: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(AppRadius.lg),
              topRight: Radius.circular(AppRadius.lg),
              bottomLeft: Radius.circular(AppRadius.lg),
              bottomRight: Radius.circular(AppRadius.xs),
            ),
          ),
          child: Text(
            message.text,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onPrimaryContainer,
              height: 1.45,
            ),
          ),
        ),
      ),
    );
  }
}

class _Answer extends StatelessWidget {
  const _Answer({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (message.hasFailed) {
      return Container(
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: AppRadius.card,
        ),
        child: Text(
          message.errorMessage!,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onErrorContainer,
            height: 1.45,
          ),
        ),
      );
    }

    // Translated at the point of display; the stored transcript is untouched.
    final text = AnswerCopy.forDisplay(message.text);
    final hint = AnswerCopy.hintFor(message.text);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // The answer, first and unqualified. Everything that used to sit
          // between the reply and the reader — a match-strength chip, a count
          // of documents searched — described the search rather than the
          // answer, and is gone.
          SelectionArea(
            child: Text(
              text,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.55),
            ),
          ),
          if (hint != null) ...<Widget>[
            AppSpacing.gapSm,
            Text(
              hint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
          SourceCitation(citations: message.citations),
        ],
      ),
    );
  }
}
