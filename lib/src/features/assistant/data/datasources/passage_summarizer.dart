import 'dart:math' as math;

import '../../../search/data/datasources/search_tokenizer.dart';
import 'passage_extractor.dart';
import 'question_analyzer.dart';
import 'shape_finder.dart';

/// A sentence chosen for a summary, and what made it worth choosing.
class SummarySentence {
  const SummarySentence({
    required this.passage,
    required this.weight,
    required this.highlights,
  });

  final Passage passage;

  /// Salience relative to the strongest sentence kept, 0–1. Comparable within
  /// one summary only — exactly like the relevance on a citation, and for the
  /// same reason: these scores mean nothing across documents.
  final double weight;

  /// The terms that carried this sentence's score, strongest first. Shown on
  /// the citation so a summary line explains why it was picked rather than
  /// asking to be trusted.
  final List<String> highlights;
}

/// Chooses the sentences that best represent a document.
///
/// Extractive, like everything else here: the summary is sentences lifted from
/// the pages, never a paraphrase. That is not a limitation worked around — it
/// is what lets an offline app summarise at all without a language model, and
/// what makes every line of the result checkable against the scan it came from.
///
/// The scoring is a variant of the classical centroid method. A term matters in
/// proportion to how often the document uses it, discounted by how many
/// sentences it appears in; a sentence matters by the mean significance of the
/// terms it carries. Three corrections follow, each for a failure that turns up
/// immediately on real scans:
///
///  * **Length.** Unnormalised, the longest sentence wins every time.
///  * **Lead.** Documents state what they are at the top — the header block of
///    a bill says more about it than any clause in the middle.
///  * **Fact shape.** A line stating something concrete — a date, a figure, a
///    reference — is preferred over prose that states nothing.
///
/// Selection is then greedy with a redundancy check, and the survivors are put
/// back into document order. A summary that reads top to bottom is worth more
/// than one ordered by a score the reader cannot see.
///
/// What this is and is not: it picks the sentences that say what the document
/// is *about*, and it is not a way to pull one particular figure out of a
/// dense form — on a bill with a dozen label-and-value lines, five of them
/// will not be the five any given reader wanted. That job belongs to
/// [ShapeFinder], which lists every amount or date outright, and which is
/// offered beside the summary for exactly that reason.
abstract final class PassageSummarizer {
  /// Sentences in a summary.
  ///
  /// Five is about where a summary stops being one. Long documents get more
  /// text per sentence, not more sentences.
  static const int maxSentences = 5;

  /// Above this token overlap with an already-chosen sentence, a candidate is
  /// dropped as a restatement.
  ///
  /// Scanned documents repeat themselves constantly — a total appears in the
  /// header, the table and the footer — and three phrasings of one fact make a
  /// summary that says one thing five times.
  static const double redundancyThreshold = 0.6;

  /// Length a summary sentence is scored against, in tokens.
  static const int idealTokens = 22;

  /// Applied to the opening sentences of the first page.
  static const double leadBoost = 1.2;

  /// How many opening sentences count as the lead.
  static const int leadSentences = 3;

  /// Applied to a sentence carrying a date, an amount, a reference or contact
  /// details.
  static const double factBoost = 1.25;

  static List<SummarySentence> summarize(
    List<Passage> passages, {
    int maxSentences = PassageSummarizer.maxSentences,
    int characterBudget = 900,
  }) {
    if (passages.isEmpty) return const <SummarySentence>[];

    final tokens = <List<String>>[
      for (final passage in passages) SearchTokenizer.tokenize(passage.text),
    ];

    final significance = _significance(tokens);
    if (significance.isEmpty) return const <SummarySentence>[];

    final scored = <(int index, double score, List<String> highlights)>[];
    for (var i = 0; i < passages.length; i++) {
      final scoredSentence = _score(
        passage: passages[i],
        tokens: tokens[i],
        significance: significance,
        isLead: passages[i].pageIndex == 0 && i < leadSentences,
      );
      if (scoredSentence != null) {
        scored.add((i, scoredSentence.$1, scoredSentence.$2));
      }
    }

    if (scored.isEmpty) return const <SummarySentence>[];
    scored.sort((a, b) => b.$2.compareTo(a.$2));

    final chosen = <(int index, double score, List<String> highlights)>[];
    final chosenTokens = <Set<String>>[];
    var characters = 0;

    for (final candidate in scored) {
      final candidateTokens = tokens[candidate.$1].toSet();
      if (chosenTokens.any(
        (taken) => _overlap(candidateTokens, taken) >= redundancyThreshold,
      )) {
        continue;
      }

      final length = passages[candidate.$1].text.length;
      if (characters + length > characterBudget && chosen.isNotEmpty) break;

      chosen.add(candidate);
      chosenTokens.add(candidateTokens);
      characters += length;

      if (chosen.length >= maxSentences) break;
    }

    final best = chosen.first.$2;

    // Back into document order. The reader has no access to the scores, so an
    // ordering by score reads as arbitrary — and a summary whose second line
    // precedes its first in the document is actively confusing.
    chosen.sort((a, b) {
      final byPage = passages[a.$1].pageIndex.compareTo(
        passages[b.$1].pageIndex,
      );
      return byPage != 0
          ? byPage
          : passages[a.$1].start.compareTo(passages[b.$1].start);
    });

    return List<SummarySentence>.unmodifiable(<SummarySentence>[
      for (final candidate in chosen)
        SummarySentence(
          passage: passages[candidate.$1],
          weight: best <= 0 ? 0 : (candidate.$2 / best).clamp(0, 1),
          highlights: candidate.$3,
        ),
    ]);
  }

  /// Bare digits, which the tokeniser emits for every date and figure.
  static final RegExp _numeric = RegExp(r'^\d+$');

  /// How much each term says about this document.
  ///
  /// `tf` alone would crown whatever the page header repeats — the supplier's
  /// name on every one of forty lines. Dividing the document frequency out
  /// keeps a term that is used often but not everywhere, which is what a term
  /// worth summarising around looks like.
  ///
  /// Numbers are excluded outright. No document is *about* the number 248, but
  /// a figure tokenises into digits that appear exactly once, which is the
  /// profile of a maximally significant term — so counting them buries the
  /// words. Measured on a utility bill it made "Total amount due: £248.60"
  /// and "Invoice date: 12/03/2026" score identically, the digits having
  /// drowned out everything the two lines actually say. That a sentence
  /// carries a figure at all is worth knowing, and [factBoost] is where that
  /// belongs.
  static Map<String, double> _significance(List<List<String>> tokens) {
    final frequency = <String, int>{};
    final documentFrequency = <String, int>{};

    for (final sentence in tokens) {
      final seen = <String>{};
      for (final token in sentence) {
        if (QuestionAnalyzer.stopwords.contains(token)) continue;
        if (token.length < 2 || _numeric.hasMatch(token)) continue;
        frequency[token] = (frequency[token] ?? 0) + 1;
        if (seen.add(token)) {
          documentFrequency[token] = (documentFrequency[token] ?? 0) + 1;
        }
      }
    }

    if (frequency.isEmpty) return const <String, double>{};

    final highest = frequency.values.reduce(math.max);
    final sentences = tokens.length;

    return <String, double>{
      for (final entry in frequency.entries)
        entry.key:
            (entry.value / highest) *
            math.log((sentences + 1) / (documentFrequency[entry.key] ?? 1)),
    };
  }

  static (double, List<String>)? _score({
    required Passage passage,
    required List<String> tokens,
    required Map<String, double> significance,
    required bool isLead,
  }) {
    final distinct = tokens.toSet()
      ..removeWhere(
        (token) =>
            QuestionAnalyzer.stopwords.contains(token) ||
            !significance.containsKey(token),
      );
    if (distinct.isEmpty) return null;

    // Mean, not sum. Summing looks more principled — [lengthNorm] appears to
    // be normalising for length already — but it is measurably worse here,
    // because `lengthNorm` is not a length normaliser. It is a preference for
    // a *target* length, penalising symmetrically either side of
    // [idealTokens], so on a scanned form it is already working against the
    // short label-and-value lines that carry the content. Summing compounds
    // that instead of offsetting it: measured on a utility bill it replaced
    // the account number and the due date with "Payment may be made by direct
    // debit or bank transfer".
    var total = 0.0;
    for (final token in distinct) {
      total += significance[token]!;
    }
    final salience = total / distinct.length;
    if (salience <= 0) return null;

    final lengthNorm =
        1 / (1 + (tokens.length - idealTokens).abs() / idealTokens);

    final carriesFact =
        PassageSignals.hasDate(passage.text) ||
        PassageSignals.hasAmount(passage.text) ||
        PassageSignals.hasIdentifier(passage.text) ||
        PassageSignals.hasContact(passage.text);

    final ranked = distinct.toList(growable: false)
      ..sort((a, b) => significance[b]!.compareTo(significance[a]!));

    return (
      salience *
          lengthNorm *
          (isLead ? leadBoost : 1.0) *
          (carriesFact ? factBoost : 1.0),
      List<String>.unmodifiable(ranked.take(3)),
    );
  }

  /// Jaccard similarity — shared tokens over total distinct tokens.
  static double _overlap(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final shared = a.intersection(b).length;
    return shared / (a.length + b.length - shared);
  }
}
