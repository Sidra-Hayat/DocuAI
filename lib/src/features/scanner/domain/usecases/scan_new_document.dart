import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../documents/domain/entities/document.dart';
import '../../../documents/domain/repositories/document_repository.dart';
import '../repositories/scanner_repository.dart';

/// Scans pages and turns them into a saved document.
///
/// This is the app's primary action, and the one place the scanner and library
/// features meet. Composing them here — rather than having the scanner know how
/// to persist, or the library know how to scan — is what keeps both
/// repositories independently replaceable.
///
/// OCR is *not* triggered from here. Recognition is slow enough to be worth
/// showing progress for, so the caller saves first, navigates to the document,
/// then runs `RecognizeDocumentText` against the visible page list.
class ScanNewDocument {
  const ScanNewDocument({
    required ScannerRepository scanner,
    required DocumentRepository documents,
  }) : _scanner = scanner,
       _documents = documents;

  final ScannerRepository _scanner;
  final DocumentRepository _documents;

  /// ML Kit's own cap. Stated here so the limit is visible to callers that want
  /// to warn the user before they hit it.
  static const int defaultPageLimit = 20;

  static const String defaultTitle = 'Untitled scan';

  AsyncResult<Document> call({
    String? title,
    int pageLimit = defaultPageLimit,
  }) async {
    final scanned = await _scanner.scanPages(pageLimit: pageLimit);
    final List<String> imagePaths;
    switch (scanned) {
      case Failed(:final failure):
        return Failed(failure);
      case Success(:final value):
        imagePaths = value;
    }

    // The user opened the scanner and backed out. Nothing to save, and nothing
    // went wrong — but there is no document to return either, so this is the
    // one cancellation the caller has to handle.
    if (imagePaths.isEmpty) {
      return const Failed(ScanFailure('No pages were captured.'));
    }

    final trimmed = title?.trim();
    return _documents.createFromImages(
      title: trimmed == null || trimmed.isEmpty ? defaultTitle : trimmed,
      sourceImagePaths: imagePaths,
    );
  }
}
