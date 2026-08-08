import '../../../../core/error/result.dart';
import '../entities/chat_message.dart';
import '../repositories/assistant_repository.dart';

/// Streams the assistant transcript, oldest first.
class WatchChatHistory {
  const WatchChatHistory(this._repository);

  final AssistantRepository _repository;

  Stream<List<ChatMessage>> call({String? documentId}) =>
      _repository.watchHistory(documentId: documentId);
}

/// Clears the transcript.
///
/// Paired with [WatchChatHistory] in one file because they are the same
/// concern from two directions, and splitting them would leave two files of
/// four lines each.
class ClearChatHistory {
  const ClearChatHistory(this._repository);

  final AssistantRepository _repository;

  FutureResult<void> call({String? documentId}) =>
      _repository.clearHistory(documentId: documentId);
}
