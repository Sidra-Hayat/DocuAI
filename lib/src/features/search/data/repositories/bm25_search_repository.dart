import 'dart:math' as math;

import '../../../../core/error/exceptions.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../documents/domain/entities/document.dart';
import '../../../documents/domain/repositories/document_repository.dart';
import '../../domain/entities/search_hit.dart';
import '../../domain/repositories/search_repository.dart';
import '../datasources/search_index_local_data_source.dart';
import '../datasources/search_tokenizer.dart';

/// Full-text search over recognised page text, ranked with BM25.
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

  /// Passages shown per hit. Three is enough to judge relevance without the
  /// result turning into the document itself.
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

      final scores = _score(terms, entries);
      if (scores.isEmpty) return const Success(<SearchHit>[]);

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

      final ranked = scores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      final hits = <SearchHit>[];
      for (final entry in ranked) {
        // The index can outlive the document it describes if a delete failed
        // to de-index. Skipping is right: a hit that opens nothing is worse
        // than a missing hit, and `rebuildIndex` repairs the entry later.
        final document = byId[entry.key];
        if (document == null) continue;

        hits.add(
          SearchHit(
            document: document,
            score: entry.value,
            snippets: _snippetsFor(document, terms),
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
      _guard(() => _index.write(_entryFor(document)));

  @override
  FutureResult<void> removeFromIndex(String documentId) =>
      _guard(() => _index.remove(documentId));

  @override
  FutureResult<void> rebuildIndex(List<Document> documents) =>
      _guard(() => _index.replaceAll(documents.map(_entryFor)));

  // ---- Scoring -------------------------------------------------------------

  Map<String, double> _score(
    List<String> terms,
    List<IndexedDocument> entries,
  ) {
    final documentCount = entries.length;
    final totalLength = entries.fold<int>(
      0,
      (sum, entry) => sum + entry.length,
    );
    final averageLength = totalLength / documentCount;

    final scores = <String, double>{};

    for (final term in terms) {
      final matching = entries
          .where((entry) => entry.terms.containsKey(term))
          .toList();
      if (matching.isEmpty) continue;

      final idf = Bm25.idf(
        documentCount: documentCount,
        documentsContainingTerm: matching.length,
      );

      for (final entry in matching) {
        scores[entry.id] = (scores[entry.id] ?? 0) +
            Bm25.termScore(
              frequency: entry.terms[term]!,
              documentLength: entry.length,
              averageDocumentLength: averageLength,
              idf: idf,
            );
      }
    }

    return scores;
  }

  static IndexedDocument _entryFor(Document document) {
    final terms = SearchTokenizer.countTerms(
      title: document.title,
      body: document.extractedText,
    );

    return IndexedDocument(
      id: document.id,
      length: terms.values.fold<int>(0, (sum, count) => sum + count),
      terms: terms,
    );
  }

  // ---- Snippets ------------------------------------------------------------

  List<SearchSnippet> _snippetsFor(Document document, List<String> terms) {
    final snippets = <SearchSnippet>[];

    for (final page in document.pages) {
      if (snippets.length >= maxSnippetsPerHit) break;
      if (!page.hasText) continue;

      final snippet = _snippetFor(page.text, page.index, terms);
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
  ) {
    final haystack = text.toLowerCase();

    var matchAt = -1;
    var matchLength = 0;
    for (final term in terms) {
      final index = haystack.indexOf(term);
      if (index >= 0 && (matchAt < 0 || index < matchAt)) {
        matchAt = index;
        matchLength = term.length;
      }
    }
    if (matchAt < 0) return null;

    final start = math.max(0, matchAt - snippetRadius);
    final end = math.min(text.length, matchAt + matchLength + snippetRadius);

    // Newlines become spaces one-for-one, so offsets survive.
    final core = text
        .substring(start, end)
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ')
        .replaceAll('\t', ' ');

    final prefix = start > 0 ? '…' : '';
    final suffix = end < text.length ? '…' : '';

    return SearchSnippet(
      pageIndex: pageIndex,
      text: '$prefix$core$suffix',
      highlightStart: (matchAt - start) + prefix.length,
      highlightLength: matchLength,
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
