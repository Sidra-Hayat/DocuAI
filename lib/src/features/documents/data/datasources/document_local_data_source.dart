import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/storage/storage_paths.dart';
import '../../../../core/utils/clock.dart';
import '../../domain/entities/document.dart';
import '../../domain/entities/document_page.dart';
import '../models/document_model.dart';
import '../models/document_page_model.dart';

/// The only place Hive and the file system meet.
///
/// Throws [CacheException] / [NotFoundException]; the repository above catches
/// those and converts them to `Failure`s. Nothing here knows what a `Result`
/// is, which is what keeps the exception-to-failure translation in exactly one
/// layer.
class DocumentLocalDataSource {
  DocumentLocalDataSource({
    required Box<DocumentModel> box,
    required StoragePaths paths,
    Uuid uuid = const Uuid(),
    Clock clock = systemClock,
  }) : _box = box,
       _paths = paths,
       _uuid = uuid,
       _now = clock;

  final Box<DocumentModel> _box;
  final StoragePaths _paths;
  final Uuid _uuid;
  final Clock _now;

  /// Every document, newest first.
  ///
  /// Sorting happens here rather than in the UI so the library, search results
  /// and the assistant all agree on what "recent" means.
  List<DocumentModel> readAll() {
    try {
      return _box.values.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    } catch (error) {
      throw CacheException('Could not read the document library.', cause: error);
    }
  }

  DocumentModel read(String id) {
    final model = _box.get(id);
    if (model == null) throw NotFoundException(id);
    return model;
  }

  /// Fires whenever the box changes, so the repository can re-emit the list.
  ///
  /// Typed as `void` because the payload is genuinely irrelevant: the
  /// repository re-reads the whole library on every change, so which key moved
  /// tells it nothing it does not already look up.
  Stream<void> watch() => _box.watch();

  /// Copies freshly captured images into the app's own storage and writes the
  /// metadata record.
  ///
  /// [sourceImagePaths] are absolute paths to files the scanner owns. They are
  /// copied, never moved: the scanner's temp files are its to clean up, and a
  /// move that half-succeeds would destroy the only copy of a page.
  Future<DocumentModel> create({
    required String title,
    required List<String> sourceImagePaths,
  }) async {
    final id = _uuid.v4();
    final pages = <DocumentPageModel>[];

    try {
      final directory = await _paths.documentDir(id);

      for (var i = 0; i < sourceImagePaths.length; i++) {
        final target = p.join(directory.path, AppConstants.pageFileName(i));
        await File(sourceImagePaths[i]).copy(target);

        pages.add(
          DocumentPageModel(
            id: _uuid.v4(),
            imagePath: _paths.relativePath(target),
            index: i,
            text: '',
            ocrStatus: OcrStatus.pending.name,
            kind: PageKind.scanned.name,
          ),
        );
      }
    } catch (error) {
      // A half-built folder is worse than none: it consumes space with no Hive
      // record pointing at it, so nothing in the app would ever clean it up.
      await _paths.deleteDocumentDir(id);
      throw CacheException('Could not save the scanned pages.', cause: error);
    }

    final timestamp = _now();
    final model = DocumentModel(
      id: id,
      title: title,
      createdAt: timestamp,
      updatedAt: timestamp,
      pages: pages,
      tags: const <String>[],
      pdfPath: null,
      isFavorite: false,
      source: DocumentSource.scanned.name,
    );

    return write(model);
  }

  /// Writes a document that has no files.
  ///
  /// No folder is created. One is made on demand the first time something is
  /// written into it — a page image, or an exported PDF — so a note the user
  /// never exports leaves nothing on disk but its record.
  Future<DocumentModel> createTextDocument({required String title}) async {
    final timestamp = _now();
    final id = _uuid.v4();

    return write(
      DocumentModel(
        id: id,
        title: title,
        createdAt: timestamp,
        updatedAt: timestamp,
        pages: <DocumentPageModel>[_emptyTextPage(index: 0)],
        tags: const <String>[],
        pdfPath: null,
        isFavorite: false,
        source: DocumentSource.created.name,
      ),
    );
  }

  Future<DocumentModel> addTextPage(String documentId) async {
    final model = read(documentId);

    return write(
      _withPages(model, <DocumentPageModel>[
        ...model.pages,
        _emptyTextPage(index: model.pages.length),
      ]),
    );
  }

  Future<DocumentModel> updatePageText(
    String documentId,
    String pageId,
    String text,
  ) async {
    final model = read(documentId);

    final existing = model.pages.where((page) => page.id == pageId).firstOrNull;
    if (existing == null) throw NotFoundException(pageId);

    return write(
      _withPages(model, <DocumentPageModel>[
        for (final page in model.pages)
          if (page.id == pageId)
            DocumentPageModel(
              id: page.id,
              imagePath: page.imagePath,
              index: page.index,
              text: text,
              // Whoever wrote it, this is the page's text now. Leaving a
              // scanned page outstanding after its text was corrected would
              // put it back in `pagesAwaitingOcr`, where the next run would
              // overwrite the correction.
              ocrStatus: OcrStatus.completed.name,
              kind: page.kind,
            )
          else
            page,
      ]),
    );
  }

  DocumentPageModel _emptyTextPage({required int index}) => DocumentPageModel(
    id: _uuid.v4(),
    imagePath: null,
    index: index,
    text: '',
    // Nothing to recognise. A text page left pending would keep its whole
    // document pending, and the detail screen starts a recognition run on
    // every document that reports as much.
    ocrStatus: OcrStatus.completed.name,
    kind: PageKind.text.name,
  );

  Future<DocumentModel> write(DocumentModel model) async {
    try {
      await _box.put(model.id, model);
      return model;
    } catch (error) {
      throw CacheException('Could not save "${model.title}".', cause: error);
    }
  }

  /// Appends pages, copying each source image into the document's folder.
  Future<DocumentModel> addPages(
    String documentId,
    List<String> sourceImagePaths,
  ) async {
    final model = read(documentId);
    final directory = await _paths.documentDir(documentId);
    final added = <DocumentPageModel>[];

    try {
      for (final source in sourceImagePaths) {
        final pageId = _uuid.v4();
        final target = p.join(
          directory.path,
          AppConstants.pageFileNameFor(pageId),
        );
        await File(source).copy(target);

        added.add(
          DocumentPageModel(
            id: pageId,
            imagePath: _paths.relativePath(target),
            index: model.pages.length + added.length,
            text: '',
            ocrStatus: OcrStatus.pending.name,
            kind: PageKind.scanned.name,
          ),
        );
      }
    } catch (error) {
      // Roll back the copies this call made. Leaving them would consume space
      // that nothing in the app can find, let alone reclaim.
      for (final page in added) {
        await _deleteImage(page.imagePath);
      }
      throw CacheException('Could not add the pages.', cause: error);
    }

    return write(_withPages(model, <DocumentPageModel>[...model.pages, ...added]));
  }

  Future<DocumentModel> deletePage(String documentId, String pageId) async {
    final model = read(documentId);

    final page = model.pages.where((page) => page.id == pageId).firstOrNull;
    if (page == null) throw NotFoundException(pageId);

    if (model.pages.length <= 1) {
      throw const CacheException(
        'A document must keep at least one page. Delete the document instead.',
      );
    }

    // The record loses the page before the file does, for the same reason a
    // document delete does: a page pointing at a missing image renders as a
    // broken thumbnail, while an unreferenced file is invisible.
    final remaining = model.pages
        .where((candidate) => candidate.id != pageId)
        .toList();
    final saved = await write(_withPages(model, remaining));

    await _deleteImage(page.imagePath);
    return saved;
  }

  Future<DocumentModel> reorderPages(
    String documentId,
    List<String> orderedPageIds,
  ) async {
    final model = read(documentId);
    final byId = <String, DocumentPageModel>{
      for (final page in model.pages) page.id: page,
    };

    if (orderedPageIds.length != byId.length ||
        !orderedPageIds.toSet().containsAll(byId.keys)) {
      throw const CacheException(
        'The new page order does not match the pages in this document.',
      );
    }

    return write(
      _withPages(
        model,
        <DocumentPageModel>[for (final id in orderedPageIds) byId[id]!],
      ),
    );
  }

  Future<DocumentModel> replacePage(
    String documentId,
    String pageId,
    String sourceImagePath,
  ) async {
    final model = read(documentId);

    final existing = model.pages.where((page) => page.id == pageId).firstOrNull;
    if (existing == null) throw NotFoundException(pageId);

    // Written under a new name rather than over the old one: a copy that fails
    // partway would otherwise destroy the page it was meant to replace.
    final directory = await _paths.documentDir(documentId);
    final target = p.join(
      directory.path,
      AppConstants.pageFileNameFor(_uuid.v4()),
    );

    try {
      await File(sourceImagePath).copy(target);
    } catch (error) {
      throw CacheException('Could not replace the page.', cause: error);
    }

    final replaced = DocumentPageModel(
      id: existing.id,
      imagePath: _paths.relativePath(target),
      index: existing.index,
      // The old text described the old image, so it goes with it.
      text: '',
      ocrStatus: OcrStatus.pending.name,
      // The page keeps its provenance. Which kind a replacement *should* carry
      // is the caller's to say, and no caller can say it yet.
      kind: existing.kind,
    );

    final saved = await write(
      _withPages(model, <DocumentPageModel>[
        for (final page in model.pages)
          if (page.id == pageId) replaced else page,
      ]),
    );

    await _deleteImage(existing.imagePath);
    return saved;
  }

  /// Rebuilds a document around a new page list, renumbering as it goes.
  ///
  /// Index is assigned from list position rather than preserved, so every path
  /// through page editing produces a contiguous 0..n-1 sequence and no caller
  /// has to remember to renumber.
  DocumentModel _withPages(DocumentModel model, List<DocumentPageModel> pages) =>
      DocumentModel(
        id: model.id,
        title: model.title,
        createdAt: model.createdAt,
        updatedAt: _now(),
        pages: <DocumentPageModel>[
          for (var i = 0; i < pages.length; i++)
            DocumentPageModel(
              id: pages[i].id,
              imagePath: pages[i].imagePath,
              index: i,
              text: pages[i].text,
              ocrStatus: pages[i].ocrStatus,
              // Carried explicitly. This rebuild runs on every add, delete and
              // reorder, so dropping the field here would quietly turn every
              // page in an edited document back into a scan.
              kind: pages[i].kind,
            ),
        ],
        tags: model.tags,
        // Any page change makes the exported PDF stale, so the reference goes
        // and the next share composes a fresh one.
        pdfPath: null,
        isFavorite: model.isFavorite,
        // Carried for the same reason the page kind is: this rebuild runs on
        // every page edit, and a document that lost its origin here would
        // report as scanned the first time anything was added to it.
        source: model.source,
      );

  /// Removes a page's image if it has one.
  ///
  /// Accepts null so callers do not have to ask first: a page with no image and
  /// a page whose image is already gone want the same thing done about it.
  Future<void> _deleteImage(String? relativePath) async {
    if (relativePath == null) return;

    try {
      final file = File(_paths.absolutePath(relativePath));
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // The record is already correct; an image left behind is reclaimable
      // and must not fail an edit the user has seen succeed.
    }
  }

  /// Removes the record first, then the files.
  ///
  /// That order matters: a record pointing at deleted files renders a broken
  /// thumbnail the user cannot get rid of, whereas files with no record are
  /// invisible and reclaimable later.
  Future<void> delete(String id) async {
    try {
      await _box.delete(id);
      await _paths.deleteDocumentDir(id);
    } catch (error) {
      throw CacheException('Could not delete the document.', cause: error);
    }
  }
}
