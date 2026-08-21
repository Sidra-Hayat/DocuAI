import 'dart:io';

import 'package:docuai/hive_registrar.g.dart';
import 'package:docuai/src/core/router/app_routes.dart';
import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/features/archives/domain/entities/zip_build.dart';
import 'package:docuai/src/features/archives/presentation/screens/archive_screen.dart';
import 'package:docuai/src/features/documents/data/datasources/document_local_data_source.dart';
import 'package:docuai/src/features/documents/data/models/document_model.dart';
import 'package:docuai/src/features/documents/data/models/document_page_model.dart';
import 'package:docuai/src/features/documents/data/repositories/document_repository_impl.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/documents/presentation/providers/document_providers.dart';
import 'package:docuai/src/features/documents/presentation/screens/documents_screen.dart';
import 'package:docuai/src/features/documents/presentation/widgets/document_card.dart';
import 'package:docuai/src/features/search/data/datasources/search_index_local_data_source.dart';
import 'package:docuai/src/features/search/data/repositories/bm25_search_repository.dart';
import 'package:docuai/src/features/search/domain/entities/search_hit.dart';
import 'package:docuai/src/features/search/presentation/providers/search_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';
import '../../helpers/ui.dart';

/// A ZIP, once it has been saved, is an ordinary library item.
///
/// That claim is the whole feature, and it is only worth anything if it holds
/// through the parts of the app the user actually touches: the record survives
/// a restart, the card says what it is, tapping it opens the reader rather than
/// a pager with no pages, and deleting it takes the file with it and leaves the
/// documents it was built from alone.
void main() {
  group('surviving a restart', () {
    late Directory tempDir;
    late Box<DocumentModel> box;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('docuai_saved_archive');
      Hive.init(p.join(tempDir.path, 'hive'));
      Hive.registerAdapters();
    });

    tearDownAll(() async {
      await Hive.close();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    setUp(() async {
      box = await Hive.openBox<DocumentModel>(
        'documents_${DateTime.now().microsecondsSinceEpoch}',
      );
    });

    tearDown(() async {
      await box.deleteFromDisk();
    });

    test('an archive record round-trips through a real Hive box', () async {
      // Force-stopping the app is not a code path — it is the absence of one.
      // What has to be true is that the record was on disk before the process
      // died and decodes to the same thing afterwards, which is what a real box
      // reopened by the real adapter proves.
      final saved = Document(
        id: 'zip-1',
        title: 'DocuAI 2026-08-21.zip',
        createdAt: DateTime.utc(2026, 8, 21, 9),
        updatedAt: DateTime.utc(2026, 8, 21, 9),
        pages: const <DocumentPage>[],
        source: DocumentSource.archive,
        archivePath: 'documents/zip-1/DocuAI 2026-08-21.zip',
        archiveBytes: 20 * 1024 * 1024,
      );

      await box.put(saved.id, DocumentModel.fromEntity(saved));

      final reopened = box.get('zip-1')!.toEntity();

      expect(reopened.isArchive, isTrue);
      expect(reopened.source, DocumentSource.archive);
      expect(reopened.title, 'DocuAI 2026-08-21.zip');
      expect(reopened.archivePath, 'documents/zip-1/DocuAI 2026-08-21.zip');
      expect(reopened.archiveBytes, 20 * 1024 * 1024);
    });

    test('a record written before archives existed still opens', () async {
      // The fields were appended, so every document already on a user's phone
      // decodes with them absent. This is the check that an update does not
      // empty somebody's library.
      final old = DocumentModel(
        id: 'doc-old',
        title: 'Water bill',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        pages: const <DocumentPageModel>[],
        tags: const <String>[],
        pdfPath: null,
        isFavorite: false,
        source: DocumentSource.scanned.name,
      );

      await box.put(old.id, old);
      final reopened = box.get('doc-old')!.toEntity();

      expect(reopened.archivePath, isNull);
      expect(reopened.archiveBytes, isNull);
      expect(reopened.isArchive, isFalse);
      expect(reopened.source, DocumentSource.scanned);
    });
  });

  group('taking ownership of the file', () {
    late Directory workspace;
    late Directory documentsRoot;
    late Directory cache;
    late DocumentLocalDataSource local;
    late Box<DocumentModel> box;

    setUp(() async {
      workspace = await Directory.systemTemp.createTemp('docuai_archive_store');
      documentsRoot = await Directory(p.join(workspace.path, 'docs')).create();
      cache = await Directory(p.join(workspace.path, 'cache')).create();

      Hive.init(p.join(workspace.path, 'hive'));
      box = await Hive.openBox<DocumentModel>(
        'docs_${DateTime.now().microsecondsSinceEpoch}',
      );
      local = DocumentLocalDataSource(
        box: box,
        paths: StoragePaths(documentsRoot),
      );
    });

    tearDown(() async {
      await box.deleteFromDisk();
      if (workspace.existsSync()) await workspace.delete(recursive: true);
    });

    String buildZip(String name, String contents) {
      final path = p.join(cache.path, name);
      File(path).writeAsStringSync(contents);
      return path;
    }

    test('moves the archive into the document’s own folder', () async {
      final source = buildZip('scratch.zip', 'PK pretend archive');

      final model = await local.createArchive(
        title: 'Bundle.zip',
        fileName: 'Bundle.zip',
        sourceZipPath: source,
      );

      final absolute = StoragePaths(
        documentsRoot,
      ).absolutePath(model.archivePath!);

      expect(File(absolute).existsSync(), isTrue);
      expect(File(absolute).readAsStringSync(), 'PK pretend archive');
      expect(p.basename(absolute), 'Bundle.zip');
      // Inside the folder the document owns, which is what makes deleting the
      // document delete the archive with no extra code.
      expect(p.basename(p.dirname(absolute)), model.id);
    });

    test('moves rather than copies, leaving nothing behind', () async {
      final source = buildZip('scratch.zip', 'PK pretend archive');

      await local.createArchive(
        title: 'Bundle.zip',
        fileName: 'Bundle.zip',
        sourceZipPath: source,
      );

      expect(
        File(source).existsSync(),
        isFalse,
        reason: 'a second copy of a large archive is not a detail on a phone',
      );
    });

    test('records the size it actually moved', () async {
      final source = buildZip('scratch.zip', 'x' * 4096);

      final model = await local.createArchive(
        title: 'Bundle.zip',
        fileName: 'Bundle.zip',
        sourceZipPath: source,
      );

      expect(model.archiveBytes, 4096);
      expect(model.pages, isEmpty);
      expect(model.source, DocumentSource.archive.name);
    });

    test('deleting the record removes the archive from disk', () async {
      final model = await local.createArchive(
        title: 'Bundle.zip',
        fileName: 'Bundle.zip',
        sourceZipPath: buildZip('scratch.zip', 'PK'),
      );
      final absolute = StoragePaths(
        documentsRoot,
      ).absolutePath(model.archivePath!);
      expect(File(absolute).existsSync(), isTrue);

      await local.delete(model.id);

      expect(File(absolute).existsSync(), isFalse);
      expect(box.get(model.id), isNull);
    });

    test('deleting an archive leaves other documents untouched', () async {
      // The question somebody hesitates over before pressing Delete: the ZIP was
      // built out of documents they still want.
      final kept = await local.create(
        title: 'Rent receipt',
        sourceImagePaths: <String>[buildZip('page.jpg', 'jpeg bytes')],
      );

      final archive = await local.createArchive(
        title: 'Bundle.zip',
        fileName: 'Bundle.zip',
        sourceZipPath: buildZip('scratch.zip', 'PK'),
      );

      await local.delete(archive.id);

      final survivor = box.get(kept.id);
      expect(survivor, isNotNull);
      expect(
        File(
          StoragePaths(documentsRoot).absolutePath(survivor!.pages.first.imagePath!),
        ).existsSync(),
        isTrue,
      );
    });
  });

  group('in the library', () {
    late FakeDocumentRepository documents;
    late FakeSearchRepository search;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('docuai_archive_library');
      documents = FakeDocumentRepository();
      search = FakeSearchRepository();
    });

    tearDown(() async {
      documents.dispose();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    Document archiveDocument({
      String id = 'zip-1',
      String title = 'DocuAI 2026-08-21.zip',
      int bytes = 12 * 1024 * 1024,
    }) => buildDocument(
      id: id,
      title: title,
      // Newest, so the library's newest-first order puts it first and "the
      // first overflow menu" means this one rather than whichever row Hive
      // happened to return.
      updatedAt: kNow,
      pages: const <DocumentPage>[],
      source: DocumentSource.archive,
      archivePath: 'documents/$id/$title',
      archiveBytes: bytes,
    );

    /// The library on a real router, because opening an archive is a push.
    Future<void> pumpLibrary(WidgetTester tester) async {
      final router = GoRouter(
        initialLocation: '/',
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (context, state) => const DocumentsScreen(),
            routes: <RouteBase>[
              GoRoute(
                path: 'archive',
                name: AppRoutes.archiveName,
                builder: (context, state) =>
                    ArchiveScreen(args: state.extra! as ArchiveArgs),
              ),
              GoRoute(
                path: 'detail/:id',
                name: AppRoutes.documentDetailName,
                builder: (context, state) =>
                    const Scaffold(body: Text('the document')),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            documentRepositoryProvider.overrideWithValue(documents),
            searchRepositoryProvider.overrideWithValue(search),
            storagePathsProvider.overrideWithValue(StoragePaths(tempDir)),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('an archive sits in the library beside documents', (
      tester,
    ) async {
      documents.seed(buildDocument(id: 'doc-a', title: 'Lecture notes'));
      documents.seed(archiveDocument());

      await pumpLibrary(tester);

      expect(find.text('Lecture notes'), findsOneWidget);
      expect(find.text('DocuAI 2026-08-21.zip'), findsOneWidget);
      expect(find.byType(DocumentCard), findsNWidgets(2));
    });

    testWidgets('the card says it is an archive and how big it is', (
      tester,
    ) async {
      documents.seed(archiveDocument(bytes: 12 * 1024 * 1024));
      await pumpLibrary(tester);

      // The badge every other library item has, saying what this one is.
      expect(find.text('Archive'), findsOneWidget);
      // Size rather than a page count, which is the number somebody about to
      // send a ZIP wants and the only one an archive has.
      expect(find.textContaining('12 MB'), findsOneWidget);
      expect(find.textContaining('page'), findsNothing);
      expect(find.byIcon(Icons.folder_zip_outlined), findsWidgets);
    });

    testWidgets('an archive is never waiting for text to be read', (
      tester,
    ) async {
      // A page-less document reports its recognition as pending, which would
      // put "Text not read yet" on a ZIP for ever.
      documents.seed(archiveDocument());
      await pumpLibrary(tester);

      expect(find.text('Text not read yet'), findsNothing);
      expect(find.text('Reading the text…'), findsNothing);
    });

    testWidgets('tapping an archive opens the reader, not a pager', (
      tester,
    ) async {
      documents.seed(archiveDocument());
      await pumpLibrary(tester);

      await tester.tap(find.text('DocuAI 2026-08-21.zip'));
      // Pumped rather than settled: the reader parses the archive on another
      // isolate, which never settles under the test binding — and which screen
      // was reached is the thing under test, not what it managed to read.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The same screen an archive shared from WhatsApp opens into.
      expect(find.byType(ArchiveScreen), findsOneWidget);
      expect(find.text('the document'), findsNothing);
    });

    testWidgets('deleting an archive says what it will not remove', (
      tester,
    ) async {
      documents.seed(archiveDocument());
      await pumpLibrary(tester);

      await tapDocumentAction(tester, 'Delete');

      expect(find.text('Delete archive?'), findsOneWidget);
      expect(
        find.textContaining('documents and files it was made from are not'),
        findsOneWidget,
      );
    });

    testWidgets('deleting an archive removes only that row', (tester) async {
      documents.seed(buildDocument(id: 'doc-a', title: 'Lecture notes'));
      documents.seed(archiveDocument());
      await pumpLibrary(tester);

      await tapDocumentAction(tester, 'Delete');
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(find.text('DocuAI 2026-08-21.zip'), findsNothing);
      expect(find.text('Lecture notes'), findsOneWidget);
    });

    testWidgets('an archive offers to share the .zip itself', (tester) async {
      documents.seed(archiveDocument());
      await pumpLibrary(tester);

      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();

      // Not "Send a PDF or a Word file" — there is nothing here to convert.
      expect(find.text('Send the .zip file'), findsOneWidget);
      expect(find.text('Send a PDF or a Word file'), findsNothing);
    });
  });

  group('finding one again', () {
    late Directory tempDir;
    late Box<DocumentModel> box;
    late Box<dynamic> indexBox;
    late DocumentRepositoryImpl documents;
    late Bm25SearchRepository search;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('docuai_archive_search');
      Hive.init(p.join(tempDir.path, 'hive'));
      final stamp = DateTime.now().microsecondsSinceEpoch;
      box = await Hive.openBox<DocumentModel>('docs_$stamp');
      indexBox = await Hive.openBox<dynamic>('index_$stamp');
      documents = DocumentRepositoryImpl(
        DocumentLocalDataSource(box: box, paths: StoragePaths(tempDir)),
      );
      search = Bm25SearchRepository(
        index: SearchIndexLocalDataSource(indexBox),
        documents: documents,
      );
    });

    tearDown(() async {
      await box.deleteFromDisk();
      await indexBox.deleteFromDisk();
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    });

    test('an archive is findable by its file name', () async {
      // Search already indexes titles, and an archive's title is its file name
      // — so this needed no change to search at all. The test is here because
      // "no change was needed" is a claim worth holding still: an archive has
      // no recognised text, and an indexer that assumed every document had some
      // would have quietly dropped it.
      final scratch = File(p.join(tempDir.path, 'scratch.zip'))
        ..writeAsStringSync('PK');

      final saved = await documents.createArchive(
        title: 'Tax return 2026.zip',
        fileName: 'Tax return 2026.zip',
        sourceZipPath: scratch.path,
      );
      final archive = saved.valueOrNull!;

      final all = await documents.getDocuments();
      await search.rebuildIndex(all.valueOrNull!);

      final hits = await search.search('tax return');

      expect(hits.valueOrNull!.map((SearchHit hit) => hit.document.id), <String>[
        archive.id,
      ]);
    });

    test('an archive with no text does not break the indexer', () async {
      final scratch = File(p.join(tempDir.path, 'scratch.zip'))
        ..writeAsStringSync('PK');

      await documents.createArchive(
        title: 'Bundle.zip',
        fileName: 'Bundle.zip',
        sourceZipPath: scratch.path,
      );
      await documents.createTextDocument(title: 'Lecture notes');

      final all = await documents.getDocuments();
      final rebuilt = await search.rebuildIndex(all.valueOrNull!);

      expect(rebuilt.isSuccess, isTrue);
    });
  });

  group('naming', () {
    test('a second archive on the same day is numbered, not overwritten', () {
      final taken = <String>{'docuai 2026-08-21.zip'};

      expect(
        uniqueNameAgainst('DocuAI 2026-08-21.zip', taken),
        'DocuAI 2026-08-21 (2).zip',
      );
    });

    test('numbering continues past the second', () {
      final taken = <String>{
        'docuai 2026-08-21.zip',
        'docuai 2026-08-21 (2).zip',
      };

      expect(
        uniqueNameAgainst('DocuAI 2026-08-21.zip', taken),
        'DocuAI 2026-08-21 (3).zip',
      );
    });

    test('an archive keeps its own name inside another archive', () {
      // Not "DocuAI 2026-08-21.zip.pdf". The document path appends `.pdf`
      // because a document becomes one; an archive is already the file.
      final source = ZipSource.archive(
        documentId: 'zip-1',
        title: 'DocuAI 2026-08-21.zip',
        sizeBytes: 4096,
      );

      expect(source.preferredEntryName, 'DocuAI 2026-08-21.zip');
      expect(source.isArchive, isTrue);
    });

    test('an ordinary document still becomes a PDF', () {
      final source = ZipSource.document(
        documentId: 'doc-1',
        title: 'Rent receipt',
        pageCount: 2,
      );

      expect(source.preferredEntryName, 'Rent receipt.pdf');
      expect(source.isArchive, isFalse);
    });

    test('a free name is left exactly as it is', () {
      expect(uniqueNameAgainst('Holiday.zip', <String>{}), 'Holiday.zip');
    });

    test('path separators still cannot survive into a file name', () {
      // Unchanged by persistence, and re-checked here because the name is now
      // written to disk *and* shown in the library.
      expect(sanitiseEntryName('2024/05 Rent'), '2024_05 Rent');
      expect(sanitiseEntryName(r'a\b'), 'a_b');
    });
  });
}
