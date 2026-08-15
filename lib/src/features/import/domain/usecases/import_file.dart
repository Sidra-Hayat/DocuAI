import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../documents/domain/entities/document.dart';
import '../../../documents/domain/entities/document_page.dart';
import '../../../documents/domain/repositories/document_repository.dart';
import '../../../search/domain/repositories/search_repository.dart';
import '../repositories/file_import_repository.dart';
import 'import_images.dart';

/// Builds a document out of a file already on the device.
///
/// The third way in, beside scanning and photographs, and deliberately the same
/// shape as both: pick, persist, index. What arrives is an ordinary [Document]
/// — nothing downstream knows or cares that it came from a PDF, which is what
/// lets an imported statement be searched, quoted by the assistant and exported
/// like anything else.
///
/// The two branches differ only in what they persist. A PDF or a picture
/// becomes pages, and recognition reads them exactly as it reads a scan — so
/// nothing is indexed here, because there is no text yet. A Word or text file
/// arrives *as* text, so it is written and indexed immediately: there is
/// nothing to recognise, and leaving it unindexed would make a document full of
/// words unfindable.
class ImportFileAsDocument {
  const ImportFileAsDocument({
    required FileImportRepository importer,
    required DocumentRepository documents,
    required SearchRepository search,
  }) : _importer = importer,
       _documents = documents,
       _search = search;

  final FileImportRepository _importer;
  final DocumentRepository _documents;
  final SearchRepository _search;

  FutureResult<ImportResult> call() async {
    final picked = await _importer.pickFile();

    final ImportedFile file;
    switch (picked) {
      case Failed(:final failure):
        return Failed(failure);
      case Success(:final value):
        file = value;
    }

    if (file.isEmpty) {
      return const Failed(ImportFailure('That file had nothing in it.'));
    }

    return switch (file.kind) {
      ImportedFileKind.pages => _createFromPages(file),
      ImportedFileKind.text => _createFromText(file),
    };
  }

  Future<Result<ImportResult>> _createFromPages(ImportedFile file) async {
    final created = await _documents.createFromImages(
      title: file.name,
      sourceImagePaths: file.imagePaths,
      source: DocumentSource.imported,
      pageKind: PageKind.imported,
    );

    return switch (created) {
      Failed(:final failure) => Failed(failure),
      Success(:final value) => Success(
        ImportResult(document: value, truncatedAt: file.truncatedAt),
      ),
    };
  }

  /// Writes the text onto the one page a new text document is created with.
  ///
  /// Composed from the existing operations rather than given a repository
  /// method of its own: creating a document to write in and putting text on its
  /// page are both things the app already does, and a third path into storage
  /// would be a third place for the page-index invariant to be got wrong.
  Future<Result<ImportResult>> _createFromText(ImportedFile file) async {
    final created = await _documents.createTextDocument(title: file.name);

    final Document document;
    switch (created) {
      case Failed(:final failure):
        return Failed(failure);
      case Success(:final value):
        document = value;
    }

    final page = document.pages.firstOrNull;
    if (page == null) {
      return const Failed(
        StorageFailure('The imported document could not be created.'),
      );
    }

    final written = await _documents.updatePageText(
      documentId: document.id,
      pageId: page.id,
      text: file.text,
    );

    switch (written) {
      case Failed(:final failure):
        return Failed(failure);
      case Success(:final value):
        // Best-effort, as everywhere else: the text is stored, so a failed
        // index costs discoverability until the next rebuild, not data.
        await _search.indexDocument(value);
        return Success(ImportResult(document: value));
    }
  }
}
