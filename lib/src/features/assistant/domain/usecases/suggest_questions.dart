import '../../../../core/error/result.dart';
import '../repositories/assistant_repository.dart';

/// Questions to offer before the user has asked anything.
class SuggestQuestions {
  const SuggestQuestions(this._repository);

  final AssistantRepository _repository;

  FutureResult<List<String>> call() => _repository.suggestedQuestions();
}

/// The last few questions actually asked, newest first.
///
/// Derived from the transcript rather than stored separately — the history is
/// already the record of what was asked, and a second list would be one more
/// thing to keep in step with it.
abstract final class RecentQuestions {
  static const int max = 5;

  /// [questions] arrives oldest-first, as the transcript is ordered.
  ///
  /// Repeats collapse to their most recent occurrence: someone who asked the
  /// same thing three times wants one chip, not three.
  static List<String> from(Iterable<String> questions) {
    final seen = <String>{};
    final recent = <String>[];

    for (final question in questions.toList().reversed) {
      final trimmed = question.trim();
      if (trimmed.isEmpty) continue;
      if (!seen.add(trimmed.toLowerCase())) continue;

      recent.add(trimmed);
      if (recent.length >= max) break;
    }

    return List<String>.unmodifiable(recent);
  }
}
