import '../../../search/data/datasources/search_tokenizer.dart';
import 'synonym_index.dart';

/// What kind of thing a question is asking for.
///
/// Only the categories this corpus actually produces. Bills, contracts and
/// receipts are overwhelmingly asked when, how much, who and where, and a
/// passage carrying a date or an amount is a far better answer to those than
/// one that merely repeats the question's words back.
enum QuestionIntent {
  date,
  amount,
  person,
  place,
  contact,
  identifier,
  general,
}

/// What the user wants done, as opposed to what they are asking about.
///
/// The distinction matters because the existing ranker scores a passage by how
/// much of the *question* it contains, and two common requests carry nothing to
/// match on. "Summarise this document" names no term the pages hold. "Find
/// important dates" asks for a shape — a passage carrying `12/03/2026` almost
/// never contains the word "dates". Ranked by coverage, both would be answered
/// "I could not find that", which is wrong rather than merely unhelpful.
///
/// So the mode chooses which ranker runs. Retrieval, extraction and citation
/// are identical in all three.
enum QuestionMode {
  /// Find the one passage that answers the question. The default.
  answer,

  /// Pick the sentences that best represent the document as a whole.
  summary,

  /// List everything of a given shape — every date, every amount, every name.
  find,

  /// Say what a piece of text contains, and where else its terms appear.
  ///
  /// Not a paraphrase. With no language model there is nothing to paraphrase
  /// *with*, and inventing one would be the single thing this assistant
  /// promises never to do. What it can honestly offer is what the passage
  /// holds — its dates, amounts, names and references — and the other places in
  /// the library those terms turn up.
  explain,
}

/// A question, reduced to what retrieval can act on.
class AnalyzedQuestion {
  const AnalyzedQuestion({
    required this.original,
    required this.terms,
    required this.synonyms,
    required this.phrases,
    required this.intent,
    required this.mode,
    required this.subjectTerms,
    required this.contentTerms,
    this.brief = false,
    this.subject = '',
    this.subjectIsDelimited = false,
  });

  final String original;

  /// Distinct, stopword-filtered terms, in the order they were asked.
  final List<String> terms;

  /// Alternatives for [terms], from [SynonymIndex]. Kept separate so a passage
  /// containing the user's own wording still outranks one that only matches a
  /// substitute.
  final Set<String> synonyms;

  /// Quoted phrases, lower-cased. A passage must contain all of them to be
  /// considered at all — quoting is the user saying "these words, together".
  final List<String> phrases;

  final QuestionIntent intent;

  final QuestionMode mode;

  /// True when a summary was asked for in fewer words.
  final bool brief;

  /// For [QuestionMode.explain], the passage to be explained.
  final String subject;

  /// True when [subject] was marked off by a colon rather than inferred by
  /// stripping the opening verb.
  ///
  /// The difference decides whether there is a passage here at all. "Explain:
  /// Total amount due: 248.60 EUR" is someone handing over a piece of text.
  /// "Explain its features" is someone asking a question, and treating its two
  /// remaining words as a passage is what produced `This passage says: “its
  /// features”`.
  final bool subjectIsDelimited;

  /// [terms] with the words that only describe the *request* removed — the
  /// summary verbs, the intent vocabulary, the qualifiers, and the words that
  /// refer to the document itself.
  ///
  /// What is left is the part that could name a document. "Summarise the
  /// tenancy agreement" leaves `tenancy, agreement`; "Summarise this document"
  /// leaves nothing, which is the engine's only way to know it has been asked
  /// to summarise something the user never identified.
  final List<String> subjectTerms;

  /// [terms] with the words that describe the *request* removed, keeping the
  /// words that describe what is being asked about.
  ///
  /// What a passage is scored against. Coverage is a fraction — how many of the
  /// asked-for terms a passage contains — so every word that no page could
  /// possibly hold drags every passage down by the same amount. "What documents
  /// mention Aisha?" was scored as asking for three things, so the sentence
  /// naming Aisha covered one third of it and fell under the floor; the
  /// assistant then reported that it could not find a name that was sitting
  /// there in plain sight.
  ///
  /// Falls back to [terms] when filtering would leave nothing, so a question
  /// made entirely of request words is still scored against something.
  final List<String> contentTerms;

  bool get isEmpty => terms.isEmpty && phrases.isEmpty;
}

/// Turns a natural-language question into query terms and an intent.
abstract final class QuestionAnalyzer {
  /// Words carrying no retrieval signal.
  ///
  /// BM25 needs no such list — its `idf` already discounts words that appear
  /// everywhere. Passage ranking does, because it scores by *coverage*: the
  /// fraction of query terms a passage contains. Coverage treats every term as
  /// equally important, so without this list "when is the deadline" would
  /// score a passage containing only "is" at one third coverage, and a
  /// confident answer would be assembled out of a preposition.
  static const Set<String> stopwords = <String>{
    'about',
    'after',
    'again',
    'all',
    'am',
    'an',
    'and',
    'any',
    'are',
    'as',
    'at',
    'be',
    'been',
    'before',
    'being',
    'but',
    'by',
    'can',
    'could',
    'did',
    'do',
    'does',
    'each',
    'find',
    'for',
    'from',
    'get',
    'give',
    'had',
    'has',
    'have',
    'he',
    'her',
    'here',
    'his',
    'how',
    'if',
    'in',
    'into',
    'is',
    'it',
    'its',
    'just',
    'know',
    'me',
    'much',
    'my',
    'need',
    'no',
    'not',
    'of',
    'on',
    'or',
    'our',
    'out',
    'over',
    'please',
    'said',
    'say',
    'says',
    'she',
    'should',
    'show',
    'so',
    'some',
    'tell',
    'than',
    'that',
    'the',
    'their',
    'them',
    'then',
    'there',
    'these',
    'they',
    'this',
    'to',
    'up',
    'us',
    'was',
    'we',
    'were',
    'what',
    'when',
    'where',
    'which',
    'who',
    'why',
    'will',
    'with',
    'would',
    'you',
    'your',
  };

  /// Contractions expanded before tokenising.
  ///
  /// The tokeniser splits on the apostrophe, so "what's the total" would
  /// otherwise yield a stray "s" that survives stopword filtering and dilutes
  /// coverage — one meaningless term out of two makes every passage look half
  /// right.
  static const Map<String, String> _contractions = <String, String>{
    "what's": 'what is',
    "when's": 'when is',
    "where's": 'where is',
    "who's": 'who is',
    "how's": 'how is',
    "that's": 'that is',
    "there's": 'there is',
    "it's": 'it is',
    "i'm": 'i am',
    "isn't": 'is not',
    "aren't": 'are not',
    "wasn't": 'was not',
    "doesn't": 'does not',
    "don't": 'do not',
    "didn't": 'did not',
    "can't": 'can not',
    "won't": 'will not',
    "shouldn't": 'should not',
    "couldn't": 'could not',
    "i've": 'i have',
    "i'd": 'i would',
  };

  static final RegExp _quoted = RegExp('"([^"]+)"');

  static const Set<String> _dateWords = <String>{
    'when',
    'date',
    'dates',
    'deadline',
    'deadlines',
    'due',
    'expires',
    'expiry',
    'expiration',
    'starts',
    'start',
    'ends',
    'end',
    'valid',
    'renewal',
    'renew',
    'day',
    'month',
    'year',
    'period',
  };

  static const Set<String> _amountWords = <String>{
    'much',
    'cost',
    'costs',
    'price',
    'prices',
    'total',
    'totals',
    'amount',
    'amounts',
    'fee',
    'fees',
    'charge',
    'charges',
    'pay',
    'paid',
    'payable',
    'balance',
    'owe',
    'owed',
    'sum',
    'sums',
    'rate',
    'refund',
    'deposit',
    'discount',
    'tax',
    'figures',
  };

  static const Set<String> _personWords = <String>{
    'who',
    'whom',
    'whose',
    'name',
    'names',
    'named',
    'signed',
    'signatory',
    'signatories',
    'tenant',
    'landlord',
    'customer',
    'holder',
    'client',
    'owner',
    'people',
    'person',
  };

  static const Set<String> _placeWords = <String>{
    'where',
    'address',
    'addresses',
    'location',
    'locations',
    'premises',
    'property',
    'city',
    'street',
    'postcode',
    'zip',
  };

  static const Set<String> _contactWords = <String>{
    'phone',
    'phones',
    'telephone',
    'mobile',
    'email',
    'emails',
    'contact',
    'contacts',
    'call',
  };

  static const Set<String> _identifierWords = <String>{
    'number',
    'numbers',
    'reference',
    'references',
    'ref',
    'code',
    'codes',
    'account',
    'policy',
    'invoice',
    'id',
    'serial',
  };

  /// Every intent's vocabulary, for deciding whether anything in a question
  /// narrows it beyond the shape it is asking for.
  static final Set<String> _intentVocabulary = <String>{
    ..._dateWords,
    ..._amountWords,
    ..._personWords,
    ..._placeWords,
    ..._contactWords,
    ..._identifierWords,
  };

  /// Asks for the document as a whole. Both spellings, since the keyboard and
  /// the app do not have to agree on which side of the Atlantic they are on.
  static const Set<String> _summaryWords = <String>{
    'summarise',
    'summarize',
    'summarised',
    'summarized',
    'summary',
    'summaries',
    'overview',
    'gist',
    'tldr',
    'recap',
    'synopsis',
    'outline',
    // Asked for as a noun rather than as a verb: "what are the important
    // points", "the key takeaways". Vocabulary rather than another phrase to
    // match, so the wording around it does not have to be anticipated.
    'points',
    'takeaways',
    'highlights',
  };

  /// Asks for the summary to be shorter than the default.
  static const Set<String> _briefWords = <String>{
    'brief',
    'briefly',
    'short',
    'shortly',
    'quick',
    'quickly',
    'tldr',
    'concise',
    'concisely',
    'one',
    'two',
  };

  /// Opens a request to be told what a passage holds.
  static const Set<String> _explainWords = <String>{
    'explain',
    'explanation',
    'clarify',
    'meaning',
    'means',
    // "What does this mean?" is the commonest way anyone asks, and it was the
    // one spelling missing.
    'mean',
  };

  static const List<String> _summaryPhrases = <String>[
    'key points',
    'main points',
    'key takeaways',
    'in short',
  ];

  /// Asks what the document *is*, rather than for the points inside it.
  ///
  /// A distinction worth keeping. "What are the main points?" wants the
  /// document's own sentences; "What is this about?" wants to be told what kind
  /// of thing is on screen, which is what an explanation answers. Both used to
  /// produce a bulleted summary, and for the second of them that is a list of
  /// details in answer to a question about the whole.
  static const List<String> _aboutPhrases = <String>[
    'what is this',
    'what kind of document',
    'what type of document',
    'what document is this',
  ];

  /// "What is *X* about?", for any X.
  ///
  /// The phrase list above used to carry `what is this about` and `what is this
  /// document about` as literals, which meant the question worked on the
  /// document that was open and failed the moment someone named one: "what is
  /// the internship report about?" went down the answer path and reported that
  /// a document it had just identified contained nothing.
  ///
  /// The shape is what matters, not the words in the middle — a `what is …
  /// about` question asks to be told what a thing *is*, whatever fills the gap.
  /// Anchored at the end so it stays a question about identity: "what do you
  /// know about the rent" has "about" in the middle and is an ordinary
  /// question, which is the answer path and should stay there.
  static final RegExp _aboutPattern = RegExp(
    r"^(what|what's|whats)\s+(is|are|was|were|s)?\s*"
    r"[a-z0-9 '’-]{0,40}\babout\s*[?.!]*$",
  );

  /// Asks for *everything* of a kind rather than one instance. Without one of
  /// these, "when is it due" stays on the answer path — the user wants the due
  /// date, not a list of every date on the page.
  static const Set<String> _enumerationWords = <String>{
    'find',
    'list',
    'show',
    'all',
    'every',
    'any',
    'extract',
    'pull',
  };

  static const List<String> _enumerationPhrases = <String>[
    'what are the',
    'list of',
    'are there any',
  ];

  /// A shape asked for in the plural is a request for all of them.
  ///
  /// The cue that "What dates are mentioned?" needs and "When is it due?" must
  /// not have. Both reduce to nothing but request vocabulary, so neither can be
  /// told apart by what is left over — but one asks for *dates* and the other
  /// for the date something is due, and the plural is the whole of the
  /// difference. Without this, a question about a page covered in dates was
  /// answered "I could not find that".
  static const Set<String> _pluralShapeWords = <String>{
    'dates',
    'deadlines',
    'names',
    'signatories',
    'people',
    'amounts',
    'costs',
    'prices',
    'charges',
    'fees',
    'totals',
    'figures',
    'numbers',
    'references',
    'codes',
    'addresses',
    'locations',
    'contacts',
    'emails',
    'phones',
  };

  /// Verbs that ask what a document contains rather than what it says.
  ///
  /// "Who is mentioned in this document?" carries no "find" or "list", and so
  /// read as an ordinary question about the word "mentioned" — which appears on
  /// no page, so it found nothing on a document full of names.
  static const Set<String> _mentionWords = <String>{
    'mentioned',
    'mention',
    'mentions',
    'listed',
    'included',
    'contains',
    'contain',
  };

  /// Words that grade a request without narrowing it. "Important" in "find
  /// important dates" tells retrieval nothing — no page marks its dates as
  /// important — so treating it as a search term would drop the question onto
  /// the answer path and return nothing.
  static const Set<String> _qualifierWords = <String>{
    'important',
    'key',
    'main',
    'major',
    'significant',
    'relevant',
    'useful',
    'mentioned',
    'listed',
    'notable',
    'critical',
    'essential',
  };

  /// The user referring to the thing in front of them rather than naming it.
  ///
  /// "Information", "details" and "facts" belong here for the same reason
  /// "document" does: they name the contents of a page in general and none of
  /// its contents in particular. Treated as search terms they send "find
  /// important information" looking for whichever passage happens to use the
  /// word "information" — which is how that request came to be answered with an
  /// unrelated sentence.
  static const Set<String> _selfWords = <String>{
    'document',
    'documents',
    'doc',
    'file',
    'page',
    'pages',
    'text',
    'scan',
    'paper',
    'contents',
    'content',
    'information',
    'info',
    'details',
    'detail',
    'facts',
    'data',
    // Structural references to a part of what is on screen. "What does this
    // section mean?" points at the document in front of the user, not at a page
    // that contains the word "section".
    //
    // "Clause" is deliberately absent: a clause is nearly always numbered, and
    // "explain clause 4" names something specific to go and find.
    'section',
    'sections',
    'passage',
    'paragraph',
    'paragraphs',
  };

  static AnalyzedQuestion analyze(String question) {
    final phrases = _quoted
        .allMatches(question)
        .map((match) => match.group(1)!.trim().toLowerCase())
        .where((phrase) => phrase.isNotEmpty)
        .toList(growable: false);

    final normalised = _expandContractions(question.toLowerCase());
    final all = SearchTokenizer.tokenize(normalised);

    final meaningful = <String>[];
    final seen = <String>{};
    for (final token in all) {
      if (stopwords.contains(token)) continue;
      if (seen.add(token)) meaningful.add(token);
    }

    // A question made entirely of common words still deserves an attempt, so
    // the unfiltered tokens stand in rather than retrieval giving up — unless
    // a quoted phrase already says exactly what to look for.
    final terms = meaningful.isEmpty && phrases.isEmpty
        ? all.toSet().toList(growable: false)
        : meaningful;

    final intent = _intentOf(all);

    final mode = _modeOf(all, normalised, intent);

    return AnalyzedQuestion(
      original: question,
      terms: List<String>.unmodifiable(terms),
      synonyms: Set<String>.unmodifiable(SynonymIndex.expand(terms)),
      phrases: phrases,
      intent: intent,
      mode: mode,
      subjectTerms: List<String>.unmodifiable(_subjectOf(terms)),
      contentTerms: List<String>.unmodifiable(_contentOf(terms)),
      brief: mode == QuestionMode.summary && all.any(_briefWords.contains),
      subject: mode == QuestionMode.explain ? _passageOf(question) : '',
      subjectIsDelimited:
          mode == QuestionMode.explain && question.contains(':'),
    );
  }

  /// True when [text] refers to the document without naming anything in it.
  ///
  /// "this document", "this", "the page", "its contents" — all of them point at
  /// whatever the user is looking at, and none of them is a phrase to search
  /// for. Distinguishing them is what stops "Explain this document" being
  /// answered with a passage that happens to contain the word "document".
  ///
  /// Deliberately narrower than [_subjectOf]: only the words that refer to the
  /// document itself and the words that grade a request are removed, so a
  /// genuine selection made of ordinary vocabulary — "Total amount due" — is
  /// still recognised as content.
  static bool namesOnlyTheDocument(String text) {
    final tokens = SearchTokenizer.tokenize(
      _expandContractions(text.toLowerCase()),
    );

    return !tokens.any(
      (token) =>
          !stopwords.contains(token) &&
          !_selfWords.contains(token) &&
          !_qualifierWords.contains(token) &&
          !_explainWords.contains(token) &&
          !_summaryWords.contains(token),
    );
  }

  static String _expandContractions(String text) {
    var result = text;
    _contractions.forEach((contraction, expansion) {
      result = result.replaceAll(contraction, expansion);
    });
    return result;
  }

  /// Read from the *unfiltered* tokens: "when", "how" and "who" are stopwords
  /// for matching but are exactly the words that reveal what is being asked.
  ///
  /// Order matters where a question could qualify twice — "how much is the
  /// deposit due" is about the amount, and checking amount before date is what
  /// makes the more specific reading win.
  static QuestionIntent _intentOf(List<String> tokens) {
    bool anyOf(Set<String> words) => tokens.any(words.contains);

    if (anyOf(_amountWords)) return QuestionIntent.amount;
    if (anyOf(_dateWords)) return QuestionIntent.date;
    if (anyOf(_contactWords)) return QuestionIntent.contact;
    if (anyOf(_identifierWords)) return QuestionIntent.identifier;
    if (anyOf(_placeWords)) return QuestionIntent.place;
    if (anyOf(_personWords)) return QuestionIntent.person;
    return QuestionIntent.general;
  }

  /// Which ranker should run.
  ///
  /// Also read from the *unfiltered* tokens, for the same reason as the intent:
  /// "find", "show" and "all" are stopwords for matching and are precisely the
  /// words that say a list was wanted.
  static QuestionMode _modeOf(
    List<String> tokens,
    String normalised,
    QuestionIntent intent,
  ) {
    // Checked first: "explain the summary of clause 4" is a request about a
    // passage, not a request to summarise the document.
    if (tokens.any(_explainWords.contains)) return QuestionMode.explain;
    if (_aboutPhrases.any(normalised.contains) ||
        _aboutPattern.hasMatch(normalised.trim())) {
      return QuestionMode.explain;
    }

    if (tokens.any(_summaryWords.contains)) return QuestionMode.summary;
    if (_summaryPhrases.any(normalised.contains)) return QuestionMode.summary;

    // Four ways of asking for everything of a kind. The first two are explicit
    // — "find", "list all". The last two are how people actually phrase it:
    // naming the shape in the plural, or asking what the document mentions.
    final enumerating =
        tokens.any(_enumerationWords.contains) ||
        _enumerationPhrases.any(normalised.contains) ||
        tokens.any(_pluralShapeWords.contains) ||
        tokens.any(_mentionWords.contains);
    if (!enumerating) return QuestionMode.answer;

    // "Find the amount on the electricity bill" names which amount, and is a
    // question with an answer — not a request to list every figure on the
    // page. Anything left after the request vocabulary is that narrowing.
    final narrowing = tokens.where(
      (token) =>
          !stopwords.contains(token) &&
          !_enumerationWords.contains(token) &&
          !_qualifierWords.contains(token) &&
          !_mentionWords.contains(token) &&
          !_selfWords.contains(token) &&
          !_intentVocabulary.contains(token),
    );
    if (narrowing.isNotEmpty) return QuestionMode.answer;

    // A shape to recognise on the page. A place is deliberately absent: an
    // address can now be *located* on request, but "find the landlord address"
    // wants one answer rather than every address in the document, and the
    // enumeration cue alone is too weak to tell those apart.
    const shaped = <QuestionIntent>{
      QuestionIntent.date,
      QuestionIntent.amount,
      QuestionIntent.person,
      QuestionIntent.contact,
      QuestionIntent.identifier,
    };
    if (shaped.contains(intent)) return QuestionMode.find;

    // Nothing left to search *for*, and no shape named either: a request made
    // entirely of request words — "find important information", "list all".
    // There is no term on any page to look for, which is why sending it down
    // the answer path made it retrieve whichever passage happened to use the
    // word "information". It is answered with every shape at once instead.
    return intent == QuestionIntent.general
        ? QuestionMode.find
        : QuestionMode.answer;
  }

  /// The passage an explain request is about.
  ///
  /// Everything after the first colon, when there is one — the shape the
  /// Explain action produces. Otherwise the whole question minus its opening
  /// verb, so a typed "explain the standing charge" still has something to
  /// work with.
  static String _passageOf(String question) {
    final colon = question.indexOf(':');
    if (colon >= 0 && colon + 1 < question.length) {
      return question.substring(colon + 1).trim();
    }

    return question
        .replaceFirst(
          RegExp(r'^\s*(explain|clarify)\b[:\s]*', caseSensitive: false),
          '',
        )
        .trim();
  }

  /// Everything a page could actually contain.
  ///
  /// Narrower than [terms] and wider than [subjectTerms]: the request verbs go,
  /// the intent vocabulary stays. "How much is the total" keeps `total`, which
  /// a bill really does say; "what documents mention Aisha" keeps only `aisha`,
  /// because no page says "documents" or "mention" about itself.
  static List<String> _contentOf(List<String> terms) {
    final content = terms
        .where(
          (term) =>
              !_summaryWords.contains(term) &&
              !_explainWords.contains(term) &&
              !_enumerationWords.contains(term) &&
              !_qualifierWords.contains(term) &&
              !_mentionWords.contains(term) &&
              !_selfWords.contains(term),
        )
        .toList(growable: false);

    return content.isEmpty ? terms : content;
  }

  /// The part of a question that could name a document.
  ///
  /// The explain verbs are filtered alongside the summary ones, for the same
  /// reason: "explain" describes the request, not the thing requested. Without
  /// it "Explain this document" leaves the single term `explain` behind, which
  /// reads as the user having named something when they named nothing at all.
  static List<String> _subjectOf(List<String> terms) => terms
      .where(
        (term) =>
            !_summaryWords.contains(term) &&
            !_explainWords.contains(term) &&
            !_enumerationWords.contains(term) &&
            !_qualifierWords.contains(term) &&
            !_mentionWords.contains(term) &&
            !_selfWords.contains(term) &&
            !_intentVocabulary.contains(term),
      )
      .toList(growable: false);
}

/// Recognises the shapes an intent boost looks for in a passage.
abstract final class PassageSignals {
  static final RegExp _numericDate = RegExp(
    r'\b\d{1,4}[./-]\d{1,2}[./-]\d{2,4}\b',
  );

  /// Trailing year is optional but captured when present: these patterns are
  /// read for their extent as well as their presence, and "12 March" is a worse
  /// answer to "find important dates" than "12 March 2026".
  /// A month name completed properly, not merely started.
  ///
  /// `mar[a-z]*` — which this used to be — matches the "Mar" in "Marlowe", so
  /// the address "14 Marlowe Street" was reported as a date. Spelling out the
  /// legal completions and closing with `\b` means a month has to *end* where a
  /// month ends: "Mar" and "March" match, "Marlowe" does not.
  static const String _month =
      r'(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?'
      r'|jul(?:y)?|aug(?:ust)?|sep(?:t|tember)?|oct(?:ober)?|nov(?:ember)?'
      r'|dec(?:ember)?)';

  static final RegExp _writtenDate = RegExp(
    '\\b$_month'
    r'\.?\s+\d{1,2}'
    r'(?:,?\s+\d{4})?\b'
    '|\\b\\d{1,2}\\s+$_month'
    r'\b(?:,?\s+\d{4})?',
    caseSensitive: false,
  );

  static const String _currency =
      r'(?:[€£$¥₹]|\b(?:eur|usd|gbp|pkr|inr|chf)\b)';

  /// A currency symbol or code next to a number, or a number written with
  /// decimals or thousands separators. Deliberately not "any digit": a page
  /// number would then count as an amount on every page.
  ///
  /// The figure is matched to its full extent rather than stopping at the first
  /// digit, so an extracted amount reads `£248.60` and not `£2`. Detection is
  /// unaffected — the same strings match either way.
  static final RegExp _amount = RegExp(
    '$_currency'
    r'\s?\d(?:[\d ,.]*\d)?'
    r'|\b\d{1,3}(?:[ ,]\d{3})+(?:[.,]\d{1,2})?\b'
    r'|\b\d+[.,]\d{2}\b',
    caseSensitive: false,
  );

  static final RegExp _phone = RegExp(
    r'(?:\+\d[\d\s().-]{7,})|(?:\b\d[\d\s().-]{8,}\d\b)',
  );

  static final RegExp _email = RegExp(r'\b[\w.+-]+@[\w-]+\.[\w.-]+\b');

  /// A run of digits or mixed alphanumerics long enough to be a reference
  /// rather than a quantity.
  static final RegExp _identifier = RegExp(
    r'\b(?=[a-z0-9-]*\d)[a-z0-9-]{6,}\b',
    caseSensitive: false,
  );

  /// Two or more capitalised words in a row — how a name reads on a page.
  ///
  /// Spaces and tabs only, never a line break. With `\s+` the last word of one
  /// line and the first of the next were read as a pair, so a report whose
  /// heading ended "…Report" above a line beginning "Prepared by" reported
  /// "Report Prepared" as a person. Nobody wrote that phrase; the line ending
  /// did.
  static final RegExp _properName = RegExp(r'\b[A-Z][a-z]+[ \t]+[A-Z][a-z]+\b');

  /// A street address, and nothing looser.
  ///
  /// Deliberately conservative. A town or a country reads as ordinary prose,
  /// and there is no offline way to tell "Reading" the place from "reading" the
  /// activity without a gazetteer this app has no business shipping. A street
  /// type at the end of a capitalised run is a convention documents actually
  /// follow, so it is the one shape that can be claimed honestly.
  ///
  /// The complement of [_furniture], which lists these same street words as
  /// things a *name* may not contain — so "12 Baker Street" is reported as a
  /// place and never as a person.
  static final RegExp _streetAddress = RegExp(
    r'\b\d{1,4}[a-z]?[,\s]+'
    r'(?:[A-Z][a-zA-Z]+\s+){1,3}'
    r'(?:Street|St|Road|Rd|Avenue|Ave|Lane|Ln|Drive|Dr|Close|Court|Ct|'
    r'Crescent|Square|Sq|Way|Terrace|Place|Boulevard|Blvd|Parade|Row)\b\.?'
    r'|\b(?:[A-Z][a-zA-Z]+\s+){1,3}'
    r'(?:Street|Road|Avenue|Lane|Drive|Crescent|Square|Terrace|Boulevard)\b',
  );

  /// A UK-style postcode.
  ///
  /// The one postal format specific enough to match on. A five-digit ZIP would
  /// match every invoice number on the page, which is why it is absent.
  static final RegExp _postcode = RegExp(
    r'\b[A-Z]{1,2}\d[A-Z\d]?\s?\d[A-Z]{2}\b',
  );

  /// Capitalised words that are almost never part of a person's name.
  ///
  /// Titles and table headers are capitalised exactly like names — "Total
  /// Amount", "Account Number", "Payment Terms" — so the two-capitals rule
  /// alone would report a utility bill as being full of people. This is why a
  /// name is reported as a partial match and a currency figure is not:
  /// capitalisation is a convention, a currency symbol is a fact.
  static const Set<String> _furniture = <String>{
    'account',
    'address',
    'amount',
    'avenue',
    'balance',
    'bank',
    'billing',
    'card',
    'close',
    'court',
    'crescent',
    'drive',
    'lane',
    'road',
    'square',
    'street',
    'terrace',
    'way',
    'charge',
    'charges',
    'closing',
    'code',
    'conditions',
    'contact',
    'credit',
    'current',
    'customer',
    'date',
    'dates',
    'dear',
    'debit',
    'delivery',
    'description',
    'detail',
    'details',
    'due',
    'email',
    'gross',
    'grand',
    'invoice',
    'item',
    'items',
    'madam',
    'mobile',
    'month',
    'net',
    'new',
    'note',
    'notes',
    'number',
    'opening',
    'order',
    'page',
    'payable',
    'payment',
    'payments',
    'period',
    'phone',
    'please',
    'previous',
    'price',
    'quantity',
    'rate',
    'receipt',
    'reference',
    'service',
    'services',
    'shipping',
    'sir',
    'statement',
    'sub',
    'subtotal',
    'summary',
    'tax',
    'telephone',
    'terms',
    'thank',
    'thanks',
    'total',
    'unit',
    'units',
    'valid',
    'vat',
    'year',
    'your',
  };

  static bool hasDate(String text) =>
      _numericDate.hasMatch(text) || _writtenDate.hasMatch(text);

  static bool hasAmount(String text) => _amount.hasMatch(text);

  static bool hasContact(String text) =>
      _email.hasMatch(text) || _phone.hasMatch(text);

  static bool hasIdentifier(String text) => _identifier.hasMatch(text);

  static bool hasProperName(String text) => properNames(text).isNotEmpty;

  /// Runs of capitalised words that survive the [_furniture] filter.
  static List<String> properNames(String text) =>
      _locateNames(text).map((found) => found.$2).toList(growable: false);

  /// Every instance of [intent]'s shape in [text], with where it sits.
  ///
  /// The counterpart of [satisfies]. Answering a question needs only to know
  /// that a passage carries a date; listing every date needs the dates
  /// themselves — and their offsets, so a citation can be widened around the
  /// value to show the label written beside it.
  static List<(int, String)> locate(QuestionIntent intent, String text) {
    List<(int, String)> from(List<RegExp> patterns) {
      final found = <(int, String)>[];
      for (final pattern in patterns) {
        for (final match in pattern.allMatches(text)) {
          found.add((match.start, match.group(0)!));
        }
      }
      found.sort((a, b) => a.$1.compareTo(b.$1));
      return List<(int, String)>.unmodifiable(found);
    }

    return switch (intent) {
      QuestionIntent.date => from(<RegExp>[_numericDate, _writtenDate]),
      QuestionIntent.amount => from(<RegExp>[_amount]),
      QuestionIntent.contact => from(<RegExp>[_email, _phone]),
      QuestionIntent.identifier => from(<RegExp>[_identifier]),
      QuestionIntent.person => _locateNames(text),
      QuestionIntent.place => from(<RegExp>[_streetAddress, _postcode]),
      QuestionIntent.general => const <(int, String)>[],
    };
  }

  /// [locate] without the offsets.
  static List<String> matches(QuestionIntent intent, String text) =>
      locate(intent, text).map((found) => found.$2).toList(growable: false);

  static List<(int, String)> _locateNames(String text) =>
      List<(int, String)>.unmodifiable(
        _properName
            .allMatches(text)
            .where(
              (match) => !match
                  .group(0)!
                  .split(RegExp(r'\s+'))
                  .any((word) => _furniture.contains(word.toLowerCase())),
            )
            .map((match) => (match.start, match.group(0)!)),
      );

  static bool satisfies(QuestionIntent intent, String text) => switch (intent) {
    QuestionIntent.date => hasDate(text),
    QuestionIntent.amount => hasAmount(text),
    QuestionIntent.contact => hasContact(text),
    QuestionIntent.identifier => hasIdentifier(text),
    QuestionIntent.person => hasProperName(text),
    // Deliberately not [hasPlace], even though one now exists. This drives the
    // *ranker's* boost for questions like "where is the property", and a street
    // pattern is far rarer than a date or an amount: a document that mentions
    // one address would have that passage boosted above the one that actually
    // answers. Listing places on request is a different job, and [locate] does
    // it without touching how questions are ranked.
    QuestionIntent.place => false,
    QuestionIntent.general => false,
  };

  /// Whether [text] carries a street address or postcode.
  static bool hasPlace(String text) =>
      _streetAddress.hasMatch(text) || _postcode.hasMatch(text);
}
