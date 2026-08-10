import '../domain/entities/assistant_intent.dart';

/// Carries an intent through a route.
///
/// A conversation is opened by navigating to it, and a route's parameters are
/// strings. This is the one place an [AssistantIntent] becomes one and back
/// again — a short stable token, not the English sentence the action stands
/// for. Passing the sentence is precisely what the intent type exists to stop:
/// it would arrive at the far end as text to be parsed, which is where "Explain
/// this document" turned into a search for the words "this document".
///
/// A selection travels in its own parameter. It can be a paragraph, and a
/// paragraph is not an action token.
abstract final class AssistantIntentCodec {
  static const String actionKey = 'action';
  static const String selectionKey = 'selection';

  static const String _summarize = 'summarize';
  static const String _shortSummary = 'summarize.short';
  static const String _explain = 'explain';
  static const String _findPrefix = 'find.';

  /// The query parameters that carry [intent], or empty for one that has none.
  static Map<String, String> encode(AssistantIntent intent) => switch (intent) {
    SummarizeDocument(:final brief) => <String, String>{
      actionKey: brief ? _shortSummary : _summarize,
    },
    ExplainDocument() => <String, String>{actionKey: _explain},
    FindInformation(:final kind) => <String, String>{
      actionKey: '$_findPrefix${kind.name}',
    },
    ExplainSelection(:final text) => <String, String>{selectionKey: text},
    // A typed question is not routed; it is typed into the conversation that
    // the route opened.
    AskQuestion() => const <String, String>{},
  };

  /// The intent those parameters stood for, or null when there was none.
  ///
  /// Unknown tokens decode to null rather than throwing. A link from an older
  /// build naming an action this one does not have should open the
  /// conversation, not fail the route.
  static AssistantIntent? decode({String? action, String? selection}) {
    if (selection != null && selection.trim().isNotEmpty) {
      return ExplainSelection(selection);
    }

    return switch (action) {
      null => null,
      _summarize => const SummarizeDocument(),
      _shortSummary => const SummarizeDocument(brief: true),
      _explain => const ExplainDocument(),
      final token when token.startsWith(_findPrefix) => _find(
        token.substring(_findPrefix.length),
      ),
      _ => null,
    };
  }

  static AssistantIntent? _find(String name) {
    for (final kind in InformationKind.values) {
      if (kind.name == name) return FindInformation(kind);
    }
    return null;
  }
}
