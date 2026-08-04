import 'dart:math' as math;

import '../../../search/data/datasources/search_tokenizer.dart';
import 'passage_extractor.dart';
import 'question_analyzer.dart';

class RankedPassage {
  const RankedPassage({
    required this.passage,
    required this.score,
    required this.coverage,
  });

  final Passage passage;
  final double score;

  /// Fraction of the question's terms this passage contains.
  final double coverage;
}

/// Scores passages against a question.
///
/// A different function from BM25 on purpose. BM25 ranks *documents* across a
/// corpus, where the hard problem is rarity — which is why it is built around
/// `idf`. By the time passages are being ranked, every candidate already comes
/// from a document known to be relevant, and rarity has been accounted for.
/// What matters now is which span of text most completely contains the
/// question.
///
/// Every factor below is bounded, and they multiply. That means no single
/// signal can run away with the ranking, and a passage missing the question's
/// terms cannot be rescued by being the right length or sitting in a strongly
/// matching document.
abstract final class PassageRanker {
  /// Passages near this length carry a full statement without burying it.
  static const int idealTokens = 25;

  /// Multiplier for a passage that answers the *kind* of question asked.
  static const double intentBoost = 1.35;

  /// With two or more query terms, a passage must contain at least half of
  /// them. Without this floor a single incidental word produces a passage that
  /// looks like an answer, which is worse than admitting nothing was found.
  static const double minCoverage = 0.5;

  static List<RankedPassage> rank({
    required AnalyzedQuestion question,
    required List<Passage> passages,
    required Map<String, double> documentPriors,
  }) {
    if (question.isEmpty) return const <RankedPassage>[];

    final ranked = <RankedPassage>[];

    for (final passage in passages) {
      final tokens = SearchTokenizer.tokenize(passage.text);
      if (tokens.isEmpty) continue;

      final scored = _score(
        question: question,
        passage: passage,
        tokens: tokens,
        prior: documentPriors[passage.documentId] ?? 1,
      );
      if (scored != null) ranked.add(scored);
    }

    ranked.sort((a, b) => b.score.compareTo(a.score));
    return ranked;
  }

  static RankedPassage? _score({
    required AnalyzedQuestion question,
    required Passage passage,
    required List<String> tokens,
    required double prior,
  }) {
    var occurrences = 0;
    var firstMatch = -1;
    var lastMatch = -1;
    final matched = <String>{};

    for (var i = 0; i < tokens.length; i++) {
      if (!question.terms.contains(tokens[i])) continue;
      matched.add(tokens[i]);
      occurrences++;
      if (firstMatch < 0) firstMatch = i;
      lastMatch = i;
    }

    if (matched.isEmpty) return null;

    final coverage = matched.length / question.terms.length;
    if (question.terms.length > 1 && coverage < minCoverage) return null;

    // Saturating, for the same reason BM25 saturates term frequency: the
    // twentieth occurrence of a word says little the second did not.
    final frequency = 1 + math.log(1 + occurrences);

    // Terms sitting close together are likelier to form one statement than the
    // same terms scattered across a paragraph.
    final span = (lastMatch - firstMatch).abs();
    final proximity = 1 / (1 + span / tokens.length);

    // Symmetric penalty away from a readable length: fragments lack the
    // context to stand alone, paragraphs bury the answer inside themselves.
    final lengthNorm =
        1 / (1 + (tokens.length - idealTokens).abs() / idealTokens);

    final intent = PassageSignals.satisfies(question.intent, passage.text)
        ? intentBoost
        : 1.0;

    return RankedPassage(
      passage: passage,
      coverage: coverage,
      score: coverage * frequency * proximity * lengthNorm * intent * prior,
    );
  }

  /// Normalises document scores into a bounded multiplier.
  ///
  /// BM25 scores are unbounded and only comparable within one result set, so
  /// multiplying by them directly would let a single strong document dominate
  /// every passage decision. Mapping them onto 0.5–1.0 keeps the document's
  /// relevance as a nudge rather than a verdict.
  static Map<String, double> priorsFrom(Map<String, double> documentScores) {
    if (documentScores.isEmpty) return const <String, double>{};

    final highest = documentScores.values.reduce(math.max);
    if (highest <= 0) {
      return <String, double>{for (final id in documentScores.keys) id: 1};
    }

    return <String, double>{
      for (final entry in documentScores.entries)
        entry.key: 0.5 + 0.5 * (entry.value / highest),
    };
  }
}
