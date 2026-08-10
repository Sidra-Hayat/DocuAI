import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_state_view.dart';
import '../../domain/entities/assistant_intent.dart';
import '../../domain/entities/conversation.dart';
import '../assistant_intent_codec.dart';
import '../providers/assistant_providers.dart';

/// Every thread, newest first.
///
/// The Assistant tab lands here rather than in a chat, because one endless
/// transcript is not a record of anything: a question asked three weeks ago
/// about a different document is noise above today's, and there is no way to
/// put it away. A list makes each thread a thing you can return to, name by
/// what was asked, and delete on its own.
class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationsProvider(null));

    return Scaffold(
      appBar: AppBar(title: const Text('Assistant')),
      body: conversations.when(
        loading: () =>
            const AppStateView.busy(title: 'Opening your conversations…'),
        error: (error, stackTrace) => const AppStateView.problem(
          icon: Icons.error_outline,
          title: 'Your conversations could not be loaded',
        ),
        data: (threads) => threads.isEmpty
            ? _NoConversations(onStart: () => openNewConversation(context))
            : _ConversationList(conversations: threads),
      ),
      // A conversation, not a document. The library's creation button used to
      // float here too, offering to scan something on the screen whose only
      // creatable thing is a thread.
      floatingActionButton: conversations.value == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => openNewConversation(context),
              icon: const Icon(Icons.add_comment_outlined),
              label: const Text('New conversation'),
            ),
    );
  }
}

/// Opens a thread that does not exist yet.
///
/// The id is minted here rather than by the store, because a conversation with
/// nothing in it has no reason to be written down — it becomes real on the
/// first question, and is forgotten if none is asked.
Future<void> openNewConversation(
  BuildContext context, {
  String? documentId,
  String? documentTitle,
  AssistantIntent? intent,
}) {
  final query = <String, String>{
    'document': ?documentId,
    'title': ?documentTitle,
    // Encoded as an action token, never as the sentence it stands for. See
    // [AssistantIntentCodec].
    if (intent != null) ...AssistantIntentCodec.encode(intent),
  };

  return context.pushNamed<void>(
    AppRoutes.conversationName,
    pathParameters: <String, String>{'conversation': const Uuid().v4()},
    queryParameters: query,
  );
}

class _ConversationList extends ConsumerWidget {
  const _ConversationList({required this.conversations});

  final List<Conversation> conversations;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      padding: const EdgeInsets.only(
        top: AppSpacing.sm,
        bottom: AppSpacing.fabClearance,
      ),
      itemCount: conversations.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, indent: 72),
      itemBuilder: (context, index) =>
          _ConversationTile(conversation: conversations[index]),
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          conversation.isAboutOneDocument
              ? Icons.description_outlined
              : Icons.auto_awesome_outlined,
          size: 20,
          color: theme.colorScheme.primary,
        ),
      ),
      title: Text(
        conversation.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge,
      ),
      subtitle: Text(
        '${conversation.messageCount} '
        '${conversation.messageCount == 1 ? 'message' : 'messages'} · '
        '${DateFormat.yMMMd().add_jm().format(conversation.updatedAt)}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: IconButton(
        tooltip: 'Delete this conversation',
        icon: const Icon(Icons.delete_outline),
        onPressed: () => _confirmDelete(context, ref),
      ),
      onTap: () => context.pushNamed(
        AppRoutes.conversationName,
        pathParameters: <String, String>{'conversation': conversation.id},
        // ignore: use_null_aware_elements — the null-aware map entry form is
        // not available on this SDK; the conditional entry is the working one.
        queryParameters: <String, String>{
          if (conversation.documentId != null)
            'document': conversation.documentId!,
        },
      ),
    );
  }

  /// Read before the dialog is awaited, for the reason every other confirmed
  /// action here does: the row is gone by the time it resolves.
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final delete = ref.read(deleteConversationProvider);
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this conversation?'),
        content: Text(
          '"${conversation.title}" and everything in it is removed. Your '
          'documents are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final result = await delete(conversation.id);
    result.fold(
      onSuccess: (_) {},
      onFailure: (failure) =>
          messenger.showSnackBar(SnackBar(content: Text(failure.message))),
    );
  }
}

class _NoConversations extends StatelessWidget {
  const _NoConversations({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return AppStateView(
      icon: Icons.auto_awesome_outlined,
      title: 'Ask anything about your documents',
      message:
          'How much was the electricity bill? What are the important dates? '
          'Every answer comes from your own pages, and shows you where it came '
          'from.',
      action: FilledButton.icon(
        onPressed: onStart,
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('Start a conversation'),
      ),
    );
  }
}
