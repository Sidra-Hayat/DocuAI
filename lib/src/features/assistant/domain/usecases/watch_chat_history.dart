import '../../../../core/error/result.dart';
import '../entities/chat_message.dart';
import '../entities/conversation.dart';
import '../repositories/assistant_repository.dart';

/// One conversation's turns, oldest first.
class WatchChatHistory {
  const WatchChatHistory(this._repository);

  final AssistantRepository _repository;

  Stream<List<ChatMessage>> call(String conversationId) =>
      _repository.watchHistory(conversationId: conversationId);
}

/// Every conversation, newest first.
///
/// Scoped to one document when [documentId] is given, so a document's own
/// threads are listed without the library-wide ones among them.
class WatchConversations {
  const WatchConversations(this._repository);

  final AssistantRepository _repository;

  Stream<List<Conversation>> call({String? documentId}) =>
      _repository.watchConversations(documentId: documentId);
}

/// Removes one conversation and everything said in it.
class DeleteConversation {
  const DeleteConversation(this._repository);

  final AssistantRepository _repository;

  FutureResult<void> call(String conversationId) =>
      _repository.deleteConversation(conversationId);
}
