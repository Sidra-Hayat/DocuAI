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

    /// Which document this turn belongs to, or null for the library-wide
    /// conversation.
    ///
    /// Scope lives on the message rather than in a box per document. A box per
    /// document would mean opening one per conversation and remembering to
    /// delete it with the document; a nullable field makes "every
    /// conversation" a filter instead of a fan-out.
    String? documentId,

    /// Which conversation this turn belongs to.
    ///
    /// Null on every message written before conversations existed. Those are
    /// not orphans: [conversation] folds them into one conversation per scope,
    /// which is exactly what they were.
    String? conversationId,

    /// Populated on assistant turns only, and kept on the message rather than
    /// recomputed, so scrolling back through the transcript shows the sources
    /// that answer was actually built from.
    @Default(<AnswerCitation>[]) List<AnswerCitation> citations,

    /// Set when the turn failed. The message stays in the transcript carrying
    /// the reason, which reads better than a snackbar that disappears and
    /// leaves an unanswered question on screen.
    String? errorMessage,
  }) = _ChatMessage;

  /// The conversation this turn is in, resolving the legacy case.
  ///
  /// Everything downstream groups and filters on this rather than on the raw
  /// field, so a transcript written before conversations existed keeps working
  /// without a migration pass over the box.
  String get conversation =>
      conversationId ?? legacyConversationFor(documentId);

  /// The conversation that pre-conversation messages belong to.
  static String legacyConversationFor(String? documentId) =>
      documentId == null ? 'legacy:library' : 'legacy:$documentId';

  bool get isFromUser => role == ChatRole.user;

  bool get hasFailed => errorMessage != null;
}
