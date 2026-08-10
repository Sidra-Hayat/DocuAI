import '../../../../core/text/markup.dart';
import '../../../documents/domain/entities/document.dart';
import 'passage_extractor.dart';
import 'passage_summarizer.dart';

/// One thing a document covers, and where it says so.
class DocumentTopic {
  const DocumentTopic({required this.text, required this.pageIndex});

  /// The heading or opening clause, exactly as the document writes it.
  final String text;

  final int pageIndex;
}

/// What a document says it covers, and where that came from.
///
/// The source matters to the wording. Headings list well inline — "covers
/// Project setup, UI design and Permissions" — because that is what a heading
/// is. Sentences do not, and have to be shown as what they are.
class DocumentOutline {
  const DocumentOutline({required this.topics, required this.fromHeadings});

  const DocumentOutline.empty()
    : topics = const <DocumentTopic>[],
      fromHeadings = false;

  final List<DocumentTopic> topics;

  /// True when the document divided itself up and this is that division.
  final bool fromHeadings;

  bool get isEmpty => topics.isEmpty;
}

/// What a document is about, in the document's own words.
///
/// This is what makes "Explain this document" answerable without a language
/// model. The honest content of an explanation is not a paraphrase — there is
/// nothing here to paraphrase *with* — it is the document's own structure read
/// back: the headings it is divided into, or failing those, the sentences that
/// best stand for it.
///
/// Headings first, because a document that has them has already told you what
/// it covers. A report divided into "Project setup", "UI design",
/// "Permissions" and "Android testing" answers "what is this?" better than any
/// summary of its prose would, and every word of that answer was typed by
/// whoever wrote it.
abstract final class DocumentTopics {
  /// Topics reported before the list stops being a summary of anything.
  static const int maxTopics = 8;

  /// A heading longer than this is a sentence that happens to be marked up as
  /// one, and reads badly in a list.
  static const int maxTopicChars = 90;

  /// The document's own account of itself, best source first.
  static DocumentOutline of(Document document) {
    final headings = _headings(document);
    if (headings.isNotEmpty) {
      return DocumentOutline(topics: headings, fromHeadings: true);
    }

    return DocumentOutline(
      topics: _leadingSentences(document),
      fromHeadings: false,
    );
  }

  /// Headings, in page then document order.
  static List<DocumentTopic> _headings(Document document) {
    final topics = <DocumentTopic>[];

    // The document's own title counts as already said. A report whose first
    // heading repeats its file name would otherwise be introduced as being
    // called X and then listed as covering X.
    final seen = <String>{document.title.trim().toLowerCase()};

    for (final page in document.pages) {
      if (!page.hasText) continue;

      for (final block in Markup.parse(page.text)) {
        if (!_isHeading(block.kind)) continue;

        final text = block.text.trim();
        if (text.isEmpty || text.length > maxTopicChars) continue;
        if (!seen.add(text.toLowerCase())) continue;

        topics.add(DocumentTopic(text: text, pageIndex: page.index));
        if (topics.length >= maxTopics) return topics;
      }
    }

    return topics;
  }

  static bool _isHeading(MarkupBlockKind kind) =>
      kind == MarkupBlockKind.heading1 ||
      kind == MarkupBlockKind.heading2 ||
      kind == MarkupBlockKind.heading3;

  /// The sentences that best represent the document, for one that has no
  /// headings — a scan, almost always.
  ///
  /// The same summariser the Summarise action uses, which is deliberate: an
  /// explanation and a summary of a headingless document are drawn from the
  /// same evidence, and having two selectors would let them disagree about
  /// what the document is about.
  static List<DocumentTopic> _leadingSentences(Document document) {
    final sentences = PassageSummarizer.summarize(
      PassageExtractor.extract(document),
      maxSentences: 4,
    );

    return <DocumentTopic>[
      for (final sentence in sentences)
        DocumentTopic(
          text: _clause(Markup.toInlineText(sentence.passage.text)),
          pageIndex: sentence.passage.pageIndex,
        ),
    ];
  }

  /// Shortens a sentence to something that reads as a topic.
  ///
  /// Cut at a clause boundary rather than at a character count, so the result
  /// is a phrase the document actually contains rather than one ending
  /// mid-word with an ellipsis.
  static String _clause(String sentence) {
    final flattened = sentence.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flattened.length <= maxTopicChars) return flattened;

    final cut = flattened.lastIndexOf(RegExp(r'[,;:]'), maxTopicChars);
    if (cut > maxTopicChars ~/ 3) return flattened.substring(0, cut).trim();

    final space = flattened.lastIndexOf(' ', maxTopicChars);
    return '${flattened.substring(0, space > 0 ? space : maxTopicChars).trim()}…';
  }
}
