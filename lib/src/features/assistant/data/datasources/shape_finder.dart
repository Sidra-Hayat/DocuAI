import 'passage_extractor.dart';
import 'question_analyzer.dart';

/// One value found on a page, and the passage it was read out of.
class ShapeFinding {
  const ShapeFinding({required this.value, required this.passage});

  /// The text exactly as it appears on the page — `12/03/2026`, `€1,240.00`,
  /// `Aisha Rahman`. Never reformatted: a date normalised to ISO would no
  /// longer be something the user could point at on the scan.
  final String value;

  /// The value's own span on the page, carrying the page it was read from.
  ///
  /// Not one of the ranked sentences. A citation built from this widens around
  /// the *value*, so the source card shows the label written beside it —
  /// "Payment due: 05/04/2026" rather than whichever sentence happened to
  /// contain it.
  final Passage passage;
}

/// Lists every date, amount, name, reference or contact in a document.
///
/// A different question from the one the ranker answers. "How much is the
/// deposit" wants the passage that covers those words; "find amounts" names
/// nothing the page contains and wants every figure on it. Ranked by term
/// coverage the second question scores zero everywhere and is answered "I could
/// not find that", which is false — the amounts are right there.
///
/// So this matches on shape rather than words, using the same signals the
/// ranker already uses to boost a passage that fits an intent. Nothing is
/// interpreted: an amount is reported because it is written like an amount, and
/// the passage it came from travels with it so the user can see the label
/// beside the figure.
abstract final class ShapeFinder {
  /// Values reported before the list stops being readable.
  ///
  /// A dense statement can carry sixty figures. Past a couple of dozen the
  /// answer has become the document again, and the user would be better served
  /// by the page itself — which the citations link to.
  static const int maxFindings = 15;

  /// Reads each page once, in document order.
  ///
  /// Scans the page rather than the ranked sentences, and this is not an
  /// evasion of retrieval — the page text is what retrieval extracted, and each
  /// value is attributed back to its own span on it. Scanning the sentences
  /// instead would silently lose values: a scanned form puts `£248.60` on a
  /// line of its own, which is below [PassageExtractor.minPassageChars] and is
  /// therefore dropped before ranking ever sees it. A list of amounts that
  /// omits the total because the total was written on its own line is worse
  /// than no list.
  static List<ShapeFinding> find(
    QuestionIntent intent,
    List<Passage> passages, {
    int maxFindings = ShapeFinder.maxFindings,
  }) {
    final findings = <ShapeFinding>[];
    final seen = <String>{};

    for (final page in _pages(passages)) {
      for (final located in PassageSignals.locate(intent, page.pageText)) {
        final trimmed = _tidy(located.$2);
        if (trimmed.isEmpty) continue;

        // The same total appears in the header, the table and the footer of one
        // bill. Reporting it three times reads as three different amounts.
        if (!seen.add(_fingerprint(trimmed))) continue;

        findings.add(
          ShapeFinding(
            value: trimmed,
            passage: Passage(
              documentId: page.documentId,
              documentTitle: page.documentTitle,
              pageIndex: page.pageIndex,
              text: located.$2,
              start: located.$1,
              end: located.$1 + located.$2.length,
              pageText: page.pageText,
            ),
          ),
        );

        if (findings.length >= maxFindings) {
          return List<ShapeFinding>.unmodifiable(findings);
        }
      }
    }

    return List<ShapeFinding>.unmodifiable(findings);
  }

  /// One passage per page, in document order — whichever came first carries
  /// the page text and the metadata the rest of the page shares.
  static List<Passage> _pages(List<Passage> passages) {
    final byPage = <String, Passage>{};
    for (final passage in passages) {
      byPage.putIfAbsent(
        '${passage.documentId}#${passage.pageIndex}',
        () => passage,
      );
    }
    return byPage.values.toList(growable: false);
  }

  /// Collapses the whitespace a scan introduced and drops what a pattern ran
  /// into at either end — the sentence punctuation ("a phone number is not
  /// `+44 7700 900123.`") and any emphasis marker the value was wrapped in, so
  /// `**248.60**` is listed as an amount rather than as decoration.
  static String _tidy(String value) => value
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s.,;:*_]+|[\s.,;:*_]+$'), '');

  /// What counts as the same value.
  ///
  /// Case and internal spacing vary between the header and the table on one
  /// page; trailing punctuation is a sentence boundary the regex caught, not
  /// part of the value.
  static String _fingerprint(String value) => value
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[^\w€£$¥₹+]+|[^\w]+$'), '');

  /// What to call these in the answer.
  static String labelFor(QuestionIntent intent, {required bool plural}) =>
      switch (intent) {
        QuestionIntent.date => plural ? 'dates' : 'date',
        QuestionIntent.amount => plural ? 'amounts' : 'amount',
        QuestionIntent.person => plural ? 'names' : 'name',
        QuestionIntent.contact =>
          plural ? 'contact details' : 'contact detail',
        QuestionIntent.identifier =>
          plural ? 'reference numbers' : 'reference number',
        QuestionIntent.place => plural ? 'places' : 'place',
        QuestionIntent.general => plural ? 'entries' : 'entry',
      };
}
