import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/utils/clock.dart';
import '../entities/assistant_answer.dart';
import '../entities/assistant_intent.dart';
import '../entities/chat_message.dart';
import '../repositories/assistant_repository.dart';

/// Asks a question and records both turns in the transcript.
///
/// The user's message is appended *before* the answer is requested, so a
/// question that takes several seconds — or fails — still appears in the chat
/// immediately, in the order it was asked. A failed answer is stored as an
/// assistant turn carrying the reason rather than being dropped, which keeps
/// the transcript a complete record of what was asked.
class AskAssistant {
  const AskAssistant(
    this._repository, {
    required String Function() idGenerator,
    Clock clock = systemClock,
  }) : _newId = idGenerator,
       _now = clock;

  final AssistantRepository _repository;
  final String Function() _newId;
  final Clock _now;

  static const int maxQuestionLength = 500;

  /// Asks a question the user typed.
  FutureResult<AssistantAnswer> call(
    String question, {
    required String conversationId,
    String? documentId,
  }) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty) {
      return const Failed(ValidationFailure('Type a question first.'));
    }
    if (trimmed.length > maxQuestionLength) {
      return const Failed(
        ValidationFailure(
          'That question is too long — try asking it in fewer words.',
        ),
      );
    }

    return run(
      AskQuestion(trimmed),
      conversationId: conversationId,
      documentId: documentId,
    );
  }

  /// Carries out an action the user chose, and records it like a question.
  ///
  /// An action produces an ordinary pair of turns: the request as the user
  /// would have phrased it, then the answer with its citations. That is what
  /// keeps the transcript a record of the conversation rather than of the
  /// typing — a thread showing a summary with nothing above it explains
  /// nothing when it is reopened a month later.
  ///
  /// No validation here. There is nothing to validate: an intent came from a
  /// button, so it cannot be blank or five hundred characters long.
  FutureResult<AssistantAnswer> run(
    AssistantIntent intent, {
    required String conversationId,
    String? documentId,
  }) async {
    await _repository.appendMessage(
      ChatMessage(
        id: _newId(),
        role: ChatRole.user,
        text: intent.transcriptLabel,
        createdAt: _now(),
        // Both turns carry the thread and the scope, so the transcript can be
        // filtered back into the conversation it belongs to.
        conversationId: conversationId,
        documentId: documentId,
      ),
    );

    final answered = await _repository.run(intent, documentId: documentId);

    await _repository.appendMessage(switch (answered) {
      Success(:final value) => ChatMessage(
        id: _newId(),
        role: ChatRole.assistant,
        text: value.text,
        createdAt: _now(),
        citations: value.citations,
        conversationId: conversationId,
        documentId: documentId,
      ),
      Failed(:final failure) => ChatMessage(
        id: _newId(),
        role: ChatRole.assistant,
        text: '',
        createdAt: _now(),
        errorMessage: failure.message,
        conversationId: conversationId,
        documentId: documentId,
      ),
    });

    return answered;
  }
}
