import 'dart:io';

import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/error/exceptions.dart';
import '../../../../core/storage/storage_paths.dart';
import '../../../../core/utils/clock.dart';
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
  Stream<BoxEvent> watch() => _box.watch();

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
    );

    return write(model);
  }

  Future<DocumentModel> write(DocumentModel model) async {
    try {
      await _box.put(model.id, model);
      return model;
    } catch (error) {
      throw CacheException('Could not save "${model.title}".', cause: error);
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
