import '../../../search/data/datasources/search_tokenizer.dart';

/// What kind of thing a question is asking for.
///
/// Only the two that matter for this corpus. Bills, invoices and agreements
/// are overwhelmingly asked "when is it due" and "how much is it", and a
/// passage carrying a date or an amount is a far better answer to those than
/// one that merely repeats the question's words.
enum QuestionIntent { date, amount, general }

/// A question, reduced to what retrieval can act on.
class AnalyzedQuestion {
  const AnalyzedQuestion({
    required this.original,
    required this.terms,
    required this.intent,
  });

  final String original;

  /// Distinct, stopword-filtered terms, in the order they were asked.
  final List<String> terms;

  final QuestionIntent intent;

  bool get isEmpty => terms.isEmpty;
}

/// Turns a natural-language question into query terms and an intent.
abstract final class QuestionAnalyzer {
  /// Words carrying no retrieval signal.
  ///
  /// BM25 needs no such list — its `idf` already discounts words that appear
  /// everywhere. Passage ranking does, because it scores by *coverage*: the
  /// fraction of query terms a passage contains. Coverage treats every term as
  /// equally important, so without this list "when is the deadline" would score
  /// a passage containing only "is" at one third coverage, and a confident
  /// answer would be assembled out of a preposition.
  static const Set<String> stopwords = <String>{
    'about', 'after', 'all', 'am', 'an', 'and', 'any', 'are', 'as', 'at',
    'be', 'been', 'before', 'being', 'but', 'by', 'can', 'did', 'do', 'does',
    'for', 'from', 'get', 'had', 'has', 'have', 'he', 'her', 'his', 'how',
    'if', 'in', 'into', 'is', 'it', 'its', 'me', 'my', 'no', 'not', 'of',
    'on', 'or', 'our', 'out', 'over', 'she', 'should', 'so', 'some',
    'tell', 'than', 'that', 'the', 'their', 'them', 'then', 'there', 'these',
    'they', 'this', 'to', 'up', 'us', 'was', 'we', 'were', 'what', 'when',
    'where', 'which', 'who', 'why', 'will', 'with', 'would', 'you', 'your',
  };

  static const Set<String> _dateWords = <String>{
    'when', 'date', 'deadline', 'due', 'expires', 'expiry', 'expiration',
    'starts', 'ends', 'valid', 'renewal', 'renew', 'day',
  };

  static const Set<String> _amountWords = <String>{
    'much', 'cost', 'costs', 'price', 'total', 'amount', 'fee', 'fees',
    'charge', 'charges', 'pay', 'paid', 'payable', 'balance', 'owe', 'owed',
    'sum', 'rate',
  };

  static AnalyzedQuestion analyze(String question) {
    final all = SearchTokenizer.tokenize(question);

    final meaningful = <String>[];
    final seen = <String>{};
    for (final token in all) {
      if (stopwords.contains(token)) continue;
      if (seen.add(token)) meaningful.add(token);
    }

    // A question made entirely of common words still deserves an attempt, so
    // the unfiltered tokens stand in rather than retrieval giving up.
    final terms = meaningful.isEmpty
        ? all.toSet().toList(growable: false)
        : meaningful;

    return AnalyzedQuestion(
      original: question,
      terms: List<String>.unmodifiable(terms),
      intent: _intentOf(all),
    );
  }

  /// Read from the *unfiltered* tokens: "when" and "how" are stopwords for
  /// matching but are exactly the words that reveal what is being asked.
  static QuestionIntent _intentOf(List<String> tokens) {
    for (final token in tokens) {
      if (_dateWords.contains(token)) return QuestionIntent.date;
    }
    for (final token in tokens) {
      if (_amountWords.contains(token)) return QuestionIntent.amount;
    }
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

  static bool hasDate(String text) =>
      _numericDate.hasMatch(text) || _writtenDate.hasMatch(text);

  static bool hasAmount(String text) => _amount.hasMatch(text);

  static bool satisfies(QuestionIntent intent, String text) => switch (intent) {
    QuestionIntent.date => hasDate(text),
    QuestionIntent.amount => hasAmount(text),
    QuestionIntent.general => false,
  };
}
