import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../../../core/constants/hive_boxes.dart';
import '../../../../core/error/exceptions.dart';

/// One document's contribution to the index.
///
/// Title, tags and body are kept apart rather than merged into one bag of
/// terms. Merging them — which is what the first version did, with the title
/// counted three times — makes a title match indistinguishable from a body
/// match once scoring starts, and the whole point of the ranking is that
/// someone typing a document's name wants *that document*, not a page that
/// mentions the same words.
class IndexedDocument {
  const IndexedDocument({
    required this.id,
    required this.title,
    required this.titleTerms,
    required this.tagTerms,
    required this.bodyTerms,
    required this.bodyLength,
  });

  factory IndexedDocument.fromStored(String id, Map<dynamic, dynamic> stored) =>
      IndexedDocument(
        id: id,
        title: stored['title'] as String? ?? '',
        titleTerms: _terms(stored['titleTerms']),
        tagTerms: _terms(stored['tagTerms']),
        bodyTerms: _counts(stored['bodyTerms']),
        bodyLength: stored['bodyLength'] as int? ?? 0,
      );

  final String id;

  /// Stored verbatim so an exact-title match can be decided without
  /// reconstructing the title from its tokens.
  final String title;

  final Set<String> titleTerms;
  final Set<String> tagTerms;

  /// Term to frequency, for BM25.
  final Map<String, int> bodyTerms;

  /// Token count of the body alone. BM25 divides by this, and including title
  /// or tag tokens would penalise a long title as though it were content.
  final int bodyLength;

  Map<String, dynamic> toStored() => <String, dynamic>{
    'title': title,
    'titleTerms': titleTerms.toList(),
    'tagTerms': tagTerms.toList(),
    'bodyTerms': bodyTerms,
    'bodyLength': bodyLength,
  };

  static Set<String> _terms(Object? raw) => <String>{
    if (raw is List) ...raw.map((term) => term as String),
  };

  static Map<String, int> _counts(Object? raw) => <String, int>{
    if (raw is Map)
      for (final entry in raw.entries) entry.key as String: entry.value as int,
  };
}

/// Persists the index in Hive.
///
/// A **forward** index — one entry per document — rather than the inverted
/// token-to-postings map a search engine would use. An inverted index wins
/// when the vocabulary cannot be walked per query; here a personal library is
/// tens to low hundreds of documents, so scoring every entry is a few thousand
/// hash lookups. In exchange, updating one document is a single write and
/// deleting one is a single delete. `SearchRepository` hides the choice.
///
/// Values are plain maps rather than `@HiveType` models. The index is derived
/// data: if the format changes there is nothing to migrate, because it can be
/// rebuilt from the documents in a second. That is what [schemaVersion] is for.
class SearchIndexLocalDataSource {
  const SearchIndexLocalDataSource(this._box);

  final Box<dynamic> _box;

  /// 2 — title, tags and body split apart. A stored index at version 1 is
  /// discarded and rebuilt rather than read.
  static const int schemaVersion = 2;

  /// A document id is a UUID, so this cannot collide with one.
  static const String metaKey = '__meta__';

  bool get isCurrentVersion {
    final meta = _box.get(metaKey);
    return meta is Map && meta['version'] == schemaVersion;
  }

  int get documentCount => _box.keys.where((key) => key != metaKey).length;

  /// What the index believes the library looked like when it was built.
  ///
  /// Counting entries is not enough: delete one document and add another and
  /// the count is unchanged while the contents are not, leaving a stale index
  /// that never repairs itself. A fingerprint over ids and revisions notices.
  String? get storedFingerprint {
    final meta = _box.get(metaKey);
    return meta is Map ? meta['fingerprint'] as String? : null;
  }

  List<IndexedDocument> readAll() {
    try {
      final entries = <IndexedDocument>[];
      for (final key in _box.keys) {
        if (key == metaKey) continue;
        final stored = _box.get(key);
        if (stored is Map) {
          entries.add(IndexedDocument.fromStored(key as String, stored));
        }
      }
      return entries;
    } catch (error) {
      throw CacheException('The search index could not be read.', cause: error);
    }
  }

  Future<void> write(IndexedDocument entry, {String? fingerprint}) async {
    try {
      await _box.put(entry.id, entry.toStored());
      await _stamp(fingerprint);
    } catch (error) {
      throw CacheException(
        'The search index could not be updated.',
        cause: error,
      );
    }
  }

  Future<void> remove(String documentId) async {
    try {
      await _box.delete(documentId);
    } catch (error) {
      throw CacheException(
        'The search index could not be updated.',
        cause: error,
      );
    }
  }

  /// Replaces the whole index in one pass.
  Future<void> replaceAll(
    Iterable<IndexedDocument> entries, {
    String? fingerprint,
  }) async {
    try {
      await _box.clear();
      await _box.putAll(<String, dynamic>{
        for (final entry in entries) entry.id: entry.toStored(),
      });
      await _stamp(fingerprint);
    } catch (error) {
      throw CacheException(
        'The search index could not be rebuilt.',
        cause: error,
      );
    }
  }

  Future<void> _stamp(String? fingerprint) => _box.put(metaKey, <String, dynamic>{
    'version': schemaVersion,
    'fingerprint': ?fingerprint,
  });
}

/// Opens the index box. Called by `bootstrap()` alongside the other boxes.
Future<Box<dynamic>> openSearchIndexBox() =>
    Hive.openBox<dynamic>(HiveBoxes.searchIndex);

final searchIndexBoxProvider = Provider<Box<dynamic>>(
  (ref) => throw UnimplementedError(
    'searchIndexBoxProvider was not overridden. '
    'It must be provided by bootstrap() via ProviderScope.overrides.',
  ),
);
