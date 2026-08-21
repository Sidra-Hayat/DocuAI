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

  FutureResult<ImportResult> call() => _persist(_importer.pickFile());

  /// The same import, for a file the app already has in hand.
  ///
  /// Used by the archive browser: a PDF pulled out of a ZIP has been through
  /// no picker, but everything that happens to it afterwards — rasterising,
  /// bounding, persisting, indexing — is identical, and this is the one place
  /// that knows what "afterwards" is.
  ///
  /// [title] overrides the name the file carries. The archive browser passes
  /// one because an entry called `scan_0001` inside `Invoices 2026.zip` reads
  /// better in the library as the entry's own name than as a document nobody
  /// can place.
  FutureResult<ImportResult> fromPath(
    String path, {
    String? title,
    bool Function()? isCancelled,
  }) => _persist(
    _importer.readFile(path, isCancelled: isCancelled),
    title: title,
  );

  Future<Result<ImportResult>> _persist(
    FutureResult<ImportedFile> reading, {
    String? title,
  }) async {
    final read = await reading;

    final ImportedFile file;
    switch (read) {
      case Failed(:final failure):
        return Failed(failure);
      case Success(:final value):
        file = value;
    }

    if (file.isEmpty) {
      return const Failed(ImportFailure('That file had nothing in it.'));
    }

    final named = title == null || title.trim().isEmpty ? file.name : title;

    return switch (file.kind) {
      ImportedFileKind.pages => _createFromPages(file, named),
      ImportedFileKind.text => _createFromText(file, named),
    };
  }

  Future<Result<ImportResult>> _createFromPages(
    ImportedFile file,
    String title,
  ) async {
    final created = await _documents.createFromImages(
      title: title,
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
  Future<Result<ImportResult>> _createFromText(
    ImportedFile file,
    String title,
  ) async {
    final created = await _documents.createTextDocument(title: title);

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
