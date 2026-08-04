import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../domain/entities/assistant_answer.dart';
import '../../domain/entities/chat_message.dart';

/// One turn in the transcript.
class ChatBubble extends StatelessWidget {
  const ChatBubble({required this.message, super.key});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fromUser = message.isFromUser;

    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.85,
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
                  height: 1.4,
                ),
              ),
            ),
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

/// Where an answer came from.
///
/// Every citation is tappable and opens its document. An answer the user cannot
/// verify is worth much less than one they can, and a quotation with no route
/// back to the page it came from is exactly that.
class _Citations extends StatelessWidget {
  const _Citations({required this.citations});

  final List<AnswerCitation> citations;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            citations.length == 1 ? 'From this document' : 'From your documents',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final citation in citations)
                ActionChip(
                  avatar: const Icon(Icons.description_outlined, size: 16),
                  label: Text(
                    '${citation.documentTitle} · ${citation.pageLabel}',
                  ),
                  tooltip: citation.snippet,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => context.pushNamed(
                    AppRoutes.documentDetailName,
                    pathParameters: {'id': citation.documentId},
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
