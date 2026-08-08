import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../documents/domain/entities/document.dart';
import '../../../documents/domain/entities/document_page.dart';
import '../../../documents/domain/repositories/document_repository.dart';
import '../../../search/domain/repositories/search_repository.dart';
import '../repositories/image_import_repository.dart';

/// What an import produced, once the pages exist.
class ImportResult {
  const ImportResult({required this.document, this.rejected = const []});

  final Document document;

  /// Files the picker offered that could not be decoded. Non-empty here is a
  /// *partial* success: the document was created from everything else.
  final List<String> rejected;
}

/// Builds a document out of photos already on the device.
///
/// The mirror of `ScanNewDocument`, and deliberately the same shape: pick,
/// persist, index. The pages it produces are byte-identical JPEGs to scanned
/// ones and take the same path through storage — they differ only in carrying
/// [PageKind.imported], which is provenance and changes no behaviour.
class ImportImagesAsDocument {
  const ImportImagesAsDocument({
    required ImageImportRepository importer,
    required DocumentRepository documents,
  }) : _importer = importer,
       _documents = documents;

  final ImageImportRepository _importer;
  final DocumentRepository _documents;

  /// Nothing is indexed here. A freshly imported page has no recognised text
  /// yet, so there is nothing to index — `RecognizeDocumentText` does it once
  /// there is, exactly as it does after a scan.
  FutureResult<ImportResult> call({required String title}) async {
    final picked = await _importer.pickImages();

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
              ? 'None of those photos could be read. They may be in a format '
                    'this device saved but cannot share — try converting them '
                    'to JPEG.'
              : 'No photos were chosen.',
          // Only silent when nothing was chosen. Photos that were chosen and
          // then dropped is something the user needs telling about.
          cancelled: !outcome.hasRejections,
        ),
      );
    }

    final created = await _documents.createFromImages(
      title: title,
      sourceImagePaths: outcome.imagePaths,
      source: DocumentSource.imported,
      pageKind: PageKind.imported,
    );

    return switch (created) {
      Failed(:final failure) => Failed(failure),
      Success(:final value) => Success(
        ImportResult(document: value, rejected: outcome.rejected),
      ),
    };
  }
}

/// Appends photos to a document that already exists.
class ImportImagesIntoDocument {
  const ImportImagesIntoDocument({
    required ImageImportRepository importer,
    required DocumentRepository documents,
    required SearchRepository search,
  }) : _importer = importer,
       _documents = documents,
       _search = search;

  final ImageImportRepository _importer;
  final DocumentRepository _documents;
  final SearchRepository _search;

  FutureResult<ImportResult> call(String documentId) async {
    final picked = await _importer.pickImages();

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
              ? 'None of those photos could be read.'
              : 'No photos were chosen.',
          cancelled: !outcome.hasRejections,
        ),
      );
    }

    final saved = await _documents.addPages(
      documentId: documentId,
      sourceImagePaths: outcome.imagePaths,
      pageKind: PageKind.imported,
    );

    if (saved case Success(:final value)) {
      // Best-effort, as everywhere else: the pages are stored, so a failed
      // index costs discoverability until the next rebuild, not data.
      await _search.indexDocument(value);
    }

    return switch (saved) {
      Failed(:final failure) => Failed(failure),
      Success(:final value) => Success(
        ImportResult(document: value, rejected: outcome.rejected),
      ),
    };
  }
}
