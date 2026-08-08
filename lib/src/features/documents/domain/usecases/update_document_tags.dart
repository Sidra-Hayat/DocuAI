import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/utils/clock.dart';
import '../../../search/domain/repositories/search_repository.dart';
import '../entities/document.dart';
import '../repositories/document_repository.dart';

/// Replaces a document's tags, normalising them first.
///
/// Normalisation is the whole point of this use case: `"  Receipts "`,
/// `"receipts"` and `"RECEIPTS"` must collapse to one tag, or the filter chips
/// fill up with near-duplicates that each match a different subset of the
/// library.
class UpdateDocumentTags {
  const UpdateDocumentTags(
    this._repository, {
    required SearchRepository search,
    Clock clock = systemClock,
  }) : _search = search,
       _now = clock;

  final DocumentRepository _repository;
  final SearchRepository _search;
  final Clock _now;

  static const int maxTagsPerDocument = 12;
  static const int maxTagLength = 32;

  FutureResult<Document> call({
    required String documentId,
    required List<String> tags,
  }) async {
    final normalised = normalise(tags);
    if (normalised.length > maxTagsPerDocument) {
      return const Failed(
        ValidationFailure('A document can have at most 12 tags.'),
      );
    }

    final loaded = await _repository.getDocument(documentId);
    final Document document;
    switch (loaded) {
      case Failed(:final failure):
        return Failed(failure);
      case Success(:final value):
        document = value;
    }

    final saved = await _repository.saveDocument(
      document.copyWith(tags: normalised, updatedAt: _now()),
    );

    if (saved case Success(:final value)) {
      // Indexed here, as `EditPageText` and `DeleteDocument` already do.
      // Without it a tag is only findable once the Search tab happens to
      // trigger a full rebuild — the index fingerprint would notice the
      // changed `updatedAt` eventually, which is not the same as a tag
      // working the moment it is added.
      //
      // Best-effort: the tag is already stored, so a failure here costs
      // discoverability until the next rebuild, not data.
      await _search.indexDocument(value);
    }

    return saved;
  }

  /// Trims, lower-cases, drops blanks and over-long entries, and removes
  /// duplicates while keeping the order the user typed them in.
  ///
  /// Exposed as a static so the tag input field can preview exactly what will
  /// be stored, rather than reimplementing the rules and drifting from them.
  static List<String> normalise(List<String> raw) {
    final seen = <String>{};
    final result = <String>[];
    for (final tag in raw) {
      final clean = tag.trim().toLowerCase();
      if (clean.isEmpty || clean.length > maxTagLength) continue;
      if (seen.add(clean)) result.add(clean);
    }
    return List.unmodifiable(result);
  }
}
