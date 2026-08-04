import '../../../../core/error/result.dart';
import '../entities/document.dart';

/// The library's persistence contract.
///
/// Implemented in Phase 2 over Hive plus the file system. Two rules the
/// implementation owns, so that no caller has to think about them:
///
///  * **Paths are relative on the way in and out.** Callers pass and receive
///    paths relative to the app documents directory; resolving them is the
///    data layer's job.
///  * **Nothing throws.** Hive errors, missing files and permission problems
///    are caught and returned as a [Failure].
abstract interface class DocumentRepository {
  /// The library, newest first, re-emitted on every change.
  ///
  /// A stream rather than a one-shot read because several screens show the same
  /// list and a scan started on one of them must be visible on the others
  /// without a manual refresh.
  ///
  /// This is the one member that does not return a `Result`. A stream carries
  /// its own error channel, and Riverpod surfaces that as `AsyncValue.error`
  /// with no work from the caller — wrapping each event in a `Result` as well
  /// would mean two error paths for one failure.
  Stream<List<Document>> watchDocuments();

  /// One-shot read of the whole library, newest first. Used by the search
  /// indexer and the assistant, which need a snapshot rather than a
  /// subscription.
  FutureResult<List<Document>> getDocuments();

  /// Returns the document with [id], or a [StorageFailure] if no such record
  /// exists.
  FutureResult<Document> getDocument(String id);

  /// Persists a document created from freshly captured images.
  ///
  /// [sourceImagePaths] are **absolute** paths to the temporary files ML Kit
  /// wrote — the one place absolute paths cross this boundary, because the
  /// files do not belong to the app yet. The implementation copies each into
  /// the document's own folder, stores the relative paths, and deletes nothing
  /// on failure so a retry is possible.
  FutureResult<Document> createFromImages({
    required String title,
    required List<String> sourceImagePaths,
  });

  /// Writes an already-existing document back, replacing it wholesale.
  /// Callers are expected to have updated `updatedAt` themselves.
  FutureResult<Document> saveDocument(Document document);

  /// Deletes the record, its page images, and its generated PDF.
  ///
  /// Succeeds when the id is unknown: deleting something that is already gone
  /// is the outcome the caller wanted.
  FutureResult<void> deleteDocument(String id);
}
