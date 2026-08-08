import '../../../../core/error/result.dart';
import '../entities/assistant_answer.dart';
import '../entities/chat_message.dart';
import '../entities/conversation.dart';

/// The offline question-answering engine and its transcript.
///
/// Phase 7 implements this retrieval-first: the answer is assembled from
/// passages the search index already holds, which means it works on every
/// device with no model download. The optional on-device model is a second
/// strategy behind the same method — callers cannot tell which ran except by
/// reading [AssistantAnswer.source].
abstract interface class AssistantRepository {
  /// Answers [question] from the user's documents.
  ///
  /// Scoped to one document when [documentId] is given — "ask this document"
  /// from the detail screen — and across the whole library otherwise.
  ///
  /// Finding no relevant passage is a success carrying an ungrounded answer,
  /// not a failure: "I could not find that in your documents" is a legitimate
  /// reply, and rendering it as an error would be misleading.
  FutureResult<AssistantAnswer> ask(String question, {String? documentId});

  /// Every conversation, newest first, re-emitted as turns are added.
  ///
  /// Derived from the messages rather than stored separately — see
  /// [Conversation]. Scoped to [documentId] when given, so a document's screen
  /// lists only the threads about it.
  Stream<List<Conversation>> watchConversations({String? documentId});

  /// One conversation's turns, oldest first, re-emitted as they are added.
  ///
  /// A conversation that has never been spoken in emits an empty list rather
  /// than failing: it exists as soon as the user opens it, and on disk only
  /// once there is something in it.
  Stream<List<ChatMessage>> watchHistory({required String conversationId});

  /// Appends a turn to the transcript.
  FutureResult<void> appendMessage(ChatMessage message);

  /// Removes one conversation and every turn in it.
  ///
  /// Does not touch documents or the search index — a thread is a record of
  /// what was asked, not of anything that was scanned.
  FutureResult<void> deleteConversation(String conversationId);

  /// Questions worth asking here, for the empty state.
  ///
  /// Drawn from the user's own documents rather than written in advance: a
  /// generic "What is my policy number?" is useless to someone whose library
  /// is three utility bills, and the first thing an empty assistant has to do
  /// is show that it knows what it can answer.
  ///
  /// Scoped to one document when [documentId] is given, where the offer becomes
  /// what that document can be asked — summarise it, list its dates, its
  /// amounts, its names — restricted to the shapes its pages actually carry.
  ///
  /// Returns an empty list when there is nothing to suggest.
  FutureResult<List<String>> suggestedQuestions({String? documentId});
}
