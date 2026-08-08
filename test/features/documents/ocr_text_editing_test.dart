import 'dart:io';

import 'package:docuai/hive_registrar.g.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/features/assistant/data/datasources/passage_extractor.dart';
import 'package:docuai/src/features/documents/data/datasources/document_local_data_source.dart';
import 'package:docuai/src/features/documents/data/models/document_model.dart';
import 'package:docuai/src/features/documents/data/repositories/document_repository_impl.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/documents/domain/repositories/document_repository.dart';
import 'package:docuai/src/features/documents/domain/usecases/edit_page_text.dart';
import 'package:docuai/src/features/ocr/domain/usecases/recognize_document_text.dart';
import 'package:docuai/src/features/search/data/datasources/search_index_local_data_source.dart';
import 'package:docuai/src/features/search/data/repositories/bm25_search_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';

/// Correcting the text a scan was read as.
///
/// The value of this feature is that OCR is fallible and the user can see the
/// page. What it must never cost them is the scan itself, or the correction —
/// so most of what follows is about what *survives* an edit rather than what
/// changes.
void main() {
  late Directory tempDir;
  late Box<DocumentModel> box;
  late Box<dynamic> indexBox;
  late StoragePaths paths;
  late DocumentRepository repository;
  late Bm25SearchRepository search;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_ocr_edit');
    Hive.init(p.join(tempDir.path, 'hive'));
    Hive.registerAdapters();
  });

  setUp(() async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    box = await Hive.openBox<DocumentModel>('docs_$stamp');
    indexBox = await Hive.openBox<dynamic>('index_$stamp');
    paths = StoragePaths(tempDir);
    repository = DocumentRepositoryImpl(
      DocumentLocalDataSource(box: box, paths: paths),
    );
    search = Bm25SearchRepository(
      index: SearchIndexLocalDataSource(indexBox),
      documents: repository,
    );
  });

  tearDown(() async {
    if (box.isOpen) await box.deleteFromDisk();
    if (indexBox.isOpen) await indexBox.deleteFromDisk();
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

  /// A scanned document whose pages have already been read.
  Future<Document> scanned({
    int pages = 1,
    String text = 'T0tal amaunt due 5OO.OO EUR',
  }) async {
    final created = (await repository.createFromImages(
      title: 'Electricity bill',
      sourceImagePaths: await captures(pages),
    )).valueOrNull!;

    return (await repository.saveDocument(
      created.copyWith(
        pages: <DocumentPage>[
          for (final page in created.pages)
            page.copyWith(text: text, ocrStatus: OcrStatus.completed),
        ],
      ),
    )).valueOrNull!;
  }

  Future<Document> correct(Document document, String text, {int page = 0}) async =>
      (await EditPageText(documents: repository, search: search)(
        documentId: document.id,
        pageId: document.pages[page].id,
        text: text,
      )).valueOrNull!;

  group('the scan survives the correction', () {
    test('the page keeps its image', () async {
      final document = await scanned();
      final imageBefore = document.pages.single.imagePath;

      final corrected = await correct(document, 'Total amount due 500.00 EUR');

      expect(corrected.pages.single.imagePath, imageBefore);
      expect(corrected.pages.single.hasImage, isTrue);
      expect(corrected.pages.single.kind, PageKind.scanned);
    });

    test('the file is still on disk', () async {
      final document = await scanned();
      final file = File(paths.absolutePath(document.pages.single.imagePath!));
      expect(file.existsSync(), isTrue);

      await correct(document, 'Total amount due 500.00 EUR');

      expect(
        file.existsSync(),
        isTrue,
        reason: 'correcting what a page says must not touch what it looks like',
      );
    });

    test('correcting one page leaves the others alone', () async {
      final document = await scanned(pages: 3);

      final corrected = await correct(document, 'Corrected first page.');

      expect(corrected.pages[0].text, 'Corrected first page.');
      expect(corrected.pages[1].text, 'T0tal amaunt due 5OO.OO EUR');
      expect(corrected.pages[2].text, 'T0tal amaunt due 5OO.OO EUR');
      expect(corrected.pages[1].hasEditedText, isFalse);
    });
  });

  group('recognition does not undo it', () {
    test('a forced re-read leaves a corrected page alone', () async {
      // The one path in this phase that can destroy work with no error and no
      // undo: a re-read reproduces what the scanner sees, and a correction is
      // precisely what it cannot see.
      final document = await scanned(pages: 2);
      final corrected = await correct(document, 'Total amount due 500.00 EUR');

      final ocr = FakeOcrRepository()
        ..defaultResult = const Success('T0tal amaunt due 5OO.OO EUR');
      final rerun = (await RecognizeDocumentText(
        ocr: ocr,
        documents: repository,
        search: search,
      )(corrected.id, force: true)).valueOrNull!;

      expect(rerun.pages[0].text, 'Total amount due 500.00 EUR');
      expect(
        ocr.requestedPaths,
        hasLength(1),
        reason: 'only the page nobody had corrected was re-read',
      );
      expect(ocr.requestedPaths.single, corrected.pages[1].imagePath);
    });

    test('an ordinary run never had it in scope anyway', () async {
      final document = await scanned();
      final corrected = await correct(document, 'Total amount due 500.00 EUR');

      expect(corrected.pages.single.ocrStatus, OcrStatus.completed);
      expect(corrected.pagesAwaitingOcr, isEmpty);
    });

    test('the correction is remembered across a reload', () async {
      final document = await scanned();
      await correct(document, 'Total amount due 500.00 EUR');

      final reopened = (await repository.getDocument(document.id)).valueOrNull!;

      expect(reopened.pages.single.hasEditedText, isTrue);
      expect(reopened.pages.single.textEditedAt, isNotNull);
    });

    test('an untouched page is not marked as corrected', () async {
      final document = await scanned();

      expect(document.pages.single.hasEditedText, isFalse);
      expect(document.pages.single.textEditedAt, isNull);
    });

    test('the mark survives a reorder', () async {
      final document = await scanned(pages: 2);
      final corrected = await correct(document, 'Corrected.');

      final reordered = (await repository.reorderPages(
        documentId: corrected.id,
        orderedPageIds: corrected.pages.reversed
            .map((page) => page.id)
            .toList(),
      )).valueOrNull!;

      final moved = reordered.pages.firstWhere(
        (page) => page.id == corrected.pages.first.id,
      );
      expect(
        moved.hasEditedText,
        isTrue,
        reason: 'losing the mark would make the page fair game for a re-read',
      );
    });
  });

  group('the rest of the app sees the correction', () {
    test('search returns the corrected wording, not the recognised one', () async {
      final document = await scanned();
      await search.indexDocument(document);

      await correct(document, 'Total amount due 500.00 EUR');

      expect((await search.search('amaunt')).valueOrNull, isEmpty);
      expect(
        (await search.search('amount')).valueOrNull?.map((h) => h.document.id),
        contains(document.id),
      );
    });

    test('the assistant quotes the corrected text', () async {
      final document = await scanned();
      final corrected = await correct(
        document,
        'The total amount due is 500.00 EUR. Payable by 05/04/2026.',
      );

      final passages = PassageExtractor.extract(corrected);

      expect(
        passages.map((passage) => passage.text).join(' '),
        contains('500.00 EUR'),
      );
      expect(
        passages.map((passage) => passage.text).join(' '),
        isNot(contains('amaunt')),
      );
    });

    test('a PDF exported before the edit is invalidated', () async {
      final document = await scanned();
      final withPdf = (await repository.saveDocument(
        document.copyWith(pdfPath: 'documents/${document.id}/bill.pdf'),
      )).valueOrNull!;
      expect(withPdf.hasPdf, isTrue);

      final corrected = await correct(withPdf, 'Total amount due 500.00 EUR');

      expect(
        corrected.pdfPath,
        isNull,
        reason: 'sharing a PDF that predates the edit would send the typo on',
      );
    });

    test('the library sees it move to the top', () async {
      final document = await scanned();

      final corrected = await correct(document, 'Total amount due 500.00 EUR');

      expect(corrected.updatedAt.isAfter(document.updatedAt), isTrue);
    });
  });

  group('a page recognition found nothing on', () {
    test('can be written by hand and becomes searchable', () async {
      final blank = (await repository.createFromImages(
        title: 'Faint receipt',
        sourceImagePaths: await captures(1),
      )).valueOrNull!;

      expect(blank.hasText, isFalse);

      final written = await correct(blank, 'Paid in cash on 12/03/2026.');

      expect(written.hasText, isTrue);
      expect(written.pages.single.hasImage, isTrue);
      expect(
        (await search.search('cash')).valueOrNull?.map((h) => h.document.id),
        contains(blank.id),
      );
    });
  });
}
