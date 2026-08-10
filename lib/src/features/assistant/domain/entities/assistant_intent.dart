/// What the user asked the assistant to do.
///
/// The distinction this type exists to make: a *question* is text to be
/// understood, and an *action* is a decision the user has already made. The
/// assistant used to receive both as English — the Explain button sent the
/// string "Explain this document" and the engine then tried to work out what it
/// meant. It worked out the wrong thing, and could only ever have: stripped of
/// its verb, "this document" is two words the ranker duly found on a page,
/// producing the answer
///
/// ```
/// This passage says:
/// “this document”
/// ```
///
/// which is the query echoed back as though it were content. No amount of
/// parsing fixes that, because the parsing was never the problem: the button
/// already knew what it meant, and then threw that knowledge away by rendering
/// it as a sentence.
///
/// So an action carries its meaning to the repository intact, and natural
/// language is parsed only when natural language is genuinely what arrived —
/// [AskQuestion], from the composer.
///
/// The scope stays out of the intent on purpose. Which document a request is
/// about is a property of the *conversation*, threaded through `ask`,
/// `appendMessage` and the transcript already; a second copy inside the intent
/// would be a second thing to keep in step with it.
sealed class AssistantIntent {
  const AssistantIntent();

  /// What the transcript records the user as having said.
  ///
  /// An action still appears in the conversation as a turn, because a thread
  /// that shows an answer with no question above it is not a record of
  /// anything. This is the sentence the user would have typed to ask for the
  /// same thing — which is also why it reads as English rather than as
  /// `find:names`.
  String get transcriptLabel;
}

/// Something the user typed. The only intent that is parsed.
final class AskQuestion extends AssistantIntent {
  const AskQuestion(this.question);

  final String question;

  @override
  String get transcriptLabel => question;
}

/// The document's main points, in its own words.
final class SummarizeDocument extends AssistantIntent {
  const SummarizeDocument({this.brief = false});

  /// Shorter than the default — the "short summary" action.
  final bool brief;

  @override
  String get transcriptLabel =>
      brief ? 'Give me a short summary' : 'Summarise this document';
}

/// What the document is and what it covers.
final class ExplainDocument extends AssistantIntent {
  const ExplainDocument();

  @override
  String get transcriptLabel => 'Explain this document';
}

/// What a specific piece of text says.
///
/// The text is the subject, and it arrives already chosen — the reader's
/// selection. Nothing here is searched for: the passage *is* the source.
final class ExplainSelection extends AssistantIntent {
  const ExplainSelection(this.text);

  final String text;

  @override
  String get transcriptLabel => 'Explain: $text';
}

/// A kind of fact worth pulling out of a document.
///
/// Each maps onto a shape that can be recognised on a page rather than a word
/// that has to appear on it. That is the whole reason these are actions: no
/// page says "dates" beside its dates, so asking for them as a question finds
/// nothing.
enum InformationKind {
  /// Everything below, gathered into one answer.
  important,
  names,
  dates,
  amounts,
  locations,
  references,
  contacts;

  String get transcriptLabel => switch (this) {
    InformationKind.important => 'Find important information',
    InformationKind.names => 'Find names',
    InformationKind.dates => 'Find important dates',
    InformationKind.amounts => 'Find amounts',
    InformationKind.locations => 'Find places',
    InformationKind.references => 'Find reference numbers',
    InformationKind.contacts => 'Find contact details',
  };
}

/// Pull every value of one kind out of the document.
final class FindInformation extends AssistantIntent {
  const FindInformation(this.kind);

  final InformationKind kind;

  @override
  String get transcriptLabel => kind.transcriptLabel;
}
