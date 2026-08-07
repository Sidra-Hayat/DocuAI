import '../../../../core/error/result.dart';
import '../entities/assistant_answer.dart';
import '../entities/chat_message.dart';

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

  /// The persisted transcript, oldest first, re-emitted as turns are added.
  Stream<List<ChatMessage>> watchHistory();

  /// Appends a turn to the transcript.
  FutureResult<void> appendMessage(ChatMessage message);

  /// Empties the transcript. Does not touch documents or the search index.
  FutureResult<void> clearHistory();

  /// Questions worth asking of *this* library, for the empty state.
  ///
  /// Drawn from the user's own documents rather than written in advance: a
  /// generic "What is my policy number?" is useless to someone whose library
  /// is three utility bills, and the first thing an empty assistant has to do
  /// is show that it knows what it can answer.
  ///
  /// Returns an empty list when there is nothing to suggest.
  FutureResult<List<String>> suggestedQuestions();
}
