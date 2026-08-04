import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../documents/presentation/providers/document_providers.dart';
import '../../../search/presentation/providers/search_providers.dart';
import '../../data/datasources/chat_history_local_data_source.dart';
import '../../data/repositories/retrieval_assistant_repository.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/assistant_repository.dart';
import '../../domain/usecases/ask_assistant.dart';
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

// ---- Controller ------------------------------------------------------------

/// Whether a question is currently being answered.
///
/// The transcript itself is the source of truth for what has been said —
/// `AskAssistant` writes both turns — so this holds only the one thing the
/// transcript cannot express: that an answer is on its way.
class AssistantController extends Notifier<bool> {
  @override
  bool build() => false;

  /// Returns a message the screen must show itself, or `null` when the
  /// transcript already carries the outcome.
  ///
  /// The split follows what `AskAssistant` actually does. A [ValidationFailure]
  /// is raised *before* either turn is written, so nothing in the transcript
  /// explains it and the composer has to. Every other failure happens after the
  /// question was recorded, and is appended as a failed assistant turn — so
  /// showing it again would say the same thing twice.
  Future<String?> ask(String question, {String? documentId}) async {
    if (state) return null;
    state = true;

    try {
      final result = await ref.read(askAssistantProvider)(
        question,
        documentId: documentId,
      );

      return switch (result) {
        Success() => null,
        Failed(failure: ValidationFailure(:final message)) => message,
        Failed() => null,
      };
    } finally {
      state = false;
    }
  }

  Future<void> clear() => ref.read(clearChatHistoryProvider)();
}

final assistantControllerProvider = NotifierProvider<AssistantController, bool>(
  AssistantController.new,
);
