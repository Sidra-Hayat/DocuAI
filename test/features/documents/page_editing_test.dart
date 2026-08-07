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
import 'package:docuai/src/features/documents/domain/usecases/edit_document_pages.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';

/// Page editing against real Hive and a real filesystem, because the whole
/// point of these operations is what happens to the records *and* the files.
void main() {
  late Directory tempDir;
  late Box<DocumentModel> box;
  late StoragePaths paths;
  late DocumentRepository repository;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_page_edit');
    Hive.init(p.join(tempDir.path, 'hive'));
    Hive.registerAdapters();
  });

  setUp(() async {
    box = await Hive.openBox<DocumentModel>(
      'pages_${DateTime.now().microsecondsSinceEpoch}',
    );
    paths = StoragePaths(tempDir);
    repository = DocumentRepositoryImpl(
      DocumentLocalDataSource(box: box, paths: paths),
    );
  });

  tearDown(() async {
    if (box.isOpen) await box.deleteFromDisk();
  });

  tearDownAll(() async {
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } on FileSystemException {
      // Windows may still hold a box file; the OS reclaims it.
    }
  });

  Future<List<String>> captures(int count) async {
    final source = await Directory(
      p.join(tempDir.path, 'incoming'),
    ).create(recursive: true);

    return <String>[
      for (var i = 0; i < count; i++)
        (await File(
          p.join(
            source.path,
            'cap_${DateTime.now().microsecondsSinceEpoch}_$i.jpg',
          ),
        ).writeAsBytes(<int>[0xFF, 0xD8, i, 0xFF, 0xD9])).path,
    ];
  }

  Future<Document> create({int pages = 3}) async {
    final result = await repository.createFromImages(
      title: 'Rental agreement',
      sourceImagePaths: await captures(pages),
    );
    return (result as Success<Document>).value;
  }

  bool imageExists(DocumentPage page) =>
      File(paths.absolutePath(page.imagePath)).existsSync();

  group('addPages', () {
    test('appends pages after the existing ones', () async {
      final document = await create(pages: 2);

      final updated = (await repository.addPages(
        documentId: document.id,
        sourceImagePaths: await captures(2),
      )).valueOrNull!;

      expect(updated.pageCount, 4);
      expect(updated.pages.map((page) => page.index), <int>[0, 1, 2, 3]);
      for (final page in updated.pages) {
        expect(imageExists(page), isTrue, reason: page.imagePath);
      }
    });

    test('new pages start unread', () async {
      final document = await create(pages: 1);

      final updated = (await repository.addPages(
        documentId: document.id,
        sourceImagePaths: await captures(1),
      )).valueOrNull!;

      expect(updated.pages.last.ocrStatus, OcrStatus.pending);
      expect(updated.pages.last.text, isEmpty);
    });

    test('a missing source adds nothing and leaves no orphan files', () async {
      final document = await create(pages: 2);
      final before = Directory(
        p.join(tempDir.path, 'documents', document.id),
      ).listSync().length;

      final result = await repository.addPages(
        documentId: document.id,
        sourceImagePaths: <String>[p.join(tempDir.path, 'nope.jpg')],
      );

      expect(result.failureOrNull, isA<StorageFailure>());
      expect(
        Directory(p.join(tempDir.path, 'documents', document.id))
            .listSync()
            .length,
        before,
        reason: 'a half-finished add must not leave files nothing points at',
      );
    });
  });

  group('deletePage', () {
    test('removes the page, its file, and renumbers the rest', () async {
      final document = await create(pages: 3);
      final removed = document.pages[1];

      final updated = (await repository.deletePage(
        documentId: document.id,
        pageId: removed.id,
      )).valueOrNull!;

      expect(updated.pageCount, 2);
      expect(updated.pages.map((page) => page.id), isNot(contains(removed.id)));
      expect(updated.pages.map((page) => page.index), <int>[0, 1]);
      expect(imageExists(removed), isFalse);
    });

    test('refuses to remove the only page', () async {
      final document = await create(pages: 1);

      final result = await repository.deletePage(
        documentId: document.id,
        pageId: document.pages.single.id,
      );

      expect(result.failureOrNull, isA<StorageFailure>());
      expect(
        result.failureOrNull!.message,
        contains('at least one page'),
        reason: 'emptying a document is a document delete, not a page delete',
      );
    });

    test('an unknown page id is a failure, not a silent success', () async {
      final document = await create(pages: 2);

      final result = await repository.deletePage(
        documentId: document.id,
        pageId: 'not-a-page',
      );

      expect(result.failureOrNull, isA<StorageFailure>());
    });
  });

  group('reorderPages', () {
    test('applies the new order and renumbers', () async {
      final document = await create(pages: 3);
      final ids = document.pages.map((page) => page.id).toList();
      final reversed = ids.reversed.toList();

      final updated = (await repository.reorderPages(
        documentId: document.id,
        orderedPageIds: reversed,
      )).valueOrNull!;

      expect(updated.pages.map((page) => page.id), reversed);
      expect(updated.pages.map((page) => page.index), <int>[0, 1, 2]);
    });

    test('touches no files — order lives in the record alone', () async {
      final document = await create(pages: 3);
      final pathsBefore = document.pages.map((p) => p.imagePath).toSet();

      final updated = (await repository.reorderPages(
        documentId: document.id,
        orderedPageIds: document.pages.reversed.map((p) => p.id).toList(),
      )).valueOrNull!;

      expect(updated.pages.map((p) => p.imagePath).toSet(), pathsBefore);
      for (final page in updated.pages) {
        expect(imageExists(page), isTrue);
      }
    });

    test('rejects an order that does not name every page once', () async {
      final document = await create(pages: 3);

      final result = await repository.reorderPages(
        documentId: document.id,
        orderedPageIds: <String>[document.pages.first.id],
      );

      expect(result.failureOrNull, isA<StorageFailure>());
    });
  });

  group('replacePage', () {
    test('swaps the image but keeps the id and position', () async {
      final document = await create(pages: 3);
      final target = document.pages[1];

      final updated = (await repository.replacePage(
        documentId: document.id,
        pageId: target.id,
        sourceImagePath: (await captures(1)).single,
      )).valueOrNull!;

      final replaced = updated.pages[1];
      expect(replaced.id, target.id);
      expect(replaced.index, 1);
      expect(replaced.imagePath, isNot(target.imagePath));
      expect(imageExists(replaced), isTrue);
      expect(imageExists(target), isFalse, reason: 'the old image is removed');
    });

    test('clears the text, because it described the old image', () async {
      final document = await create(pages: 2);
      final withText = document.copyWith(
        pages: <DocumentPage>[
          document.pages.first.copyWith(
            text: 'old recognised text',
            ocrStatus: OcrStatus.completed,
          ),
          document.pages.last,
        ],
      );
      await repository.saveDocument(withText);

      final updated = (await repository.replacePage(
        documentId: document.id,
        pageId: document.pages.first.id,
        sourceImagePath: (await captures(1)).single,
      )).valueOrNull!;

      expect(updated.pages.first.text, isEmpty);
      expect(updated.pages.first.ocrStatus, OcrStatus.pending);
    });
  });

  group('any page change', () {
    test('drops the exported PDF, which no longer matches', () async {
      final document = await create(pages: 2);
      await repository.saveDocument(
        document.copyWith(pdfPath: 'documents/${document.id}/old.pdf'),
      );

      final updated = (await repository.addPages(
        documentId: document.id,
        sourceImagePaths: await captures(1),
      )).valueOrNull!;

      expect(updated.hasPdf, isFalse);
    });

    test('moves updatedAt so the library reorders and search re-indexes',
        () async {
      final document = await create(pages: 2);

      final updated = (await repository.addPages(
        documentId: document.id,
        sourceImagePaths: await captures(1),
      )).valueOrNull!;

      expect(updated.updatedAt.isAfter(document.updatedAt), isTrue);
    });
  });

  group('use cases', () {
    late FakeDocumentRepository documents;
    late FakeScannerRepository scanner;
    late FakeSearchRepository search;

    setUp(() {
      documents = FakeDocumentRepository()..seed(buildDocument());
      scanner = FakeScannerRepository();
      search = FakeSearchRepository();
    });

    tearDown(() => documents.dispose());

    test('AddPagesToDocument scans then appends, and re-indexes', () async {
      final add = AddPagesToDocument(
        scanner: scanner,
        documents: documents,
        search: search,
      );

      final result = await add('doc-1');

      expect(result.isSuccess, isTrue);
      expect(documents.pageOperations, contains('add:doc-1'));
      expect(search.indexedIds, contains('doc-1'));
    });

    test('a cancelled scan adds nothing and is flagged as cancelled', () async {
      scanner.result = const Success(<String>[]);
      final add = AddPagesToDocument(
        scanner: scanner,
        documents: documents,
        search: search,
      );

      final result = await add('doc-1');

      expect(
        result.failureOrNull,
        isA<ScanFailure>().having((f) => f.cancelled, 'cancelled', isTrue),
      );
      expect(documents.pageOperations, isEmpty);
    });

    test('ReplaceDocumentPage asks the scanner for exactly one page', () async {
      final replace = ReplaceDocumentPage(
        scanner: scanner,
        documents: documents,
        search: search,
      );

      await replace(documentId: 'doc-1', pageId: 'page-1');

      expect(scanner.lastPageLimit, 1);
      expect(documents.pageOperations, contains('replace:doc-1'));
    });

    test('ReorderDocumentPages does not re-index', () async {
      final reorder = ReorderDocumentPages(documents);

      await reorder(documentId: 'doc-1', orderedPageIds: <String>['page-1']);

      expect(documents.pageOperations, contains('reorder:doc-1'));
      expect(
        search.indexedIds,
        isEmpty,
        reason: 'reordering changes page numbers, not which words are in the '
            'document, and the index is document-level',
      );
    });

    test('DeleteDocumentPage re-indexes, since text left the document',
        () async {
      final delete = DeleteDocumentPage(documents: documents, search: search);

      await delete(documentId: 'doc-1', pageId: 'page-1');

      expect(documents.pageOperations, contains('delete:doc-1'));
      expect(search.indexedIds, contains('doc-1'));
    });
  });
}
