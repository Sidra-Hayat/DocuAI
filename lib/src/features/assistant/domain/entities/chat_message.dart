import 'package:freezed_annotation/freezed_annotation.dart';

import 'assistant_answer.dart';

part 'chat_message.freezed.dart';

enum ChatRole { user, assistant }

/// One turn in the assistant transcript.
///
/// Both sides of the conversation are the same type so the chat list is a
/// single ordered collection rather than two that have to be interleaved
/// correctly at render time.
@freezed
abstract class ChatMessage with _$ChatMessage {
  const ChatMessage._();

  const factory ChatMessage({
    required String id,
    required ChatRole role,
    required String text,
    required DateTime createdAt,

    /// Populated on assistant turns only, and kept on the message rather than
    /// recomputed, so scrolling back through the transcript shows the sources
    /// that answer was actually built from.
    @Default(<AnswerCitation>[]) List<AnswerCitation> citations,

    /// Set when the turn failed. The message stays in the transcript carrying
    /// the reason, which reads better than a snackbar that disappears and
    /// leaves an unanswered question on screen.
    String? errorMessage,
  }) = _ChatMessage;

  bool get isFromUser => role == ChatRole.user;

  bool get hasFailed => errorMessage != null;
}
