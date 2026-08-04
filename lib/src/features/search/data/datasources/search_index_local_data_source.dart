import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive.dart';

import '../../../../core/constants/hive_boxes.dart';
import '../../../../core/error/exceptions.dart';

/// One document's contribution to the index.
class IndexedDocument {
  const IndexedDocument({
    required this.id,
    required this.length,
    required this.terms,
  });

  factory IndexedDocument.fromStored(String id, Map<dynamic, dynamic> stored) =>
      IndexedDocument(
        id: id,
        length: stored['length'] as int? ?? 0,
        terms: <String, int>{
          for (final entry in (stored['terms'] as Map? ?? const {}).entries)
            entry.key as String: entry.value as int,
        },
      );

  final String id;

  /// Total token count, including the weighted title. BM25 divides by this to
  /// stop long documents outranking short ones purely on volume.
  final int length;

  /// Term to frequency.
  final Map<String, int> terms;

  Map<String, dynamic> toStored() => <String, dynamic>{
    'length': length,
    'terms': terms,
  };
}

/// Persists the index in Hive.
///
/// The stored shape is a **forward** index — one entry per document holding its
/// term frequencies — rather than the inverted token-to-postings map a search
/// engine would use.
///
/// That is a deliberate trade for this corpus. An inverted index wins when the
/// vocabulary cannot be walked per query; here a personal library is tens to
/// low hundreds of documents, so scoring every entry is a few thousand hash
/// lookups. In exchange, updating one document is a single write and deleting
/// one is a single delete, where an inverted index would have to touch every
/// token the document contributed. `SearchRepository` hides the choice, so
/// swapping in postings later changes nothing above this layer.
///
/// Values are plain maps and lists rather than `@HiveType` models. The index is
/// derived data: if the format ever changes there is nothing to migrate,
/// because it can be rebuilt from the documents in a second. That is what
/// [schemaVersion] is for.
class SearchIndexLocalDataSource {
  const SearchIndexLocalDataSource(this._box);

  final Box<dynamic> _box;

  static const int schemaVersion = 1;

  /// A document id is a UUID, so this cannot collide with one.
  static const String metaKey = '__meta__';

  bool get isCurrentVersion {
    final meta = _box.get(metaKey);
    return meta is Map && meta['version'] == schemaVersion;
  }

  int get documentCount => _box.keys.where((key) => key != metaKey).length;

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

  Future<void> write(IndexedDocument entry) async {
    try {
      await _box.put(entry.id, entry.toStored());
      await _stampVersion();
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
  Future<void> replaceAll(Iterable<IndexedDocument> entries) async {
    try {
      await _box.clear();
      await _box.putAll(<String, dynamic>{
        for (final entry in entries) entry.id: entry.toStored(),
      });
      await _stampVersion();
    } catch (error) {
      throw CacheException(
        'The search index could not be rebuilt.',
        cause: error,
      );
    }
  }

  Future<void> _stampVersion() => _box.put(metaKey, <String, dynamic>{
    'version': schemaVersion,
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
