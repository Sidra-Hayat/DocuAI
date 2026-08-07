import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../documents/presentation/providers/document_providers.dart';
import '../../../search/presentation/providers/search_providers.dart';
import '../../data/datasources/chat_history_local_data_source.dart';
import '../../data/repositories/retrieval_assistant_repository.dart';
import '../../domain/entities/assistant_answer.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/assistant_repository.dart';
import '../../domain/usecases/ask_assistant.dart';
import '../../domain/usecases/suggest_questions.dart';
import '../../domain/usecases/watch_chat_history.dart';

// ---- Dependencies ----------------------------------------------------------

final chatHistoryDataSourceProvider = Provider<ChatHistoryLocalDataSource>(
  (ref) => ChatHistoryLocalDataSource(ref.watch(chatHistoryBoxProvider)),
);

final assistantRepositoryProvider = Provider<AssistantRepository>(
  (ref) => RetrievalAssistantRepository(
    search: ref.watch(searchRepositoryProvider),
    documents: ref.watch(documentRepositoryProvider),
    history: ref.watch(chatHistoryDataSourceProvider),
  ),
);

final askAssistantProvider = Provider<AskAssistant>(
  (ref) => AskAssistant(
    ref.watch(assistantRepositoryProvider),
    idGenerator: const Uuid().v4,
  ),
);

final clearChatHistoryProvider = Provider<ClearChatHistory>(
  (ref) => ClearChatHistory(ref.watch(assistantRepositoryProvider)),
);

/// The transcript, oldest first, re-emitted as turns are added.
final chatHistoryProvider = StreamProvider<List<ChatMessage>>(
  (ref) => WatchChatHistory(ref.watch(assistantRepositoryProvider))(),
);

final suggestQuestionsProvider = Provider<SuggestQuestions>(
  (ref) => SuggestQuestions(ref.watch(assistantRepositoryProvider)),
);

/// Questions worth asking of this particular library.
///
/// Empty list on failure rather than an error state: suggestions are a
/// convenience, and an empty state that reports "suggestions unavailable"
/// would make a working assistant look broken.
final suggestedQuestionsProvider = FutureProvider<List<String>>((ref) async {
  final result = await ref.watch(suggestQuestionsProvider)();
  return result.valueOrNull ?? const <String>[];
});

/// The last few questions actually asked, newest first.
///
/// A projection of the transcript rather than a second stored list — the
/// history already records what was asked.
final recentQuestionsProvider = Provider<List<String>>((ref) {
  final history = ref.watch(chatHistoryProvider).value ?? const <ChatMessage>[];

  return RecentQuestions.from(
    history.where((message) => message.isFromUser).map((message) => message.text),
  );
});

// ---- Controller ------------------------------------------------------------

/// What the assistant is doing, plus what the last run reported about itself.
///
/// The transcript is the source of truth for what was *said* — `AskAssistant`
/// writes both turns. This holds the two things it cannot express: that an
/// answer is on its way, and how the run that produced the newest answer went.
class AssistantState {
  const AssistantState({this.busy = false, this.lastAnswer});

  final bool busy;

  /// Confidence and the searched-document count describe one run, and are
  /// deliberately not persisted with the transcript — replaying them against a
  /// library that has since changed would be a claim nobody re-checked.
  final AssistantAnswer? lastAnswer;

  AssistantState copyWith({bool? busy, AssistantAnswer? lastAnswer}) =>
      AssistantState(
        busy: busy ?? this.busy,
        lastAnswer: lastAnswer ?? this.lastAnswer,
      );
}

class AssistantController extends Notifier<AssistantState> {
  @override
  AssistantState build() => const AssistantState();

  /// Returns a message the screen must show itself, or `null` when the
  /// transcript already carries the outcome.
  ///
  /// The split follows what `AskAssistant` actually does. A [ValidationFailure]
  /// is raised *before* either turn is written, so nothing in the transcript
  /// explains it and the composer has to. Every other failure happens after the
  /// question was recorded, and is appended as a failed assistant turn — so
  /// showing it again would say the same thing twice.
  Future<String?> ask(String question, {String? documentId}) async {
    if (state.busy) return null;
    state = const AssistantState(busy: true);

    try {
      final result = await ref.read(askAssistantProvider)(
        question,
        documentId: documentId,
      );

      return switch (result) {
        Success(:final value) => () {
          state = AssistantState(lastAnswer: value);
          return null;
        }(),
        Failed(failure: ValidationFailure(:final message)) => message,
        Failed() => null,
      };
    } finally {
      if (state.busy) state = const AssistantState();
    }
  }

  Future<void> clear() async {
    await ref.read(clearChatHistoryProvider)();
    state = const AssistantState();
  }
}

final assistantControllerProvider =
    NotifierProvider<AssistantController, AssistantState>(
      AssistantController.new,
    );
