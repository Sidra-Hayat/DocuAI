import '../../../../core/error/result.dart';
import '../repositories/assistant_repository.dart';

/// Questions to offer before the user has asked anything.
class SuggestQuestions {
  const SuggestQuestions(this._repository);

  final AssistantRepository _repository;

  /// Scoped to one document when [documentId] is given.
  FutureResult<List<String>> call({String? documentId}) =>
      _repository.suggestedQuestions(documentId: documentId);
}

/// The questions the app asks on the user's behalf.
///
/// Named constants because the same strings have to arrive from three places
/// and mean the same thing in all of them: the Summarise button on the document
/// screen, the suggestion chips, and the user typing. Everything funnels
/// through the one analyser — a button with its own private code path would be
/// a second summariser to keep in step with the first.
abstract final class DocumentQuestions {
  static const String summarise = 'Summarise this document';
  static const String dates = 'Find important dates';
  static const String names = 'Find names';
  static const String amounts = 'Find amounts';
  static const String contact = 'Find contact details';
  static const String references = 'Find reference numbers';
}

/// The same idea for the library-wide conversation.
///
/// Separate from [DocumentQuestions] because the wording has to be true of a
/// library rather than of one page — "Find names" reads as a command inside a
/// document and as an ambiguity outside it, where the useful question is which
/// of *your documents* mention anybody.
///
/// Every one of these is offered only when the library can actually answer it,
/// checked with the same signals that will do the answering. A suggestion that
/// comes back empty is worse than no suggestion: it teaches the user that the
/// assistant does not work, when in truth they were handed a question about
/// something their documents do not contain.
abstract final class LibraryQuestions {
  static const String summariseLatest = 'Summarize my latest document';
  static const String dates = 'Find all important dates';
  static const String names = 'Who is mentioned in my documents?';
  static const String amounts = 'What amounts are mentioned?';

  /// "What is my electricity bill about?" — with the user's own document in
  /// place of the example, because a suggestion naming a document they do not
  /// have is a suggestion that cannot be tapped.
  static String about(String title) => 'What is the $title about?';
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
