import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/utils/clock.dart';
import '../entities/assistant_answer.dart';
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

  FutureResult<AssistantAnswer> call(
    String question, {
    String? documentId,
  }) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty) {
      return const Failed(ValidationFailure('Type a question first.'));
    }
    if (trimmed.length > maxQuestionLength) {
      return const Failed(
        ValidationFailure('That question is too long — try asking it in fewer words.'),
      );
    }

    await _repository.appendMessage(
      ChatMessage(
        id: _newId(),
        role: ChatRole.user,
        text: trimmed,
        createdAt: _now(),
      ),
    );

    final answered = await _repository.ask(trimmed, documentId: documentId);

    await _repository.appendMessage(
      switch (answered) {
        Success(:final value) => ChatMessage(
          id: _newId(),
          role: ChatRole.assistant,
          text: value.text,
          createdAt: _now(),
          citations: value.citations,
        ),
        Failed(:final failure) => ChatMessage(
          id: _newId(),
          role: ChatRole.assistant,
          text: '',
          createdAt: _now(),
          errorMessage: failure.message,
        ),
      },
    );

    return answered;
  }
}
