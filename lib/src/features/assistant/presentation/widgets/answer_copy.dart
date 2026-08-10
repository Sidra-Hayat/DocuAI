import '../../data/repositories/retrieval_assistant_repository.dart';

/// How the assistant's unhelpful answers are worded on screen.
///
/// The retrieval layer composes an answer and stores it with the transcript.
/// Three of those answers are not really answers — nothing was found, nothing
/// has been read, there is nothing to read — and their wording is a matter of
/// how the app talks to people rather than of how retrieval works.
///
/// So the wording is translated *here*, at the point of display, and the
/// repository is left exactly as it is. That keeps a presentation concern out
/// of the data layer, keeps the stored transcript stable, and keeps the
/// repository's own tests — which assert against the constants by name, not by
/// their text — untouched.
///
/// Everything else passes through unchanged: a grounded answer is quoted from
/// the user's pages, and rewriting *that* would be the app putting words in a
/// document's mouth.
abstract final class AnswerCopy {
  /// The sentence for a question the documents do not answer.
  ///
  /// Says what happened and stops. No apology, and no suggestion that the
  /// assistant might be wrong about it — it searched, and the words are not
  /// there.
  static const String notFound =
      "I couldn't find that information in your documents.";

  static const String noText =
      "None of your documents have had their pages read yet, so there's "
      'nothing for me to look through.';

  static const String emptyLibrary =
      'There are no documents to look through yet. Add one and I can answer '
      'questions about it.';

  /// The stored answer, in the words the app uses.
  static String forDisplay(String stored) => switch (stored) {
    RetrievalAssistantRepository.notFoundMessage => notFound,
    RetrievalAssistantRepository.noTextMessage => noText,
    RetrievalAssistantRepository.emptyLibraryMessage => emptyLibrary,
    _ => stored,
  };

  /// One concrete thing to do about it, where there is one.
  ///
  /// Separate from the answer rather than tacked onto the end of it: the answer
  /// is what the assistant found, and the suggestion is the app talking. Shown
  /// quieter for the same reason.
  static String? hintFor(String stored) => switch (stored) {
    RetrievalAssistantRepository.notFoundMessage =>
      'Try the words as they appear on the page, or open the document and '
          'search inside it.',
    RetrievalAssistantRepository.noTextMessage =>
      'Open a document and choose Read — that makes it searchable and lets me '
          'answer questions about it.',
    RetrievalAssistantRepository.emptyLibraryMessage =>
      'Scan, import or write a document to get started.',
    _ => null,
  };
}
