import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_empty_state.dart';
import '../../domain/entities/assistant_answer.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/usecases/ask_assistant.dart';
import '../providers/assistant_providers.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/question_chips.dart';
import '../widgets/thinking_indicator.dart';

/// Offline question answering over the user's own documents.
///
/// Answers are quoted from recognised text, never composed, so every reply can
/// be traced back to a page. The screen makes that visible: each answer carries
/// citation chips that open the document it came from.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({this.documentId, this.documentTitle, super.key});

  /// The document this conversation is about, or null for the library-wide
  /// one reached from the Assistant tab.
  final String? documentId;

  /// Shown in the bar so a scoped conversation says what it is scoped to.
  final String? documentTitle;

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final question = _composer.text;
    if (question.trim().isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    _composer.clear();

    final rejection = await ref
        .read(assistantControllerProvider.notifier)
        .ask(question, documentId: widget.documentId);

    // Only a question rejected before it was recorded needs telling; anything
    // else is already in the transcript as a failed turn.
    if (rejection != null) {
      messenger.showSnackBar(SnackBar(content: Text(rejection)));
    }
  }

  /// Asks a question the user picked rather than typed.
  ///
  /// Routed through the same path as the composer so a suggestion and a typed
  /// question cannot drift apart in validation or error handling.
  Future<void> _askNow(String question) async {
    _composer.clear();

    final messenger = ScaffoldMessenger.of(context);
    final rejection = await ref
        .read(assistantControllerProvider.notifier)
        .ask(question, documentId: widget.documentId);

    if (rejection != null) {
      messenger.showSnackBar(SnackBar(content: Text(rejection)));
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _confirmClear() async {
    final notifier = ref.read(assistantControllerProvider.notifier);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear conversation?'),
        content: const Text(
          'The questions and answers will be removed. Your documents are not '
          'affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed ?? false) {
      await notifier.clear(documentId: widget.documentId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = widget.documentId;
    final history = ref.watch(chatHistoryProvider(scope));
    final recent = ref.watch(recentQuestionsProvider(scope));
    final assistant = ref.watch(assistantControllerProvider);

    // Only this conversation's own run drives its progress.
    final busy = assistant.busy && assistant.scopeId == scope;

    ref.listen(
      chatHistoryProvider(scope),
      (previous, next) => _scrollToLatest(),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.documentTitle == null
              ? 'Assistant'
              : 'Ask ${widget.documentTitle}',
        ),
        actions: [
          if (recent.isNotEmpty && !busy)
            PopupMenuButton<String>(
              tooltip: 'Recent questions',
              icon: const Icon(Icons.history),
              onSelected: _askNow,
              itemBuilder: (context) => <PopupMenuEntry<String>>[
                for (final question in recent)
                  PopupMenuItem<String>(
                    value: question,
                    child: Text(question, maxLines: 2),
                  ),
              ],
            ),
          if ((history.value?.isNotEmpty ?? false) && !busy)
            IconButton(
              tooltip: 'Clear conversation',
              onPressed: _confirmClear,
              icon: const Icon(Icons.delete_sweep_outlined),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: history.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => const AppEmptyState(
                icon: Icons.error_outline,
                title: 'The conversation could not be loaded',
              ),
              data: (messages) => messages.isEmpty
                  ? _Introduction(onAsk: _askNow, scoped: scope != null)
                  : _Transcript(
                      messages: messages,
                      controller: _scroll,
                      busy: busy,
                      lastAnswer: assistant.scopeId == scope
                          ? assistant.lastAnswer
                          : null,
                    ),
            ),
          ),
          _Composer(controller: _composer, busy: busy, onSend: _send),
        ],
      ),
    );
  }
}

class _Transcript extends StatelessWidget {
  const _Transcript({
    required this.messages,
    required this.controller,
    required this.busy,
    required this.lastAnswer,
  });

  final List<ChatMessage> messages;
  final ScrollController controller;
  final bool busy;
  final AssistantAnswer? lastAnswer;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: messages.length + (busy ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= messages.length) return const ThinkingIndicator();

        final message = messages[index];

        // Confidence belongs to the run that produced it, and only the newest
        // answer has a run this session knows about.
        final isNewestAnswer =
            index == messages.length - 1 && !message.isFromUser && !busy;

        return ChatBubble(
          message: message,
          answer: isNewestAnswer ? lastAnswer : null,
        );
      },
    );
  }
}

/// Shown before the first question.
///
/// States the two things that are not obvious and that determine whether the
/// assistant appears to work at all: it can only read documents whose text has
/// been recognised, and it quotes rather than composes.
class _Introduction extends ConsumerWidget {
  const _Introduction({required this.onAsk, required this.scoped});

  final ValueChanged<String> onAsk;

  /// True when this conversation is about one document rather than the whole
  /// library — the suggestions and the explanation both change.
  final bool scoped;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (scoped) {
      return const AppEmptyState(
        icon: Icons.auto_awesome_outlined,
        title: 'Ask about this document',
        message:
            'Answers are quoted from this document only. Its conversation is '
            'kept separately, so it is still here next time you open it.',
      );
    }

    // Suggestions are a convenience: a library that cannot produce any still
    // gets the explanation, never an error.
    final suggestions =
        ref.watch(suggestedQuestionsProvider).value ?? const <String>[];

    return AppEmptyState(
      icon: Icons.auto_awesome_outlined,
      title: 'Ask about your documents',
      message:
          'Answers are quoted from the pages themselves — nothing is sent '
          'anywhere, and nothing is made up. Every answer shows where it came '
          'from.\n\n'
          'Looking for a document rather than an answer? The Search tab finds '
          'them by name, tag or text.',
      action: suggestions.isEmpty
          ? null
          : QuestionChips(
              questions: suggestions,
              label: 'TRY ASKING',
              icon: Icons.north_east,
              onSelected: onAsk,
            ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.busy,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !busy,
                maxLength: AskAssistant.maxQuestionLength,
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                onSubmitted: busy ? null : (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Ask questions about your documents',
                  border: OutlineInputBorder(),
                  isDense: true,
                  // The limit only matters as it is approached, and a permanent
                  // "0/500" under the field is noise the rest of the time.
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: busy ? null : onSend,
              icon: const Icon(Icons.arrow_upward),
              tooltip: 'Ask',
            ),
          ],
        ),
      ),
    );
  }
}
