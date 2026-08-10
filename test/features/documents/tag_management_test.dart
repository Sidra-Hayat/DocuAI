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
import 'package:docuai/src/features/documents/domain/usecases/update_document_tags.dart';
import 'package:docuai/src/features/documents/presentation/providers/document_providers.dart';
import 'package:docuai/src/features/documents/presentation/screens/document_detail_screen.dart';
import 'package:docuai/src/features/search/data/datasources/search_index_local_data_source.dart';
import 'package:docuai/src/features/search/data/repositories/bm25_search_repository.dart';
import 'package:docuai/src/features/search/presentation/providers/search_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';
import '../../helpers/ui.dart';

/// Tagging a document, end to end.
///
/// The capability was already stored, normalised and indexed — it simply had no
/// way in. So most of what follows is about the two things that were missing:
/// a surface to type into, and a tag being findable the moment it is added
/// rather than whenever the index next happens to rebuild.
void main() {
  group('normalisation', () {
    test('trims and lower-cases', () {
      expect(
        UpdateDocumentTags.normalise(<String>['  Receipts ', 'HOME']),
        <String>['receipts', 'home'],
      );
    });

    test('collapses duplicates however they were typed', () {
      expect(
        UpdateDocumentTags.normalise(<String>[
          'receipts',
          'Receipts',
          '  RECEIPTS  ',
        ]),
        <String>['receipts'],
      );
    });

    test('keeps the order they were entered in', () {
      expect(
        UpdateDocumentTags.normalise(<String>['zebra', 'apple', 'mango']),
        <String>['zebra', 'apple', 'mango'],
      );
    });

    test('drops blanks and over-long entries', () {
      expect(
        UpdateDocumentTags.normalise(<String>[
          '   ',
          '',
          'x' * (UpdateDocumentTags.maxTagLength + 1),
          'keep',
        ]),
        <String>['keep'],
      );
    });
  });

  group('saving', () {
    late Directory tempDir;
    late Box<DocumentModel> box;
    late Box<dynamic> indexBox;
    late DocumentRepository documents;
    late Bm25SearchRepository search;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('docuai_tags');
      Hive.init(p.join(tempDir.path, 'hive'));
      Hive.registerAdapters();
    });

    setUp(() async {
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

    Future<Document> seed({List<String> tags = const <String>[]}) async {
      final document = Document(
        id: 'bill',
        title: 'Electricity bill',
        createdAt: DateTime.utc(2026, 8, 1),
        updatedAt: DateTime.utc(2026, 8, 1),
        tags: tags,
        pages: <DocumentPage>[
          DocumentPage(
            id: 'bill-p0',
            imagePath: 'documents/bill/page_0.jpg',
            index: 0,
            text: 'Total amount due: 248.60 EUR',
            ocrStatus: OcrStatus.completed,
          ),
        ],
      );

      await documents.saveDocument(document);
      await search.indexDocument(document);
      return document;
    }

    Future<Document> setTags(List<String> tags) async =>
        (await UpdateDocumentTags(documents, search: search)(
          documentId: 'bill',
          tags: tags,
        )).valueOrNull!;

    test('a tag is stored on the document itself', () async {
      await seed();

      final tagged = await setTags(<String>['Utilities', ' home ']);

      expect(tagged.tags, <String>['utilities', 'home']);
      expect(
        (await documents.getDocument('bill')).valueOrNull!.tags,
        <String>['utilities', 'home'],
        reason: 'there is one tag store, and it is the document',
      );
    });

    test('a tag is searchable immediately, with no rebuild', () async {
      // The gap this step closed. The use case saved and returned; nothing
      // indexed, so a new tag only worked once the Search tab happened to
      // trigger a full rebuild.
      await seed();
      expect((await search.search('utilities')).valueOrNull, isEmpty);

      await setTags(<String>['utilities']);

      expect(
        (await search.search(
          'utilities',
        )).valueOrNull?.map((h) => h.document.id),
        contains('bill'),
      );
    });

    test('removing a tag removes it from the index too', () async {
      await seed(tags: <String>['utilities']);
      await search.indexDocument(
        (await documents.getDocument('bill')).valueOrNull!,
      );
      expect((await search.search('utilities')).valueOrNull, isNotEmpty);

      await setTags(<String>[]);

      expect(
        (await search.search('utilities')).valueOrNull,
        isEmpty,
        reason: 'a removed tag must stop matching',
      );
    });

    test('renaming a tag replaces it in the index', () async {
      await seed();
      await setTags(<String>['utilties']);
      expect((await search.search('utilties')).valueOrNull, isNotEmpty);

      await setTags(<String>['utilities']);

      expect((await search.search('utilties')).valueOrNull, isEmpty);
      expect((await search.search('utilities')).valueOrNull, isNotEmpty);
    });

    test('the rest of the document is untouched', () async {
      final before = await seed();

      final tagged = await setTags(<String>['utilities']);

      expect(tagged.title, before.title);
      expect(tagged.pages.single.text, before.pages.single.text);
      expect(tagged.pages.single.imagePath, before.pages.single.imagePath);
    });

    test('the library reorders, because the document changed', () async {
      final before = await seed();

      final tagged = await setTags(<String>['utilities']);

      expect(tagged.updatedAt.isAfter(before.updatedAt), isTrue);
    });

    test('too many tags is refused rather than truncated', () async {
      await seed();

      final result = await UpdateDocumentTags(documents, search: search)(
        documentId: 'bill',
        tags: <String>[
          for (var i = 0; i < UpdateDocumentTags.maxTagsPerDocument + 1; i++)
            'tag$i',
        ],
      );

      expect(result, isA<Failed<Document>>());
      expect((result as Failed<Document>).failure, isA<ValidationFailure>());
      expect(
        (await documents.getDocument('bill')).valueOrNull!.tags,
        isEmpty,
        reason: 'a refused edit must not half-apply',
      );
    });
  });

  group('the editing sheet', () {
    late Directory uiTempDir;
    late FakeDocumentRepository documents;
    late FakeSearchRepository search;

    setUpAll(() async {
      uiTempDir = await Directory.systemTemp.createTemp('docuai_tags_ui');
    });

    tearDownAll(() async {
      if (uiTempDir.existsSync()) await uiTempDir.delete(recursive: true);
    });

    setUp(() {
      documents = FakeDocumentRepository();
      search = FakeSearchRepository();
    });

    tearDown(() => documents.dispose());

    Future<void> pumpDetail(
      WidgetTester tester, {
      List<String> tags = const <String>[],
    }) async {
      documents.seed(
        buildDocument(id: 'bill', title: 'Electricity bill', tags: tags),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            documentRepositoryProvider.overrideWithValue(documents),
            searchRepositoryProvider.overrideWithValue(search),
            storagePathsProvider.overrideWithValue(StoragePaths(uiTempDir)),
          ],
          child: const MaterialApp(
            home: DocumentDetailScreen(documentId: 'bill'),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the document offers to be tagged when it has none', (
      tester,
    ) async {
      await pumpDetail(tester);

      expect(find.text('Add tags'), findsOneWidget);
    });

    testWidgets('existing tags are shown, with a way to change them', (
      tester,
    ) async {
      await pumpDetail(tester, tags: <String>['utilities', 'home']);

      expect(find.text('utilities'), findsOneWidget);
      expect(find.text('home'), findsOneWidget);
      expect(find.text('Edit tags'), findsOneWidget);
    });

    testWidgets('adding a tag stores it normalised', (tester) async {
      await pumpDetail(tester);

      await tester.tap(find.text('Add tags'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '  Receipts ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(documents.store['bill']!.tags, <String>['receipts']);
      expect(
        search.indexedIds,
        contains('bill'),
        reason: 'a tag nobody indexed is a tag nobody can find',
      );
    });

    testWidgets('several tags can be typed at once, comma separated', (
      tester,
    ) async {
      await pumpDetail(tester);
      await tester.tap(find.text('Add tags'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'receipts, 2026, home');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(documents.store['bill']!.tags, <String>[
        'receipts',
        '2026',
        'home',
      ]);
    });

    testWidgets('text left in the field is not discarded on save', (
      tester,
    ) async {
      // Requiring "add" before "save" would silently drop a tag the user had
      // plainly finished typing.
      await pumpDetail(tester);
      await tester.tap(find.text('Add tags'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'unsubmitted');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(documents.store['bill']!.tags, <String>['unsubmitted']);
    });

    testWidgets('a duplicate adds nothing', (tester) async {
      await pumpDetail(tester, tags: <String>['receipts']);
      await tester.tap(find.text('Edit tags'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'RECEIPTS');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(documents.store['bill']!.tags, <String>['receipts']);
    });

    testWidgets('a tag can be removed', (tester) async {
      await pumpDetail(tester, tags: <String>['utilities', 'home']);
      await tester.tap(find.text('Edit tags'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove utilities'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(documents.store['bill']!.tags, <String>['home']);
    });

    testWidgets('tapping a tag lifts it back for renaming', (tester) async {
      await pumpDetail(tester, tags: <String>['utilties']);
      await tester.tap(find.text('Edit tags'));
      await tester.pumpAndSettle();

      // The chip inside the sheet, not the one on the screen behind it.
      await tester.tap(find.widgetWithText(InputChip, 'utilties'));
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'utilties',
        reason: 'renaming reuses the add path rather than a second one',
      );

      await tester.enterText(find.byType(TextField), 'utilities');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(documents.store['bill']!.tags, <String>['utilities']);
    });

    testWidgets('cancelling changes nothing', (tester) async {
      await pumpDetail(tester, tags: <String>['utilities']);
      await tester.tap(find.text('Edit tags'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'discarded');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(documents.store['bill']!.tags, <String>['utilities']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opening and closing the sheet throws nothing', (tester) async {
      // The controller-ownership trap the rename dialog already fell into once.
      await pumpDetail(tester, tags: <String>['utilities']);

      for (var i = 0; i < 2; i++) {
        await tester.tap(find.text('Edit tags'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
        await tester.pumpAndSettle();
      }

      expect(tester.takeException(), isNull);
    });

    testWidgets('the action menu offers tag editing', (tester) async {
      await pumpDetail(tester, tags: <String>['utilities']);

      await openDocumentActions(tester);

      expect(find.text('Edit tags'), findsWidgets);
    });
  });
}
