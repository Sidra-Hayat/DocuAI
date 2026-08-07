import 'dart:io';

import 'package:docuai/hive_registrar.g.dart';
import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/features/documents/data/datasources/documents_box.dart';
import 'package:docuai/src/features/documents/data/models/document_model.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/presentation/providers/document_providers.dart';
import 'package:docuai/src/features/documents/presentation/screens/documents_screen.dart';
import 'package:docuai/src/features/search/data/datasources/search_index_local_data_source.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

/// Exercises the provider graph the app actually assembles, over real Hive.
///
/// The repository's own stream is covered in
/// `document_repository_impl_test.dart`. This sits one layer up, where the
/// reported failure was: the store updates, the use case reports success, and
/// the screen keeps showing the deleted document.
void main() {
  late Directory tempDir;
  late Box<DocumentModel> documentsBox;
  late Box<dynamic> searchIndexBox;
  late ProviderContainer container;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_reactivity');
    Hive.init(p.join(tempDir.path, 'hive'));
    Hive.registerAdapters();
  });

  setUp(() async {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    documentsBox = await Hive.openBox<DocumentModel>('documents_$stamp');
    searchIndexBox = await Hive.openBox<dynamic>('index_$stamp');

    container = ProviderContainer(
      overrides: [
        documentsBoxProvider.overrideWithValue(documentsBox),
        searchIndexBoxProvider.overrideWithValue(searchIndexBox),
        storagePathsProvider.overrideWithValue(StoragePaths(tempDir)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await documentsBox.deleteFromDisk();
    await searchIndexBox.deleteFromDisk();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  Future<List<String>> writeSourceImages(int count) async {
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
        ).writeAsBytes(<int>[0xFF, 0xD8, 0xFF, 0xD9])).path,
    ];
  }

  Future<Document> createDocument(String title) async {
    final result = await container
        .read(documentRepositoryProvider)
        .createFromImages(
          title: title,
          sourceImagePaths: await writeSourceImages(1),
        );
    return result.valueOrNull!;
  }

  /// Lets the box event reach the stream and the provider rebuild.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 50));

  /// Starts the library subscription the way the screen does, and records
  /// every list it is handed.
  List<List<Document>> listenToLibrary() {
    final seen = <List<Document>>[];
    container.listen<AsyncValue<List<Document>>>(
      documentsProvider,
      (previous, next) {
        final value = next.value;
        if (value != null) seen.add(value);
      },
      fireImmediately: true,
    );
    return seen;
  }

  test('the library stream reaches the provider on create', () async {
    final seen = listenToLibrary();
    await settle();

    await createDocument('Water bill');
    await settle();

    expect(seen.last.map((document) => document.title), <String>['Water bill']);
  });

  test('deleting a document updates the library without a restart', () async {
    final seen = listenToLibrary();
    await settle();

    final document = await createDocument('Water bill');
    await settle();
    expect(seen.last, hasLength(1));

    final result = await container.read(deleteDocumentProvider)(document.id);
    await settle();

    expect(result.isSuccess, isTrue);
    expect(documentsBox.get(document.id), isNull, reason: 'gone from Hive');
    expect(
      container.read(documentsProvider).value,
      isEmpty,
      reason: 'the screen reads this — it must not still hold the document',
    );
    expect(seen.last, isEmpty);
  });

  test('deleting one of several leaves the rest', () async {
    final seen = listenToLibrary();
    await settle();

    final keep = await createDocument('Keep me');
    await settle();
    final remove = await createDocument('Remove me');
    await settle();
    expect(seen.last, hasLength(2));

    await container.read(deleteDocumentProvider)(remove.id);
    await settle();

    expect(
      container.read(documentsProvider).value?.map((d) => d.id),
      <String>[keep.id],
    );
  });

  test('documentProvider resolves to null once its document is deleted', () async {
    listenToLibrary();
    await settle();

    final document = await createDocument('Water bill');
    await settle();
    expect(container.read(documentProvider(document.id)).value?.id, document.id);

    await container.read(deleteDocumentProvider)(document.id);
    await settle();

    expect(
      container.read(documentProvider(document.id)).value,
      isNull,
      reason: 'the detail screen pops itself on null',
    );
  });

  testWidgets('the library screen drops a deleted document without a restart', (
    tester,
  ) async {
    late Document document;

    // Real file and Hive I/O has to run outside the fake-async zone, or the
    // awaits inside never complete.
    await tester.runAsync(() async {
      document = await createDocument('Water bill');
      await settle();
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: DocumentsScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Water bill'), findsOneWidget);

    await tester.runAsync(() async {
      await container.read(deleteDocumentProvider)(document.id);
      await settle();
    });
    await tester.pumpAndSettle();

    expect(find.text('Water bill'), findsNothing);
    expect(find.text('No documents yet'), findsOneWidget);
  });

  test('renaming is reflected in the library', () async {
    final seen = listenToLibrary();
    await settle();

    final document = await createDocument('Before');
    await settle();

    await container.read(renameDocumentProvider)(
      documentId: document.id,
      title: 'After',
    );
    await settle();

    expect(seen.last.single.title, 'After');
  });
}
