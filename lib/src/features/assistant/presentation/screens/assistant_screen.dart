import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_state_view.dart';
import '../../../documents/domain/entities/document.dart';
import '../../../documents/presentation/providers/document_providers.dart';
import '../../domain/entities/assistant_intent.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/usecases/ask_assistant.dart';
import '../providers/assistant_providers.dart';
import '../widgets/answer_view.dart';
import '../widgets/assistant_quick_actions.dart';
import '../widgets/question_chips.dart';
import '../widgets/thinking_indicator.dart';

/// Offline question answering over the user's own documents.
///
/// Answers are quoted from the pages, never composed, so every reply can be
/// traced back to where it came from. The screen keeps that property and stops
/// performing it: an answer arrives as an answer, with one line naming its
/// source underneath, and the excerpt is there for anyone who taps to check.
///
/// What it no longer shows by default is the shape of the search that produced
/// it — the match-strength chip, the count of documents read, the list of words
/// that matched. Those describe the retrieval, and a person asking how much
/// their electricity bill was is not asking about retrieval.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({
    required this.conversationId,
    this.documentId,
    this.documentTitle,
    this.initialIntent,
    super.key,
  });

  /// The thread this screen is showing.
  ///
  /// Always known before the screen opens, including for a brand-new thread:
  /// a conversation exists as soon as the user is looking at it, and reaches
  /// the box only once something has been said in it.
  final String conversationId;

  /// The document this conversation is about, or null for the library-wide
  /// one reached from the Assistant tab.
  final String? documentId;

  /// Shown in the bar so a scoped conversation says what it is scoped to.
  final String? documentTitle;

  /// Carried out once, on arrival.
  ///
  /// How the Summarise button, the Explain button and the reader's selection
  /// work. Each arrives as the intent it stood for rather than as a sentence to
  /// be re-read: the button already knew what it meant, and the whole class of
  /// defect this replaced came from throwing that knowledge away and asking the
  /// engine to recover it from English.
  ///
  /// The result still lands in the transcript as an ordinary pair of turns.
  final AssistantIntent? initialIntent;

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _composerFocus = FocusNode();

  @override
  void initState() {
    super.initState();

    final intent = widget.initialIntent;
    if (intent == null) return;

    // After the first frame: running an intent reads a provider and writes the
    // transcript, neither of which may happen while the widget is still being
    // built.
    Future.microtask(() {
      if (mounted) _run(intent);
    });
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final question = _composer.text;
    if (question.trim().isEmpty) return;

    _composer.clear();
    await _ask(question);
  }

  /// Asks a question the user picked rather than typed.
  ///
  /// Routed through the same path as the composer so a suggestion and a typed
  /// question cannot drift apart in validation or error handling.
  Future<void> _askNow(String question) async {
    _composer.clear();
    await _ask(question);
  }

  Future<void> _ask(String question) async {
    final messenger = ScaffoldMessenger.of(context);

    final rejection = await ref
        .read(assistantControllerProvider.notifier)
        .ask(
          question,
          conversationId: widget.conversationId,
          documentId: widget.documentId,
        );

    // Only a question rejected before it was recorded needs telling; anything
    // else is already in the transcript as a failed turn.
    if (rejection != null) {
      messenger.showSnackBar(SnackBar(content: Text(rejection)));
    }
  }

  /// Runs a chosen action.
  ///
  /// Straight to the intent — never through the composer. Rendering an action
  /// as the sentence a user might have typed and asking the engine to read it
  /// back is exactly how the Explain button came to answer with the words
  /// "this document".
  Future<void> _run(AssistantIntent intent) async {
    final messenger = ScaffoldMessenger.of(context);

    final rejection = await ref
        .read(assistantControllerProvider.notifier)
        .run(
          intent,
          conversationId: widget.conversationId,
          documentId: widget.documentId,
        );

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
        title: const Text('Delete this conversation?'),
        content: const Text(
          'The questions and answers are removed. Your documents are not '
          'affected.',
        ),
        actions: <Widget>[
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

    if (!(confirmed ?? false) || !mounted) return;

    // Resolved before the delete, not after: the thread this screen shows is
    // about to stop existing, and reaching through the context afterwards is
    // how a disposed dependency gets touched.
    final navigator = Navigator.of(context);
    await notifier.delete(widget.conversationId);
    // The thread this screen exists to show is gone, so the screen goes with
    // it rather than sitting on an empty transcript the user has to leave.
    if (navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final scope = widget.conversationId;
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
              : 'About ${widget.documentTitle}',
          overflow: TextOverflow.ellipsis,
        ),
        actions: <Widget>[
          if (recent.isNotEmpty && !busy)
            PopupMenuButton<String>(
              tooltip: 'Questions you asked before',
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
              tooltip: 'Delete this conversation',
              onPressed: _confirmClear,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: history.when(
              loading: () =>
                  const AppStateView.busy(title: 'Opening this conversation…'),
              error: (error, stackTrace) => const AppStateView.problem(
                icon: Icons.error_outline,
                title: 'The conversation could not be loaded',
              ),
              data: (messages) => messages.isEmpty
                  ? _Introduction(
                      onAsk: _askNow,
                      onIntent: _run,
                      onWriteQuestion: _composerFocus.requestFocus,
                      scope: widget.documentId,
                    )
                  : _Transcript(
                      messages: messages,
                      controller: _scroll,
                      busy: busy,
                    ),
            ),
          ),
          _Composer(
            controller: _composer,
            focusNode: _composerFocus,
            busy: busy,
            scoped: widget.documentId != null,
            onSend: _send,
            onIntent: _run,
          ),
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
  });

  final List<ChatMessage> messages;
  final ScrollController controller;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      itemCount: messages.length + (busy ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= messages.length) return const ThinkingIndicator();

        return ChatTurn(message: messages[index]);
      },
    );
  }
}

/// Shown before the first question.
///
/// Leads with what the user can do rather than with a caveat about how the
/// engine works. The old version opened with two paragraphs — one explaining
/// that answers are quoted rather than composed, one pointing at the Search tab
/// — which is a lot of reading in front of an empty box.
class _Introduction extends ConsumerWidget {
  const _Introduction({
    required this.onAsk,
    required this.onIntent,
    required this.onWriteQuestion,
    required this.scope,
  });

  /// Sends one of the suggested *questions*, which are questions and go through
  /// retrieval like any other.
  final ValueChanged<String> onAsk;

  final ValueChanged<AssistantIntent> onIntent;
  final VoidCallback onWriteQuestion;

  /// The document this conversation is about, or null for the library-wide
  /// one — the suggestions and the actions both change.
  final String? scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Suggestions are a convenience: a document or library that cannot produce
    // any still gets the actions, never an error.
    final suggestions =
        ref.watch(suggestedQuestionsProvider(scope)).value ?? const <String>[];

    // A library with nothing readable in it cannot answer anything, and saying
    // so beats offering four actions that all come back empty.
    final library = ref.watch(documentsProvider).value ?? const <Document>[];
    if (scope == null && !library.any((document) => document.hasText)) {
      return const AppStateView(
        icon: Icons.folder_open_outlined,
        title: 'Nothing to ask about yet',
        message:
            'Add or scan a document first, then you can ask questions about '
            'it.',
      );
    }

    return AppStateView(
      icon: Icons.auto_awesome_outlined,
      title: scope == null
          ? 'Ask about your documents'
          : 'Ask about this document',
      message: scope == null
          // Said plainly on the screen where it is not obvious. Inside a
          // document the scope explains itself; from the Assistant tab the user
          // has no way of knowing what the question is being asked *of*.
          ? 'Ask a question about any of your documents. DocuAI searches your '
                'saved documents and answers only from information it can find.'
          : 'Every answer comes from this document’s own pages, and shows you '
                'where it came from.',
      action: AssistantQuickActions(
        onIntent: onIntent,
        onWriteQuestion: onWriteQuestion,
        scoped: scope != null,
      ),
      secondaryAction: suggestions.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: QuestionChips(
                questions: suggestions,
                label: 'FOR EXAMPLE',
                icon: Icons.north_east,
                onSelected: onAsk,
              ),
            ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.busy,
    required this.scoped,
    required this.onSend,
    required this.onIntent,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool busy;
  final bool scoped;
  final VoidCallback onSend;
  final ValueChanged<AssistantIntent> onIntent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            // The quick actions, still reachable. They used to exist only in
            // the empty state, so the second question onwards you were on your
            // own with a blank field.
            IconButton(
              tooltip: 'Summarize, explain, find information',
              onPressed: busy
                  ? null
                  : () => showQuickActionsSheet(
                      context,
                      scoped: scoped,
                      onIntent: onIntent,
                      onWriteQuestion: focusNode.requestFocus,
                    ),
              icon: const Icon(Icons.auto_awesome_outlined),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: !busy,
                maxLength: AskAssistant.maxQuestionLength,
                maxLines: 4,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.send,
                onSubmitted: busy ? null : (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'Ask about your documents',
                  isDense: true,
                  // The limit only matters as it is approached, and a permanent
                  // "0/500" under the field is noise the rest of the time.
                  counterText: '',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHigh,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.md,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    borderSide: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
            AppSpacing.gapHorizontalSm,
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
