import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../../../core/constants/hive_boxes.dart';
import '../../../../core/error/exceptions.dart';
import '../models/chat_message_model.dart';

/// Persists the assistant transcript.
///
/// Keyed by message id and ordered by timestamp on read, rather than relying on
/// Hive's insertion order: two turns written in the same millisecond by the
/// same call must still come back in the order they were asked and answered.
class ChatHistoryLocalDataSource {
  const ChatHistoryLocalDataSource(this._box);

  final Box<ChatMessageModel> _box;

  /// Beyond this the oldest turns are dropped.
  ///
  /// A transcript grows for the life of the install and is never useful in
  /// full — nobody scrolls back through a thousand questions — so it is capped
  /// rather than left to consume storage on a device that cannot offload it.
  static const int maxMessages = 200;

  List<ChatMessageModel> readAll() {
    try {
      return _box.values.toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    } catch (error) {
      throw CacheException(
        'The conversation could not be read.',
        cause: error,
      );
    }
  }

  Stream<BoxEvent> watch() => _box.watch();

  Future<void> append(ChatMessageModel message) async {
    try {
      await _box.put(message.id, message);
      await _trim();
    } catch (error) {
      throw CacheException(
        'The conversation could not be saved.',
        cause: error,
      );
    }
  }

  /// Empties one conversation.
  ///
  /// Deletes only the turns in the named scope rather than clearing the box:
  /// clearing a document's conversation must leave the library-wide one — and
  /// every other document's — exactly as it was.
  Future<void> clear({String? documentId}) async {
    try {
      await _box.deleteAll(
        readAll()
            .where((message) => message.documentId == documentId)
            .map((message) => message.id),
      );
    } catch (error) {
      throw CacheException(
        'The conversation could not be cleared.',
        cause: error,
      );
    }
  }

  /// Caps each conversation independently.
  ///
  /// A single global cap would let a busy document's conversation evict the
  /// library-wide one, or another document's — the user would watch history
  /// they never touched disappear.
  Future<void> _trim() async {
    if (_box.length <= maxMessages) return;

    final byScope = <String?, List<ChatMessageModel>>{};
    for (final message in readAll()) {
      byScope.putIfAbsent(message.documentId, () => <ChatMessageModel>[])
          .add(message);
    }

    final surplus = <String>[];
    for (final conversation in byScope.values) {
      if (conversation.length <= maxMessages) continue;
      surplus.addAll(
        conversation
            .take(conversation.length - maxMessages)
            .map((message) => message.id),
      );
    }

    if (surplus.isNotEmpty) await _box.deleteAll(surplus);
  }
}

Future<Box<ChatMessageModel>> openChatHistoryBox() =>
    Hive.openBox<ChatMessageModel>(HiveBoxes.chatHistory);

final chatHistoryBoxProvider = Provider<Box<ChatMessageModel>>(
  (ref) => throw UnimplementedError(
    'chatHistoryBoxProvider was not overridden. '
    'It must be provided by bootstrap() via ProviderScope.overrides.',
  ),
);
