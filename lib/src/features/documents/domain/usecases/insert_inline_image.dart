import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../import/domain/repositories/image_import_repository.dart';
import '../repositories/document_repository.dart';

/// Puts a picture from the device into a document being written.
///
/// Two steps that must not be separable. The picker leaves a normalised JPEG in
/// the cache, and the cache is cleared the next time anything is imported — so
/// a picture that was chosen but not copied is a picture that will be gone by
/// the time the document is reopened. Copying immediately, in the same
/// operation, is what makes "insert an image" mean it.
///
/// What comes back is the file's *name*, which the caller writes into the page
/// text as a reference. The picture only becomes part of the document when that
/// text is saved — and if the user backs out before then, the sweep on the next
/// save removes it.
class InsertInlineImage {
  const InsertInlineImage({
    required ImageImportRepository importer,
    required DocumentRepository documents,
  }) : _importer = importer,
       _documents = documents;

  final ImageImportRepository _importer;
  final DocumentRepository _documents;

  /// Returns the stored file's name, or a failure the caller can show.
  ///
  /// A dismissed picker comes back as a cancelled [ImportFailure] rather than a
  /// success with nothing in it: the caller has to tell the two apart, because
  /// one of them deserves a message and the other deserves silence.
  FutureResult<String> call({required String documentId}) async {
    // One at a time. The reference goes at the caret, and a caret is one place.
    final picked = await _importer.pickImages(limit: 1);

    final ImportOutcome outcome;
    switch (picked) {
      case Failed(:final failure):
        return Failed(failure);
      case Success(:final value):
        outcome = value;
    }

    if (outcome.isEmpty) {
      return Failed(
        ImportFailure(
          outcome.hasRejections
              ? 'That picture could not be read. It may be in a format this '
                    'device saved but cannot share — try converting it to JPEG.'
              : 'No picture was chosen.',
          // Only a dismissal is silent. A picture that was chosen and then
          // dropped is something the user needs telling about.
          cancelled: !outcome.hasRejections,
        ),
      );
    }

    return _documents.addInlineImage(
      documentId: documentId,
      sourcePath: outcome.imagePaths.first,
    );
  }
}
