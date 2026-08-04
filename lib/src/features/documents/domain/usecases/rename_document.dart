import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/utils/clock.dart';
import '../entities/document.dart';
import '../repositories/document_repository.dart';

/// Renames a document, rejecting titles that are blank once trimmed.
///
/// The validation lives here rather than in the text field so that it holds for
/// every caller — the rename dialog today, a bulk action or an intent handler
/// later.
class RenameDocument {
  const RenameDocument(this._repository, {Clock clock = systemClock})
    : _now = clock;

  final DocumentRepository _repository;
  final Clock _now;

  /// Longest title the library list can render without truncating badly.
  static const int maxTitleLength = 120;

  FutureResult<Document> call({
    required String documentId,
    required String title,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      return const Failed(ValidationFailure('A document needs a title.'));
    }
    if (trimmed.length > maxTitleLength) {
      return const Failed(
        ValidationFailure('That title is too long — keep it under 120 characters.'),
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

    // Nothing changed — skip the write so `updatedAt` does not move and the
    // library does not reorder under the user.
    if (document.title == trimmed) return Success(document);

    return _repository.saveDocument(
      document.copyWith(title: trimmed, updatedAt: _now()),
    );
  }
}
