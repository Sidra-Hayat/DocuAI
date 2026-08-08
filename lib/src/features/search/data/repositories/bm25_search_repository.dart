import 'dart:math' as math;

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/text/markup.dart';
import '../../../documents/domain/entities/document.dart';
import '../../../documents/domain/repositories/document_repository.dart';
import '../../domain/entities/search_hit.dart';
import '../../domain/repositories/search_repository.dart';
import '../datasources/search_index_local_data_source.dart';
import '../datasources/search_tokenizer.dart';

/// Search across titles, recognised text and tags.
///
/// Results are ordered by *where* the match happened before how strong it was.
/// Someone typing a document's name wants that document; a page elsewhere that
/// happens to contain the same words is a worse answer no matter how well it
/// scores. BM25 still decides the order of content matches among themselves —
/// it is the right tool for ranking text, and the wrong tool for deciding that
/// text beats a title.
class Bm25SearchRepository implements SearchRepository {
  const Bm25SearchRepository({
    required SearchIndexLocalDataSource index,
    required DocumentRepository documents,
  }) : _index = index,
       _documents = documents;

  final SearchIndexLocalDataSource _index;
  final DocumentRepository _documents;

  /// Beyond this nobody scrolls, and every extra hit costs a snippet scan over
  /// a document's full text.
  static const int maxResults = 50;

  /// Passages shown per hit.
  static const int maxSnippetsPerHit = 3;

  /// Characters of context either side of a match.
  static const int snippetRadius = 60;

  @override
  FutureResult<List<SearchHit>> search(String query) async {
    try {
      final terms = SearchTokenizer.tokenize(query).toSet().toList();
      if (terms.isEmpty) return const Success(<SearchHit>[]);

      final entries = _index.readAll();
      if (entries.isEmpty) return const Success(<SearchHit>[]);

      // Loaded before scoring, not after. Deciding whether a document contains
      // the query *as a phrase* needs its actual text, which a forward index of
      // term counts cannot answer — and the library is read for snippets
      // anyway, so this costs nothing but a reordering.
      final loaded = await _documents.getDocuments();
      final List<Document> documents;
      switch (loaded) {
        case Failed(:final failure):
          return Failed(failure);
        case Success(:final value):
          documents = value;
      }

      final byId = <String, Document>{
        for (final document in documents) document.id: document,
      };

      final phrase = phrasePatternFor(query);
      final scored = _score(query, terms, entries, byId, phrase);
      if (scored.isEmpty) return const Success(<SearchHit>[]);

      // Kind first, then score within the kind. This is what "priority" means:
      // a weak title match still beats a strong content match.
      scored.sort((a, b) {
        final byKind = a.kind.priority.compareTo(b.kind.priority);
        return byKind != 0 ? byKind : b.score.compareTo(a.score);
      });

      final hits = <SearchHit>[];
      for (final match in scored) {
        // The index can outlive the document it describes if a delete failed
        // to de-index. Skipping is right: a hit that opens nothing is worse
        // than a missing hit, and `rebuildIndex` repairs the entry later.
        final document = byId[match.id];
        if (document == null) continue;

        hits.add(
          SearchHit(
            document: document,
            score: match.score,
            kind: match.kind,
            matchedTags: match.matchedTags,
            // Passages are worth showing whenever the text contains the query,
            // even for a title match — seeing where else it appears is useful.
            snippets: _snippetsFor(document, terms, phrase),
          ),
        );
        if (hits.length >= maxResults) break;
      }

      return Success(List<SearchHit>.unmodifiable(hits));
    } on CacheException catch (error, stackTrace) {
      return Failed(
        StorageFailure(error.message, cause: error, stackTrace: stackTrace),
      );
    } catch (error, stackTrace) {
      return Failed(
        StorageFailure(
          'The search index could not be read.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  FutureResult<void> indexDocument(Document document) =>
      _guard(() => _index.write(entryFor(document)));

  @override
  FutureResult<void> removeFromIndex(String documentId) =>
      _guard(() => _index.remove(documentId));

  @override
  FutureResult<void> rebuildIndex(List<Document> documents) => _guard(
    () => _index.replaceAll(
      documents.map(entryFor),
      fingerprint: fingerprintOf(documents),
    ),
  );

  // ---- Scoring -------------------------------------------------------------

  List<_Match> _score(
    String query,
    List<String> terms,
    List<IndexedDocument> entries,
    Map<String, Document> byId,
    RegExp? phrase,
  ) {
    final normalisedQuery = SearchTokenizer.tokenize(query).join(' ');

    final withBody = entries.where((entry) => entry.bodyLength > 0).toList();
    final averageLength = withBody.isEmpty
        ? 0.0
        : withBody.fold<int>(0, (sum, entry) => sum + entry.bodyLength) /
              withBody.length;

    final matches = <_Match>[];

    for (final entry in entries) {
      final titleTokens = SearchTokenizer.tokenize(entry.title);

      // Tier 0 — the query *is* the title.
      if (titleTokens.join(' ') == normalisedQuery) {
        matches.add(
          _Match(
            id: entry.id,
            kind: SearchMatchKind.exactTitle,
            // Shorter titles win: "Rent" is a tighter answer to "rent" than
            // "Rent and utilities summary" would be.
            score: 1 / (1 + titleTokens.length),
          ),
        );
        continue;
      }

      // Tier 1 — every query term appears in the title.
      final inTitle = terms.where(entry.titleTerms.contains).length;
      if (inTitle == terms.length) {
        matches.add(
          _Match(
            id: entry.id,
            kind: SearchMatchKind.partialTitle,
            score: inTitle / math.max(1, titleTokens.length),
          ),
        );
        continue;
      }

      // Tier 2 — the query appears word-for-word in the text.
      if (phrase != null) {
        final body = byId[entry.id]?.extractedText ?? '';
        final occurrences = phrase.allMatches(body).length;

        if (occurrences > 0) {
          matches.add(
            _Match(
              id: entry.id,
              kind: SearchMatchKind.exactPhrase,
              // Density, not a raw count: a receipt saying it once in twenty
              // words is more about the phrase than a forty-page contract
              // that mentions it once.
              score: occurrences / math.max(1, entry.bodyLength),
            ),
          );
          continue;
        }
      }

      // Tier 3 — recognised text, ranked by BM25 exactly as before.
      final bodyScore = _bm25(terms, entry, entries.length, averageLength);
      if (bodyScore > 0) {
        matches.add(
          _Match(id: entry.id, kind: SearchMatchKind.content, score: bodyScore),
        );
        continue;
      }

      // Tier 4 — a tag, and nothing else.
      final matchedTags = terms.where(entry.tagTerms.contains).toList();
      if (matchedTags.isNotEmpty) {
        matches.add(
          _Match(
            id: entry.id,
            kind: SearchMatchKind.tag,
            score: matchedTags.length / terms.length,
            matchedTags: matchedTags,
          ),
        );
        continue;
      }

      // A partial title match is still better than nothing, but only once
      // every stronger signal has been ruled out.
      if (inTitle > 0) {
        matches.add(
          _Match(
            id: entry.id,
            kind: SearchMatchKind.partialTitle,
            score: inTitle / terms.length * 0.5,
          ),
        );
      }
    }

    return matches;
  }

  static double _bm25(
    List<String> terms,
    IndexedDocument entry,
    int documentCount,
    double averageLength,
  ) {
    if (entry.bodyLength == 0) return 0;

    var score = 0.0;
    for (final term in terms) {
      final frequency = entry.bodyTerms[term];
      if (frequency == null) continue;

      // Document frequency is approximated by the corpus size here because the
      // per-term posting count is not stored in a forward index; the constant
      // cancels out across candidates, and relative order is all that matters.
      final idf = Bm25.idf(
        documentCount: documentCount,
        documentsContainingTerm: 1,
      );
      score += Bm25.termScore(
        frequency: frequency,
        documentLength: entry.bodyLength,
        averageDocumentLength: averageLength,
        idf: idf,
      );
    }
    return score;
  }

  /// The query as a phrase: its words in order, separated by anything that is
  /// not a word character.
  ///
  /// Null for a single word, where "phrase" would mean nothing and every term
  /// match would be promoted a whole tier.
  ///
  /// Matched against the *original* text rather than a normalised copy, so the
  /// offsets it reports can be used for a highlight directly. That is why the
  /// separator is a pattern rather than a literal space: a phrase may be split
  /// by a line break, a comma or the run of spaces a scan leaves between
  /// columns, and all of those still read as the same phrase. Letters are
  /// excluded from the separator, so "amount, but due" does not match
  /// "amount due".
  static RegExp? phrasePatternFor(String query) {
    final words = SearchTokenizer.tokenize(query);
    if (words.length < 2) return null;

    return RegExp(
      words.map(RegExp.escape).join('[^A-Za-z0-9]+'),
      caseSensitive: false,
    );
  }

  /// Builds an index entry for [document].
  ///
  /// Every document is indexed, whether or not its text has been recognised.
  /// The first version only indexed documents with text, which meant a freshly
  /// scanned document could not be found by its own name until OCR finished.
  static IndexedDocument entryFor(Document document) {
    final bodyCounts = <String, int>{};
    for (final token in SearchTokenizer.tokenize(document.extractedText)) {
      bodyCounts[token] = (bodyCounts[token] ?? 0) + 1;
    }

    return IndexedDocument(
      id: document.id,
      title: document.title,
      titleTerms: SearchTokenizer.tokenize(document.title).toSet(),
      tagTerms: <String>{
        for (final tag in document.tags) ...SearchTokenizer.tokenize(tag),
      },
      bodyTerms: bodyCounts,
      bodyLength: bodyCounts.values.fold<int>(0, (sum, count) => sum + count),
    );
  }

  /// Identifies the library's contents, so a stale index can be spotted.
  ///
  /// Includes each document's `updatedAt`, so a rename or a page change
  /// invalidates the index even though the document count is unchanged.
  static String fingerprintOf(List<Document> documents) {
    final parts = documents
        .map((d) => '${d.id}:${d.updatedAt.microsecondsSinceEpoch}')
        .toList()
      ..sort();
    return '${parts.length}|${parts.join(',').hashCode}';
  }

  // ---- Snippets ------------------------------------------------------------

  List<SearchSnippet> _snippetsFor(
    Document document,
    List<String> terms,
    RegExp? phrase,
  ) {
    final snippets = <SearchSnippet>[];

    for (final page in document.pages) {
      if (snippets.length >= maxSnippetsPerHit) break;
      if (!page.hasText) continue;

      final snippet = _snippetFor(page.text, page.index, terms, phrase);
      if (snippet != null) snippets.add(snippet);
    }

    return List<SearchSnippet>.unmodifiable(snippets);
  }

  /// Builds one excerpt around the earliest matching term on a page.
  ///
  /// Every transformation below preserves length, and the ellipses are added
  /// last with the offset adjusted for them. That matters: `SearchSnippet`
  /// carries a highlight range into the text, and a `trim()` or a whitespace
  /// collapse would silently shift it — producing a highlight over the wrong
  /// characters, or a `RangeError` inside a `build`.
  static SearchSnippet? _snippetFor(
    String text,
    int pageIndex,
    List<String> terms,
    RegExp? phrase,
  ) {
    final haystack = text.toLowerCase();

    var matchAt = -1;
    var matchLength = 0;

    // The whole phrase, when the page carries it. Highlighting one word of a
    // phrase the user typed in full shows them less than they asked about, and
    // the pattern matches against the original string precisely so that the
    // offsets it returns still line up with it.
    final phraseMatch = phrase?.firstMatch(text);
    if (phraseMatch != null) {
      matchAt = phraseMatch.start;
      matchLength = phraseMatch.end - phraseMatch.start;
    } else {
      for (final term in terms) {
        final index = haystack.indexOf(term);
        if (index >= 0 && (matchAt < 0 || index < matchAt)) {
          matchAt = index;
          matchLength = term.length;
        }
      }
    }
    if (matchAt < 0) return null;

    final start = math.max(0, matchAt - snippetRadius);
    final end = math.min(text.length, matchAt + matchLength + snippetRadius);

    // Markers come off *before* the highlight is worked out, not after. The
    // stripper hands back where every character moved to, so the match is
    // re-located in the string that will actually be drawn. Stripping
    // afterwards would leave the highlight later in the line by exactly the
    // number of markers removed ahead of it — over the wrong words, and
    // silently, since a highlight has no way to look wrong on its own.
    final stripped = Markup.strip(text.substring(start, end));
    final (highlightStart, highlightEnd) = stripped.mapRange(
      matchAt - start,
      matchAt + matchLength - start,
    );

    // Newlines become spaces one-for-one, so the offsets just computed survive.
    final core = stripped.text
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ')
        .replaceAll('\t', ' ');

    final prefix = start > 0 ? '…' : '';
    final suffix = end < text.length ? '…' : '';

    return SearchSnippet(
      pageIndex: pageIndex,
      text: '$prefix$core$suffix',
      highlightStart: highlightStart + prefix.length,
      highlightLength: highlightEnd - highlightStart,
    );
  }

  Future<Result<void>> _guard(Future<void> Function() action) async {
    try {
      await action();
      return const Success<void>(null);
    } on CacheException catch (error, stackTrace) {
      return Failed(
        StorageFailure(error.message, cause: error, stackTrace: stackTrace),
      );
    } catch (error, stackTrace) {
      return Failed(
        StorageFailure(
          'The search index could not be updated.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}

class _Match {
  const _Match({
    required this.id,
    required this.kind,
    required this.score,
    this.matchedTags = const <String>[],
  });

  final String id;
  final SearchMatchKind kind;
  final double score;
  final List<String> matchedTags;
}
