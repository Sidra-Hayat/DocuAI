import 'dart:io';
import 'dart:typed_data';

import 'package:docuai/hive_registrar.g.dart';
import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/features/assistant/data/datasources/passage_extractor.dart';
import 'package:docuai/src/features/documents/data/datasources/document_local_data_source.dart';
import 'package:docuai/src/features/documents/data/models/document_model.dart';
import 'package:docuai/src/features/documents/data/repositories/document_repository_impl.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/documents/domain/repositories/document_repository.dart';
import 'package:docuai/src/features/documents/domain/usecases/create_text_document.dart';
import 'package:docuai/src/features/documents/domain/usecases/delete_document.dart';
import 'package:docuai/src/features/documents/domain/usecases/edit_page_text.dart';
import 'package:docuai/src/features/documents/domain/usecases/rename_document.dart';
import 'package:docuai/src/features/documents/domain/usecases/toggle_favorite.dart';
import 'package:docuai/src/features/documents/domain/usecases/update_document_tags.dart';
import 'package:docuai/src/features/export/data/datasources/pdf_composer.dart';
import 'package:docuai/src/features/export/data/repositories/export_repository_impl.dart';
import 'package:docuai/src/features/search/data/datasources/search_index_local_data_source.dart';
import 'package:docuai/src/features/search/data/repositories/bm25_search_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';

/// Documents you write rather than scan.
///
/// The claim under test is that there is no second document system: a written
/// document is an ordinary `Document` holding an ordinary `DocumentPage`, so
/// renaming, tagging, favouriting, deleting, searching, retrieval and export
/// all work through code that predates it and knows nothing about it.
void main() {
  late Directory tempDir;
  late Box<DocumentModel> box;
  late Box<dynamic> indexBox;
  late StoragePaths paths;
  late DocumentRepository repository;
  late Bm25SearchRepository search;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_text_doc');
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

  Future<Document> newNote({String title = 'Tenancy notes'}) async =>
      (await CreateTextDocument(repository)(title: title)).valueOrNull!;

  Future<Document> write(Document document, String text) async =>
      (await EditPageText(documents: repository, search: search)(
        documentId: document.id,
        pageId: document.pages.first.id,
        text: text,
      )).valueOrNull!;

  group('creating', () {
    test('starts as one empty page, written rather than captured', () async {
      final note = await newNote();

      expect(note.title, 'Tenancy notes');
      expect(note.source, DocumentSource.created);
      expect(note.pages, hasLength(1));

      final page = note.pages.single;
      expect(page.kind, PageKind.text);
      expect(page.imagePath, isNull);
      expect(page.text, isEmpty);
      expect(
        page.ocrStatus,
        OcrStatus.completed,
        reason: 'nothing to recognise, so nothing outstanding',
      );
    });

    test('writes no files, only a record', () async {
      final note = await newNote();

      expect(
        Directory(p.join(paths.documentsRoot.path, note.id)).existsSync(),
        isFalse,
        reason: 'a note the user never exports should leave nothing on disk',
      );
      expect(box.get(note.id), isNotNull);
    });

    test('an unnamed document still gets a usable title', () async {
      final note =
          (await CreateTextDocument(repository)(title: '   ')).valueOrNull!;

      expect(note.title, CreateTextDocument.defaultTitle);
    });

    test('a title too long to rename to cannot be created with', () async {
      final result = await CreateTextDocument(repository)(
        title: 'x' * (RenameDocument.maxTitleLength + 1),
      );

      expect(result, isA<Failed<Document>>());
      expect((result as Failed<Document>).failure, isA<ValidationFailure>());
    });

    test('it never asks recognition to run', () async {
      final note = await newNote();

      expect(note.ocrStatus, OcrStatus.completed);
      expect(note.pagesAwaitingOcr, isEmpty);
    });
  });

  group('writing', () {
    test('the text is on the page, where every other reader looks', () async {
      final note = await write(await newNote(), 'The deposit is 500.00 EUR.');

      expect(note.pages.single.text, 'The deposit is 500.00 EUR.');
      expect(note.extractedText, 'The deposit is 500.00 EUR.');
      expect(note.hasText, isTrue);
    });

    test('it survives being read back from storage', () async {
      final note = await write(await newNote(), 'Renewal due in March.');

      final reopened = (await repository.getDocument(note.id)).valueOrNull!;

      expect(reopened.pages.single.text, 'Renewal due in March.');
      expect(reopened.pages.single.kind, PageKind.text);
      expect(reopened.source, DocumentSource.created);
    });

    test('an edit moves the document to the top of the library', () async {
      final note = await newNote();
      final edited = await write(note, 'Something new.');

      expect(edited.updatedAt.isAfter(note.updatedAt), isTrue);
    });

    test('an edit invalidates a PDF exported before it', () async {
      // Otherwise Share hands over a file that predates the edit — discovered
      // only by whoever received it.
      final note = await newNote();
      await repository.saveDocument(
        (await write(note, 'First draft.')).copyWith(
          pdfPath: 'documents/${note.id}/note.pdf',
        ),
      );

      final edited = await write(note, 'Second draft.');

      expect(edited.pdfPath, isNull);
    });

    test('a second page can be added and written separately', () async {
      final note = await newNote();
      final grown =
          (await AddTextPage(repository)(note.id)).valueOrNull!;

      expect(grown.pages, hasLength(2));
      expect(grown.pages.last.kind, PageKind.text);

      final written = (await EditPageText(
        documents: repository,
        search: search,
      )(
        documentId: note.id,
        pageId: grown.pages.last.id,
        text: 'Second page.',
      )).valueOrNull!;

      expect(written.pages.map((page) => page.text), <String>[
        '',
        'Second page.',
      ]);
    });
  });

  group('the library actions work unchanged', () {
    test('rename', () async {
      final note = await newNote();

      final renamed = (await RenameDocument(repository)(
        documentId: note.id,
        title: 'Lease notes',
      )).valueOrNull!;

      expect(renamed.title, 'Lease notes');
      expect(renamed.source, DocumentSource.created, reason: 'origin is fixed');
      expect(renamed.pages.single.kind, PageKind.text);
    });

    test('favourite', () async {
      final note = await newNote();

      final starred =
          (await ToggleFavorite(repository)(note.id)).valueOrNull!;

      expect(starred.isFavorite, isTrue);
      expect(starred.pages.single.kind, PageKind.text);
    });

    test('tags', () async {
      final note = await newNote();

      final tagged = (await UpdateDocumentTags(repository, search: search)(
        documentId: note.id,
        tags: const <String>['Home', 'rent'],
      )).valueOrNull!;

      expect(tagged.tags, isNotEmpty);
    });

    test('delete removes the record and de-indexes it', () async {
      final note = await write(await newNote(), 'A note about the boiler.');
      await search.indexDocument(note);

      final deleted = await DeleteDocument(
        documents: repository,
        search: search,
      )(note.id);

      expect(deleted, isA<Success<void>>());
      expect(box.get(note.id), isNull);
      expect(
        (await search.search('boiler')).valueOrNull,
        isEmpty,
        reason: 'a hit that opens nothing is worse than no hit',
      );
    });
  });

  group('search sees it immediately', () {
    test('a written note is findable by its own words', () async {
      final note = await write(
        await newNote(title: 'Boiler service'),
        'The engineer is booked for 12/03/2026.',
      );

      final hits = (await search.search('engineer')).valueOrNull!;

      expect(hits.map((hit) => hit.document.id), contains(note.id));
    });

    test('an edit replaces what the index holds, without a rebuild', () async {
      // The failure this rules out: the library redraws from the box watch at
      // once, so an edit that did not re-index would look saved while search
      // kept returning the old wording.
      final note = await newNote(title: 'Notes');
      await write(note, 'The boiler is under warranty.');

      expect((await search.search('boiler')).valueOrNull, isNotEmpty);

      await write(note, 'The dishwasher is under warranty.');

      expect(
        (await search.search('boiler')).valueOrNull,
        isEmpty,
        reason: 'the old wording is gone from the page and from the index',
      );
      expect((await search.search('dishwasher')).valueOrNull, isNotEmpty);
    });

    test('emptying a note takes it out of the index', () async {
      final note = await newNote();
      await write(note, 'Temporary thought.');
      expect((await search.search('temporary')).valueOrNull, isNotEmpty);

      await write(note, '');

      expect(
        (await search.search('temporary')).valueOrNull,
        isEmpty,
        reason: 'left indexed it would match text it no longer contains',
      );
    });

    test('it is findable by title, like any other document', () async {
      final note = await write(
        await newNote(title: 'Mortgage offer'),
        'Body text.',
      );

      final hits = (await search.search('mortgage')).valueOrNull!;
      expect(hits.map((hit) => hit.document.id), contains(note.id));
    });
  });

  group('the assistant can read it', () {
    test('a written page yields passages like a scanned one', () async {
      final note = await write(
        await newNote(),
        'The deposit is 500.00 EUR. It is refundable on the final inspection.',
      );

      final passages = PassageExtractor.extract(note);

      expect(passages, isNotEmpty);
      expect(
        passages.first.pageIndex,
        0,
        reason: 'a citation still points at a page the user can open',
      );
      expect(
        passages.map((passage) => passage.text).join(' '),
        contains('500.00 EUR'),
      );
    });

    test('a mixed document offers passages from both kinds', () async {
      final note = await write(await newNote(), 'A heading I typed myself.');

      final mixed = (await repository.saveDocument(
        note.copyWith(
          pages: <DocumentPage>[
            note.pages.single,
            buildPage(
              id: 'scan',
              index: 1,
              imagePath: 'documents/${note.id}/scan.jpg',
              text: 'Recognised from the scan.',
              ocrStatus: OcrStatus.completed,
            ),
          ],
        ),
      )).valueOrNull!;

      final pages = PassageExtractor.extract(
        mixed,
      ).map((passage) => passage.pageIndex).toSet();

      expect(pages, <int>{0, 1});
    });
  });

  group('PDF export', () {
    late List<PdfJob> rendered;
    late ExportRepositoryImpl export;

    setUp(() {
      rendered = <PdfJob>[];
      export = ExportRepositoryImpl(
        paths: paths,
        renderer: (job) async {
          rendered.add(job);
          return Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]);
        },
      );
    });

    test('a written document exports its text', () async {
      final note = await write(await newNote(), 'The deposit is 500.00 EUR.');

      final result = await export.buildPdf(note);

      expect(result, isA<Success<String>>());
      expect(rendered.single.pages, hasLength(1));
      expect(
        (rendered.single.pages.single as PdfTextPage).text,
        'The deposit is 500.00 EUR.',
      );
      expect(rendered.single.title, 'Tenancy notes');
    });

    test('an empty note is refused rather than exported blank', () async {
      final note = await newNote();

      final result = await export.buildPdf(note);

      expect(result, isA<Failed<String>>());
      expect(rendered, isEmpty);
    });

    test('a mixed document keeps its pages in order', () async {
      final note = await write(await newNote(), 'Typed first.');

      final scanFile = File(
        paths.absolutePath('documents/${note.id}/scan.jpg'),
      );
      await scanFile.parent.create(recursive: true);
      await scanFile.writeAsBytes(<int>[0xFF, 0xD8, 0xFF, 0xD9]);

      final mixed = (await repository.saveDocument(
        note.copyWith(
          pages: <DocumentPage>[
            note.pages.single,
            buildPage(
              id: 'scan',
              index: 1,
              imagePath: 'documents/${note.id}/scan.jpg',
              ocrStatus: OcrStatus.completed,
            ),
          ],
        ),
      )).valueOrNull!;

      await export.buildPdf(mixed);

      expect(rendered.single.pages.map((page) => page.runtimeType), <Type>[
        PdfTextPage,
        PdfImagePage,
      ]);
    });
  });
}
