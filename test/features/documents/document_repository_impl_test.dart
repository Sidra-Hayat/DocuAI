import 'dart:io';

import 'package:docuai/hive_registrar.g.dart';
import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/features/documents/data/datasources/document_local_data_source.dart';
import 'package:docuai/src/features/documents/data/models/document_model.dart';
import 'package:docuai/src/features/documents/data/repositories/document_repository_impl.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/documents/domain/repositories/document_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

/// Data-layer tests run against **real Hive** in a temp directory, not a fake.
///
/// The whole point of this layer is the interaction between Hive and the file
/// system — adapter round-trips, relative paths, the delete cascade. A mock box
/// would assert that the code calls the methods it calls, which proves nothing
/// about whether a document survives being written and read back.
///
/// `Hive.init` is used rather than `initFlutter`: the latter needs
/// `path_provider` and a platform channel, neither of which exists in a plain
/// `test()`.
void main() {
  late Directory tempDir;
  late Box<DocumentModel> box;
  late DocumentRepository repository;
  late StoragePaths paths;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_repo_test');
    Hive.init(p.join(tempDir.path, 'hive'));
    Hive.registerAdapters();
  });

  setUp(() async {
    box = await Hive.openBox<DocumentModel>(
      'documents_${DateTime.now().microsecondsSinceEpoch}',
    );
    paths = StoragePaths(tempDir);
    repository = DocumentRepositoryImpl(
      DocumentLocalDataSource(box: box, paths: paths),
    );
  });

  tearDown(() async => box.deleteFromDisk());

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// Writes throwaway files standing in for what the scanner would hand over.
  Future<List<String>> writeSourceImages(int count) async {
    final source = await Directory(
      p.join(tempDir.path, 'incoming'),
    ).create(recursive: true);

    return <String>[
      for (var i = 0; i < count; i++)
        (await File(
          p.join(source.path, 'capture_${DateTime.now().microsecondsSinceEpoch}_$i.jpg'),
        ).writeAsBytes(<int>[0xFF, 0xD8, i, 0xFF, 0xD9])).path,
    ];
  }

  Future<Document> create({String title = 'Water bill', int pages = 2}) async {
    final result = await repository.createFromImages(
      title: title,
      sourceImagePaths: await writeSourceImages(pages),
    );
    return (result as Success<Document>).value;
  }

  group('createFromImages', () {
    test('copies each page into the document folder', () async {
      final document = await create(pages: 3);

      expect(document.pageCount, 3);
      for (final page in document.pages) {
        expect(
          File(paths.absolutePath(page.imagePath)).existsSync(),
          isTrue,
          reason: '${page.imagePath} should have been copied in',
        );
      }
    });

    test('stores relative paths, never absolute ones', () async {
      final document = await create();

      for (final page in document.pages) {
        expect(p.isRelative(page.imagePath), isTrue);
        expect(page.imagePath, isNot(contains(tempDir.path)));
      }
    });

    test('leaves the source files where it found them', () async {
      final sources = await writeSourceImages(2);

      await repository.createFromImages(
        title: 'Passport',
        sourceImagePaths: sources,
      );

      for (final source in sources) {
        expect(File(source).existsSync(), isTrue);
      }
    });

    test('numbers pages in order, starting at zero', () async {
      final document = await create(pages: 3);

      expect(
        document.pages.map((page) => page.index),
        <int>[0, 1, 2],
      );
      expect(
        document.pages.map((page) => p.basename(page.imagePath)),
        <String>['page_000.jpg', 'page_001.jpg', 'page_002.jpg'],
      );
    });

    test('every page starts awaiting OCR', () async {
      final document = await create();

      expect(document.ocrStatus, OcrStatus.pending);
      expect(document.pagesAwaitingOcr, hasLength(2));
    });

    test('cleans up the folder when a source image is missing', () async {
      // Documents written by earlier tests in this file share the same root,
      // so the assertion is that this create added nothing — not that the root
      // is empty.
      final root = Directory(p.join(tempDir.path, 'documents'));
      Set<String> folders() => root.existsSync()
          ? root.listSync().map((entity) => entity.path).toSet()
          : <String>{};

      final before = folders();

      final result = await repository.createFromImages(
        title: 'Broken',
        sourceImagePaths: <String>[p.join(tempDir.path, 'does_not_exist.jpg')],
      );

      expect(result.failureOrNull, isA<StorageFailure>());
      expect(box.values, isEmpty, reason: 'no half-written record');
      expect(
        folders(),
        before,
        reason: 'no orphan folder should survive a failed create',
      );
    });
  });

  group('round-trip through Hive', () {
    test('survives being written and read back', () async {
      final created = await create(title: 'Rental agreement');

      final reloaded = await repository.getDocument(created.id);

      expect(reloaded.valueOrNull, created);
    });

    test('preserves tags, favourite and OCR text', () async {
      final created = await create();

      await repository.saveDocument(
        created.copyWith(
          tags: const <String>['bills', 'utilities'],
          isFavorite: true,
          pages: <DocumentPage>[
            created.pages.first.copyWith(
              text: 'Total due 42.00',
              ocrStatus: OcrStatus.completed,
            ),
            created.pages.last,
          ],
        ),
      );

      final reloaded = (await repository.getDocument(created.id)).valueOrNull!;

      expect(reloaded.tags, <String>['bills', 'utilities']);
      expect(reloaded.isFavorite, isTrue);
      expect(reloaded.pages.first.text, 'Total due 42.00');
      expect(reloaded.pages.first.ocrStatus, OcrStatus.completed);
      expect(reloaded.ocrStatus, OcrStatus.pending, reason: 'page 2 pending');
    });

    test('returns pages in index order even if stored shuffled', () async {
      final created = await create(pages: 3);

      await repository.saveDocument(
        created.copyWith(pages: created.pages.reversed.toList()),
      );

      final reloaded = (await repository.getDocument(created.id)).valueOrNull!;

      expect(reloaded.pages.map((page) => page.index), <int>[0, 1, 2]);
    });

    test('a missing id is a StorageFailure, not a crash', () async {
      final result = await repository.getDocument('nope');

      expect(result.failureOrNull, isA<StorageFailure>());
    });
  });

  group('getDocuments', () {
    test('returns the library newest first', () async {
      final first = await create(title: 'Oldest');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final second = await create(title: 'Newest');

      final documents = (await repository.getDocuments()).valueOrNull!;

      expect(
        documents.map((document) => document.id),
        <String>[second.id, first.id],
      );
    });
  });

  group('deleteDocument', () {
    test('removes the record and the page files', () async {
      final document = await create(pages: 2);
      final pagePath = paths.absolutePath(document.pages.first.imagePath);
      expect(File(pagePath).existsSync(), isTrue);

      final result = await repository.deleteDocument(document.id);

      expect(result.isSuccess, isTrue);
      expect(box.get(document.id), isNull);
      expect(File(pagePath).existsSync(), isFalse);
      expect(
        Directory(p.join(tempDir.path, 'documents', document.id)).existsSync(),
        isFalse,
      );
    });

    test('succeeds for an id that was never there', () async {
      final result = await repository.deleteDocument('never-existed');

      expect(result.isSuccess, isTrue);
    });

    test('leaves other documents untouched', () async {
      final keep = await create(title: 'Keep');
      final remove = await create(title: 'Remove');

      await repository.deleteDocument(remove.id);

      final remaining = (await repository.getDocuments()).valueOrNull!;
      expect(remaining.map((document) => document.id), <String>[keep.id]);
      expect(
        File(paths.absolutePath(keep.pages.first.imagePath)).existsSync(),
        isTrue,
      );
    });
  });

  group('watchDocuments', () {
    test('emits the current library, then again on every change', () async {
      final emissions = <List<Document>>[];
      final subscription = repository.watchDocuments().listen(emissions.add);

      // Let the seed emission land before mutating.
      await Future<void>.delayed(Duration.zero);
      final document = await create();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await subscription.cancel();

      expect(emissions.first, isEmpty);
      expect(emissions.last.single.id, document.id);
    });

    test('re-emits after a delete', () async {
      final document = await create();

      final emissions = <List<Document>>[];
      final subscription = repository.watchDocuments().listen(emissions.add);
      await Future<void>.delayed(Duration.zero);

      await repository.deleteDocument(document.id);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await subscription.cancel();

      expect(emissions.first, hasLength(1));
      expect(emissions.last, isEmpty);
    });
  });
}
