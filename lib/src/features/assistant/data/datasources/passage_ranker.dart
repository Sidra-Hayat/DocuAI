import 'dart:math' as math;

import '../../../search/data/datasources/search_tokenizer.dart';
import 'passage_extractor.dart';
import 'question_analyzer.dart';
import 'synonym_index.dart';

class RankedPassage {
  const RankedPassage({
    required this.passage,
    required this.score,
    required this.coverage,
    required this.matchedTerms,
    required this.satisfiesIntent,
  });

  final Passage passage;
  final double score;

  /// How much of the question this passage covered, 0–1. Synonym matches count
  /// for less than the user's own wording.
  final double coverage;

  /// The question's own terms this passage contained, in question order. What
  /// a citation shows to explain why it was cited.
  final List<String> matchedTerms;

  /// Whether the passage carries the shape the question asked for — a date for
  /// a "when", an amount for a "how much".
  final bool satisfiesIntent;
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
/// Every factor below is bounded, and they multiply. No single signal can run
/// away with the ranking, and a passage missing the question's terms cannot be
/// rescued by being the right length or sitting in a strongly matching
/// document.
abstract final class PassageRanker {
  /// Passages near this length carry a full statement without burying it.
  static const int idealTokens = 25;

  /// Multiplier for a passage that answers the *kind* of question asked.
  static const double intentBoost = 1.35;

  /// With two or more query terms, a passage must cover at least half of them.
  /// Without this floor a single incidental word produces a passage that looks
  /// like an answer, which is worse than admitting nothing was found.
  static const double minCoverage = 0.5;

  static List<RankedPassage> rank({
    required AnalyzedQuestion question,
    required List<Passage> passages,
    required Map<String, double> documentPriors,
  }) {
    if (question.isEmpty) return const <RankedPassage>[];

    final ranked = <RankedPassage>[];

    for (final passage in passages) {
      final scored = _score(
        question: question,
        passage: passage,
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
    required double prior,
  }) {
    final tokens = SearchTokenizer.tokenize(passage.text);
    if (tokens.isEmpty) return null;

    // A quoted phrase is the user saying "these words, in this order". A
    // passage missing any of them is not a partial match, it is the wrong
    // passage.
    final haystack = passage.text.toLowerCase();
    for (final phrase in question.phrases) {
      if (!haystack.contains(phrase)) return null;
    }

    final present = tokens.toSet();

    var credit = 0.0;
    var occurrences = 0;
    var firstMatch = -1;
    var lastMatch = -1;
    final matchedTerms = <String>[];

    for (final term in question.contentTerms) {
      if (present.contains(term)) {
        credit += 1;
        matchedTerms.add(term);
        continue;
      }

      // Fall back to the curated alternatives. Worth less than the user's own
      // word, because a passage containing what they actually typed is better
      // evidence than one containing what the app decided was equivalent.
      final alternatives = SynonymIndex.alternativesFor(term);
      if (alternatives.any(present.contains)) credit += SynonymIndex.weight;
    }

    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      final isMatch =
          question.contentTerms.contains(token) ||
          question.synonyms.contains(token);
      if (!isMatch) continue;

      occurrences++;
      if (firstMatch < 0) firstMatch = i;
      lastMatch = i;
    }

    // A quoted phrase that matched is itself full coverage, even when the
    // loose terms around it did not land.
    // Scored against what a page could hold, not against the whole sentence.
    // A request word cannot appear on any page, so counting one would put every
    // passage the same distance below the floor — see [contentTerms].
    final coverage = question.contentTerms.isEmpty
        ? (question.phrases.isEmpty ? 0.0 : 1.0)
        : math.min(1.0, credit / question.contentTerms.length);

    if (coverage <= 0 && question.phrases.isEmpty) return null;
    if (question.contentTerms.length > 1 &&
        question.phrases.isEmpty &&
        coverage < minCoverage) {
      return null;
    }

    // Saturating, for the same reason BM25 saturates term frequency: the
    // twentieth occurrence of a word says little the second did not.
    final frequency = 1 + math.log(1 + occurrences);

    // Terms sitting close together are likelier to form one statement than the
    // same terms scattered across a paragraph.
    final span = firstMatch < 0 ? 0 : (lastMatch - firstMatch).abs();
    final proximity = 1 / (1 + span / tokens.length);

    // Symmetric penalty away from a readable length: fragments lack the
    // context to stand alone, paragraphs bury the answer inside themselves.
    final lengthNorm =
        1 / (1 + (tokens.length - idealTokens).abs() / idealTokens);

    final satisfiesIntent = PassageSignals.satisfies(
      question.intent,
      passage.text,
    );

    return RankedPassage(
      passage: passage,
      coverage: coverage,
      matchedTerms: List<String>.unmodifiable(matchedTerms),
      satisfiesIntent: satisfiesIntent,
      score:
          coverage *
          frequency *
          proximity *
          lengthNorm *
          (satisfiesIntent ? intentBoost : 1.0) *
          prior,
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
