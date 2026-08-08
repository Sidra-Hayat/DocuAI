import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../documents/domain/entities/document.dart';

part 'search_hit.freezed.dart';

/// Where a query matched, which is what decides the order results appear in.
///
/// Ordered by priority: someone who types a document's name wants that
/// document, not a page that happens to mention the words. Ranking within a
/// kind only settles ties among equals.
enum SearchMatchKind {
  /// The query is the document's title.
  exactTitle,

  /// Every query term appears in the title, but the query is not the whole
  /// title.
  partialTitle,

  /// The query appears in the text word-for-word, in order.
  ///
  /// Above BM25 because a phrase is a much stronger statement of intent than
  /// the same words scattered across a page: someone typing "total amount
  /// due" wants the document that says exactly that, not the one that
  /// happens to use all three words in different paragraphs.
  exactPhrase,

  /// Matched recognised page text, ranked by BM25.
  content,

  /// Matched a tag and nothing else.
  tag;

  /// Lower sorts first.
  int get priority => index;

  String get label => switch (this) {
    SearchMatchKind.exactTitle => 'Title',
    SearchMatchKind.partialTitle => 'Title',
    SearchMatchKind.exactPhrase => 'Phrase',
    SearchMatchKind.content => 'Text',
    SearchMatchKind.tag => 'Tag',
  };
}

/// One document matched by a query, with the evidence for why it matched.
///
/// Carries the whole [Document] rather than just its id so the results list
/// renders thumbnails and titles without a second read per row — the library is
/// already in memory, and N extra Hive lookups while typing is exactly the cost
/// the debounce in `AppConstants.searchDebounce` exists to avoid.
@freezed
abstract class SearchHit with _$SearchHit {
  const SearchHit._();

  const factory SearchHit({
    required Document document,

    /// Relevance *within this hit's [kind]* — BM25 for content, a coverage
    /// fraction for titles and tags. Comparable only against hits of the same
    /// kind in the same result set, which is why sorting goes by kind first.
    required double score,

    @Default(SearchMatchKind.content) SearchMatchKind kind,

    /// Matching passages, most relevant first. Empty when the query matched the
    /// title or a tag but no page text.
    @Default(<SearchSnippet>[]) List<SearchSnippet> snippets,

    /// Tags the query matched, for the result row to show why.
    @Default(<String>[]) List<String> matchedTags,
  }) = _SearchHit;

  SearchSnippet? get bestSnippet => snippets.isEmpty ? null : snippets.first;

  bool get matchedTitleOnly => snippets.isEmpty && matchedTags.isEmpty;

  bool get matchedTitle =>
      kind == SearchMatchKind.exactTitle || kind == SearchMatchKind.partialTitle;
}

/// A short window of page text around a match, ready to render with the
/// matching term emphasised.
@freezed
abstract class SearchSnippet with _$SearchSnippet {
  const SearchSnippet._();

  const factory SearchSnippet({
    /// Page the passage came from, zero-based.
    required int pageIndex,

    /// The excerpt itself, already trimmed to a displayable length.
    required String text,

    /// Offset of the match **within [text]**, not within the full page — the
    /// snippet is what gets rendered, so the highlight must be relative to it.
    required int highlightStart,
    required int highlightLength,
  }) = _SearchSnippet;

  int get highlightEnd => highlightStart + highlightLength;

  /// Guards against an index built by an older version disagreeing with the
  /// current text; a malformed range is rendered unhighlighted rather than
  /// throwing a `RangeError` inside a `build`.
  bool get hasValidHighlight =>
      highlightStart >= 0 && highlightLength > 0 && highlightEnd <= text.length;
}
