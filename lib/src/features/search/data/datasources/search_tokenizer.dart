import 'dart:math' as math;

/// Turns text into the terms the index stores and queries match against.
///
/// Unicode-aware rather than `[a-z0-9]`: a scanned document is as likely to
/// contain "Gebühr" or "café" as plain ASCII, and splitting those on the
/// accented character would index two fragments that no realistic query
/// reproduces.
abstract final class SearchTokenizer {
  /// Single characters are dropped. They match almost everything, and
  /// `SearchDocuments` already refuses queries shorter than two characters, so
  /// indexing them would only add weight the search can never use.
  static const int minTokenLength = 2;

  static final RegExp _separators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

  static List<String> tokenize(String text) => text
      .toLowerCase()
      .split(_separators)
      .where((token) => token.length >= minTokenLength)
      .toList(growable: false);

  /// Term frequencies for one document.
  ///
  /// The title is counted [titleWeight] times. A document called "Electricity
  /// bill" should win against one that merely mentions electricity in a
  /// paragraph, and weighting the field is the standard way to say so without
  /// a separate index.
  static Map<String, int> countTerms({
    required String title,
    required String body,
    int titleWeight = 3,
  }) {
    final counts = <String, int>{};

    for (final token in tokenize(title)) {
      counts[token] = (counts[token] ?? 0) + titleWeight;
    }
    for (final token in tokenize(body)) {
      counts[token] = (counts[token] ?? 0) + 1;
    }

    return counts;
  }
}

/// Okapi BM25 — the ranking function the assistant will also lean on in
/// Phase 7.
///
/// Chosen over raw term-frequency counting because it answers the two things
/// counting gets wrong: a term appearing twenty times is not twenty times as
/// relevant ([k1] saturates it), and a long document is not more relevant just
/// for having more words in it ([b] normalises by length).
abstract final class Bm25 {
  /// Term-frequency saturation. 1.2 is the usual default and behaves well on
  /// short documents, which scanned pages are.
  static const double k1 = 1.2;

  /// How strongly length normalisation applies. 0.75 is the standard middle
  /// ground between ignoring length entirely and dividing it out completely.
  static const double b = 0.75;

  /// Rarity of a term across the corpus.
  ///
  /// The `+ 1` inside the logarithm keeps the result non-negative: without it,
  /// a term appearing in more than half the documents scores negatively and can
  /// push a genuine match below a document that does not contain the word at
  /// all.
  static double idf({
    required int documentCount,
    required int documentsContainingTerm,
  }) => math.log(
    1 +
        (documentCount - documentsContainingTerm + 0.5) /
            (documentsContainingTerm + 0.5),
  );

  static double termScore({
    required int frequency,
    required int documentLength,
    required double averageDocumentLength,
    required double idf,
  }) {
    final normalisedLength = averageDocumentLength <= 0
        ? 1.0
        : documentLength / averageDocumentLength;
    final denominator = frequency + k1 * (1 - b + b * normalisedLength);

    return idf * (frequency * (k1 + 1)) / denominator;
  }
}
