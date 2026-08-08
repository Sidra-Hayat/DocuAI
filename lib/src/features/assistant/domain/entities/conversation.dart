import 'chat_message.dart';

/// One thread of questions and answers.
///
/// Derived from the messages rather than stored beside them. A conversation is
/// entirely described by the turns it contains — its name is the first thing
/// asked, its age is the last thing said — so a second record would be a copy
/// to keep in step, and an empty one on disk after every accidental tap on
/// "New".
///
/// A conversation that has not been spoken in does not exist yet, which is the
/// right answer to "what happens if I start one and change my mind".
class Conversation {
  const Conversation({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.messageCount,
    this.documentId,
  });

  final String id;

  /// The first question asked, trimmed for a list row.
  final String title;

  final DateTime updatedAt;
  final int messageCount;

  /// The document this thread is about, or null when it ranges over the whole
  /// library.
  final String? documentId;

  bool get isAboutOneDocument => documentId != null;

  /// Groups [messages] into the conversations they belong to, newest first.
  static List<Conversation> from(List<ChatMessage> messages) {
    final grouped = <String, List<ChatMessage>>{};
    for (final message in messages) {
      grouped.putIfAbsent(message.conversation, () => <ChatMessage>[])
          .add(message);
    }

    final conversations = <Conversation>[
      for (final entry in grouped.entries) _fold(entry.key, entry.value),
    ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return List<Conversation>.unmodifiable(conversations);
  }

  static Conversation _fold(String id, List<ChatMessage> messages) {
    final ordered = List<ChatMessage>.of(messages)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // The first thing the user asked, not the first message of any kind: an
    // assistant turn opens no conversation, and naming a thread after an error
    // message would be worse than naming it after nothing.
    final opener = ordered
        .where((message) => message.isFromUser && message.text.trim().isNotEmpty)
        .firstOrNull;

    return Conversation(
      id: id,
      title: _titleFrom(opener?.text),
      updatedAt: ordered.last.createdAt,
      messageCount: ordered.length,
      documentId: ordered.first.documentId,
    );
  }

  /// Fallback name for a thread whose only turns are errors or blanks.
  static const String untitled = 'New conversation';

  static String _titleFrom(String? question) {
    final trimmed = question?.trim() ?? '';
    if (trimmed.isEmpty) return untitled;

    // One line, bounded. A list row shows about this much before it truncates,
    // and truncating here rather than in the widget means the same name is
    // used wherever the conversation is named.
    final flattened = trimmed.replaceAll(RegExp(r'\s+'), ' ');
    return flattened.length <= 60
        ? flattened
        : '${flattened.substring(0, 59).trimRight()}…';
  }
}
