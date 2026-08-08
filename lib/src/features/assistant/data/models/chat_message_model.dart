import 'package:hive_ce/hive.dart';

import '../../../../core/constants/hive_boxes.dart';
import '../../domain/entities/chat_message.dart';
import 'answer_citation_model.dart';

part 'chat_message_model.g.dart';

/// Hive representation of a [ChatMessage].
///
/// The role is stored as its enum **name**, for the same reason `OcrStatus` is:
/// an index is a position in a list, so inserting a case would silently
/// reinterpret every stored turn.
@HiveType(typeId: HiveTypeIds.chatMessage)
class ChatMessageModel {
  const ChatMessageModel({
    required this.id,
    required this.role,
    required this.text,
    required this.createdAt,
    required this.citations,
    required this.errorMessage,
    required this.documentId,
  });

  factory ChatMessageModel.fromEntity(ChatMessage message) => ChatMessageModel(
    id: message.id,
    role: message.role.name,
    text: message.text,
    createdAt: message.createdAt,
    citations: message.citations
        .map(AnswerCitationModel.fromEntity)
        .toList(growable: false),
    errorMessage: message.errorMessage,
    documentId: message.documentId,
  );

  @HiveField(0)
  final String id;

  @HiveField(1)
  final String role;

  @HiveField(2)
  final String text;

  @HiveField(3)
  final DateTime createdAt;

  @HiveField(4)
  final List<AnswerCitationModel> citations;

  @HiveField(5)
  final String? errorMessage;

  /// Null for the library-wide conversation — which is also what every
  /// transcript written before scoping existed reads back as, so those turns
  /// stay where the user left them.
  @HiveField(6)
  final String? documentId;

  ChatMessage toEntity() => ChatMessage(
    id: id,
    role: _decodeRole(role),
    text: text,
    createdAt: createdAt,
    citations: citations
        .map((citation) => citation.toEntity())
        .toList(growable: false),
    errorMessage: errorMessage,
    documentId: documentId,
  );

  /// An unrecognised role is read as the assistant's, because the alternative —
  /// attributing an unknown turn to the user — puts words in their mouth.
  static ChatRole _decodeRole(String raw) => ChatRole.values.firstWhere(
    (role) => role.name == raw,
    orElse: () => ChatRole.assistant,
  );
}
