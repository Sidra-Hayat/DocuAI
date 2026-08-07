import '../../../search/data/datasources/search_tokenizer.dart';
import 'synonym_index.dart';

/// What kind of thing a question is asking for.
///
/// Only the categories this corpus actually produces. Bills, contracts and
/// receipts are overwhelmingly asked when, how much, who and where, and a
/// passage carrying a date or an amount is a far better answer to those than
/// one that merely repeats the question's words back.
enum QuestionIntent { date, amount, person, place, contact, identifier, general }

/// A question, reduced to what retrieval can act on.
class AnalyzedQuestion {
  const AnalyzedQuestion({
    required this.original,
    required this.terms,
    required this.synonyms,
    required this.phrases,
    required this.intent,
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
    'about', 'after', 'again', 'all', 'am', 'an', 'and', 'any', 'are', 'as',
    'at', 'be', 'been', 'before', 'being', 'but', 'by', 'can', 'could', 'did',
    'do', 'does', 'each', 'find', 'for', 'from', 'get', 'give', 'had', 'has',
    'have', 'he', 'her', 'here', 'his', 'how', 'if', 'in', 'into', 'is', 'it',
    'its', 'just', 'know', 'me', 'much', 'my', 'need', 'no', 'not', 'of', 'on',
    'or', 'our', 'out', 'over', 'please', 'said', 'say', 'says', 'she',
    'should', 'show', 'so', 'some', 'tell', 'than', 'that', 'the', 'their',
    'them', 'then', 'there', 'these', 'they', 'this', 'to', 'up', 'us', 'was',
    'we', 'were', 'what', 'when', 'where', 'which', 'who', 'why', 'will',
    'with', 'would', 'you', 'your',
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
    'when', 'date', 'deadline', 'due', 'expires', 'expiry', 'expiration',
    'starts', 'start', 'ends', 'end', 'valid', 'renewal', 'renew', 'day',
    'month', 'year', 'period',
  };

  static const Set<String> _amountWords = <String>{
    'much', 'cost', 'costs', 'price', 'total', 'amount', 'fee', 'fees',
    'charge', 'charges', 'pay', 'paid', 'payable', 'balance', 'owe', 'owed',
    'sum', 'rate', 'refund', 'deposit', 'discount', 'tax',
  };

  static const Set<String> _personWords = <String>{
    'who', 'whom', 'whose', 'name', 'named', 'signed', 'signatory', 'tenant',
    'landlord', 'customer', 'holder', 'client', 'owner',
  };

  static const Set<String> _placeWords = <String>{
    'where', 'address', 'location', 'premises', 'property', 'city', 'street',
    'postcode', 'zip',
  };

  static const Set<String> _contactWords = <String>{
    'phone', 'telephone', 'mobile', 'email', 'contact', 'call',
  };

  static const Set<String> _identifierWords = <String>{
    'number', 'reference', 'ref', 'code', 'account', 'policy', 'invoice',
    'id', 'serial',
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

    return AnalyzedQuestion(
      original: question,
      terms: List<String>.unmodifiable(terms),
      synonyms: Set<String>.unmodifiable(SynonymIndex.expand(terms)),
      phrases: phrases,
      intent: _intentOf(all),
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
}

/// Recognises the shapes an intent boost looks for in a passage.
abstract final class PassageSignals {
  static final RegExp _numericDate = RegExp(
    r'\b\d{1,4}[./-]\d{1,2}[./-]\d{2,4}\b',
  );

  static final RegExp _writtenDate = RegExp(
    r'\b(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+\d{1,2}\b'
    r'|\b\d{1,2}\s+(?:jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b',
    caseSensitive: false,
  );

  /// A currency symbol or code next to a number, or a number written with
  /// decimals or thousands separators. Deliberately not "any digit": a page
  /// number would then count as an amount on every page.
  static final RegExp _amount = RegExp(
    r'[€£$¥₹]\s?\d|(?:\b(?:eur|usd|gbp|pkr|inr|chf)\b\s?\d)'
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
  static final RegExp _properName = RegExp(r'\b[A-Z][a-z]+\s+[A-Z][a-z]+\b');

  static bool hasDate(String text) =>
      _numericDate.hasMatch(text) || _writtenDate.hasMatch(text);

  static bool hasAmount(String text) => _amount.hasMatch(text);

  static bool hasContact(String text) =>
      _email.hasMatch(text) || _phone.hasMatch(text);

  static bool hasIdentifier(String text) => _identifier.hasMatch(text);

  static bool hasProperName(String text) => _properName.hasMatch(text);

  static bool satisfies(QuestionIntent intent, String text) => switch (intent) {
    QuestionIntent.date => hasDate(text),
    QuestionIntent.amount => hasAmount(text),
    QuestionIntent.contact => hasContact(text),
    QuestionIntent.identifier => hasIdentifier(text),
    QuestionIntent.person => hasProperName(text),
    // A place reads as ordinary prose on the page, so there is no shape to
    // match on — the terms have to carry it alone.
    QuestionIntent.place => false,
    QuestionIntent.general => false,
  };
}
