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

/// One conversation's transcript, oldest first, re-emitted as turns are added.
///
/// Keyed by document id, with null for the library-wide conversation — the
/// same key the messages themselves carry.
final chatHistoryProvider = StreamProvider.family<List<ChatMessage>, String?>(
  (ref, documentId) => WatchChatHistory(
    ref.watch(assistantRepositoryProvider),
  )(documentId: documentId),
);

final suggestQuestionsProvider = Provider<SuggestQuestions>(
  (ref) => SuggestQuestions(ref.watch(assistantRepositoryProvider)),
);

/// Questions worth asking here — of this library, or of one document.
///
/// Keyed by the same nullable document id the conversation is, so a scoped
/// screen offers what that document can be asked and the library-wide one keeps
/// offering documents by name.
///
/// Empty list on failure rather than an error state: suggestions are a
/// convenience, and an empty state that reports "suggestions unavailable"
/// would make a working assistant look broken.
final suggestedQuestionsProvider =
    FutureProvider.family<List<String>, String?>((ref, documentId) async {
      final result = await ref.watch(suggestQuestionsProvider)(
        documentId: documentId,
      );
      return result.valueOrNull ?? const <String>[];
    });

/// The last few questions actually asked, newest first.
///
/// A projection of the transcript rather than a second stored list — the
/// history already records what was asked.
final recentQuestionsProvider = Provider.family<List<String>, String?>((
  ref,
  documentId,
) {
  final history =
      ref.watch(chatHistoryProvider(documentId)).value ?? const <ChatMessage>[];

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
  const AssistantState({this.busy = false, this.lastAnswer, this.scopeId});

  final bool busy;

  /// The conversation the last run belonged to. Carried for the same reason
  /// `OcrState` and `ExportState` carry a document id: a run started in one
  /// conversation must not paint its result into another.
  final String? scopeId;

  /// Confidence and the searched-document count describe one run, and are
  /// deliberately not persisted with the transcript — replaying them against a
  /// library that has since changed would be a claim nobody re-checked.
  final AssistantAnswer? lastAnswer;

  AssistantState copyWith({
    bool? busy,
    AssistantAnswer? lastAnswer,
    String? scopeId,
  }) => AssistantState(
    busy: busy ?? this.busy,
    lastAnswer: lastAnswer ?? this.lastAnswer,
    scopeId: scopeId ?? this.scopeId,
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
    state = AssistantState(busy: true, scopeId: documentId);

    try {
      final result = await ref.read(askAssistantProvider)(
        question,
        documentId: documentId,
      );

      return switch (result) {
        Success(:final value) => () {
          state = AssistantState(lastAnswer: value, scopeId: documentId);
          return null;
        }(),
        Failed(failure: ValidationFailure(:final message)) => message,
        Failed() => null,
      };
    } finally {
      if (state.busy) state = const AssistantState();
    }
  }

  Future<void> clear({String? documentId}) async {
    await ref.read(clearChatHistoryProvider)(documentId: documentId);
    state = const AssistantState();
  }
}

final assistantControllerProvider =
    NotifierProvider<AssistantController, AssistantState>(
      AssistantController.new,
    );
