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
  ///
  /// Scoped to [documentId] when given, and to the library-wide conversation
  /// otherwise. Asking about one document should not be interleaved with
  /// questions about the whole library.
  Stream<List<ChatMessage>> watchHistory({String? documentId});

  /// Appends a turn to the transcript.
  FutureResult<void> appendMessage(ChatMessage message);

  /// Empties one conversation. Does not touch documents or the search index.
  ///
  /// Clears only the scope named by [documentId], so clearing a document's
  /// conversation leaves the library-wide one intact and vice versa.
  FutureResult<void> clearHistory({String? documentId});

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
