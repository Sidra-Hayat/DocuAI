import 'dart:io';
import 'dart:typed_data';

import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/features/archives/data/datasources/zip_reader.dart';
import 'package:docuai/src/features/archives/data/datasources/zip_writer.dart';
import 'package:docuai/src/features/archives/data/repositories/zip_builder_repository_impl.dart';
import 'package:docuai/src/features/archives/domain/entities/zip_build.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/documents/domain/repositories/document_repository.dart';
import 'package:docuai/src/features/export/domain/repositories/export_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// The ZIP builder, on a real phone.
///
/// Everything here is the production code path — the real encoder, the real
/// `archive` package, real isolates, and the device's own cache directory — run
/// against files that are actually written to the phone's storage. The desktop
/// unit tests prove the logic; these prove it survives an ARM device with a
/// real memory ceiling, which is the part that cannot be faked.
///
/// The scenarios are the ones on the test list: two files, more than ten,
/// images only, PDFs only, mixed types, a large archive, and stopping part way
/// through. Every archive produced is read back through DocuAI's own
/// `ZipReader`, and the last test leaves its output where `adb pull` can reach
/// it so the file can be opened by something that is not this app at all.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory scratch;
  late Directory cache;
  late Directory documentsRoot;
  late _DeviceExport export;
  late _DeviceDocuments documents;

  setUp(() async {
    final temp = await getTemporaryDirectory();
    scratch = await Directory(p.join(temp.path, 'device_test_sources')).create(
      recursive: true,
    );
    cache = await Directory(p.join(temp.path, 'device_test_cache')).create(
      recursive: true,
    );
    documentsRoot = await Directory(
      p.join(temp.path, 'device_test_docs'),
    ).create(recursive: true);

    export = _DeviceExport(documentsRoot);
    documents = _DeviceDocuments(documentsRoot);
  });

  tearDown(() async {
    for (final directory in <Directory>[scratch, cache, documentsRoot]) {
      if (directory.existsSync()) await directory.delete(recursive: true);
    }
  });

  ZipBuilderRepositoryImpl repository({ZipWriter? writer}) =>
      ZipBuilderRepositoryImpl(
        documents: documents,
        export: export,
        paths: StoragePaths(documentsRoot),
        writer: writer ?? const ZipWriter(),
        shareLauncher: (params) async =>
            const ShareResult('not opened in a test', ShareResultStatus.success),
        temporaryDirectory: () async => cache,
      );

  /// A file of [kilobytes] on the phone's own storage.
  ZipSource realFile(String name, int kilobytes, {bool compressible = true}) {
    final path = p.join(scratch.path, name);
    final bytes = Uint8List(kilobytes * 1024);

    if (compressible) {
      // Text-shaped: repetitive enough that deflate has real work to do, and
      // varied enough to compress like prose rather than like a zip bomb.
      //
      // This is not fussiness. A file of one repeated byte deflates about
      // 650:1, and DocuAI's *reader* refuses anything past 300:1 as a bomb —
      // so a degenerate fixture here would produce an archive the app declines
      // to list, and the test would be measuring the fixture rather than the
      // encoder. Real text reaches perhaps ten to one.
      const words = <String>[
        'invoice', 'total', 'due', 'March', 'account', 'balance',
        'reference', 'payment', 'received', 'thank you',
      ];
      var seed = 0x1B873593;
      var written = 0;
      while (written < bytes.length) {
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
        final word = '${words[seed % words.length]} ${seed % 100000} ';
        for (final unit in word.codeUnits) {
          if (written >= bytes.length) break;
          bytes[written++] = unit;
        }
      }
    } else {
      // Pseudo-random and incompressible, which is what a JPEG or an already
      // compressed PDF actually looks like to the encoder.
      var seed = 0x2F6E2B1;
      for (var i = 0; i < bytes.length; i++) {
        seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
        bytes[i] = seed & 0xFF;
      }
    }

    File(path).writeAsBytesSync(bytes);
    return ZipSource.file(
      path: path,
      name: name,
      sizeBytes: File(path).lengthSync(),
    );
  }

  ZipSource realDocument(String id, String title, {int pages = 3}) {
    documents.store[id] = Document(
      id: id,
      title: title,
      createdAt: DateTime(2026, 8, 21),
      updatedAt: DateTime(2026, 8, 21),
      pages: <DocumentPage>[
        for (var i = 0; i < pages; i++)
          DocumentPage(
            id: '$id-$i',
            imagePath: 'documents/$id/page_$i.jpg',
            index: i,
            text: '',
            ocrStatus: OcrStatus.completed,
            kind: PageKind.scanned,
          ),
      ],
    );
    return ZipSource.document(documentId: id, title: title, pageCount: pages);
  }

  /// Builds, then insists the result is an archive this app can read back.
  Future<ZipBuildOutcome> buildAndVerify(
    List<ZipSource> sources,
    String name, {
    ZipWriter? writer,
    bool Function()? isCancelled,
    void Function(int done, int total, String label)? onProgress,
  }) async {
    final result = await repository(writer: writer).build(
      sources: sources,
      archiveName: name,
      isCancelled: isCancelled,
      onProgress: (progress) =>
          onProgress?.call(progress.done, progress.total, progress.label),
    );

    expect(
      result,
      isA<Success<ZipBuildOutcome>>(),
      reason: result.failureOrNull?.message,
    );

    final outcome = result.valueOrNull!;

    expect(File(outcome.path).existsSync(), isTrue);
    expect(
      p.isWithin(documentsRoot.path, outcome.path),
      isTrue,
      reason: 'a saved archive lives in the library’s own storage',
    );
    expect(
      p.isWithin(cache.path, outcome.path),
      isFalse,
      reason: 'the cache is where it is built, never where it is kept',
    );

    // And the scratch space is empty again — the archive was moved, not copied.
    final scratch = Directory(
      p.join(cache.path, ZipBuilderRepositoryImpl.rootDirectory),
    );
    expect(
      scratch.existsSync()
          ? scratch.listSync(recursive: true).whereType<File>().toList()
          : <File>[],
      isEmpty,
    );

    // Read back through the app's own reader, on the device, which is the same
    // path an incoming ZIP from WhatsApp takes.
    final listing = ZipReader.listSync(outcome.path);
    expect(listing.fileCount, outcome.entryCount);
    expect(listing.refusedEntries, 0);

    return outcome;
  }

  testWidgets('two files', (tester) async {
    final outcome = await buildAndVerify(<ZipSource>[
      realFile('statement.pdf', 200, compressible: false),
      realFile('notes.txt', 40),
    ], 'Two files');

    expect(outcome.entryCount, 2);
    expect(outcome.isComplete, isTrue);
    expect(outcome.fileName, 'Two files.zip');
  });

  testWidgets('more than ten files', (tester) async {
    final outcome = await buildAndVerify(<ZipSource>[
      for (var i = 0; i < 14; i++) realFile('file_$i.txt', 60),
    ], 'Fourteen');

    expect(outcome.entryCount, 14);
    expect(
      ZipReader.listSync(outcome.path).files.length,
      14,
      reason: 'every one of them has to come back out again',
    );
  });

  testWidgets('images only', (tester) async {
    // The case that decides whether storing rather than deflating was right: a
    // dozen photographs are already compressed, and an encoder that deflates
    // them anyway does a great deal of work to make the archive no smaller.
    final outcome = await buildAndVerify(<ZipSource>[
      for (var i = 0; i < 12; i++)
        realFile('photo_$i.jpg', 400, compressible: false),
    ], 'Photos');

    expect(outcome.entryCount, 12);
    // Within a whisker of what went in, which is the honest outcome for JPEGs
    // and what the result screen says out loud.
    expect(outcome.sizeBytes, greaterThan((outcome.sourceBytes * 0.98).round()));
    expect(outcome.sizeBytes, lessThan((outcome.sourceBytes * 1.02).round()));
  });

  testWidgets('PDFs only', (tester) async {
    final outcome = await buildAndVerify(<ZipSource>[
      for (var i = 0; i < 6; i++)
        realFile('invoice_$i.pdf', 500, compressible: false),
    ], 'Invoices');

    expect(outcome.entryCount, 6);
    for (final entry in ZipReader.listSync(outcome.path).files) {
      expect(entry.path, endsWith('.pdf'));
    }
  });

  testWidgets('mixed types, documents and files together', (tester) async {
    final outcome = await buildAndVerify(<ZipSource>[
      realDocument('doc-a', 'Lease agreement'),
      realFile('photo.jpg', 300, compressible: false),
      realDocument('doc-b', 'Inventory'),
      realFile('notes.txt', 20),
      realFile('spreadsheet.xlsx', 80, compressible: false),
    ], 'Move house');

    expect(outcome.entryCount, 5);

    final names = ZipReader.listSync(outcome.path).files
        .map((entry) => entry.path)
        .toList();

    expect(names, containsAll(<String>[
      'Lease agreement.pdf',
      'Inventory.pdf',
      'photo.jpg',
      'notes.txt',
      'spreadsheet.xlsx',
    ]));
  });

  testWidgets('a large archive', (tester) async {
    // Roughly 60 MB of incompressible content, which is the shape that found
    // three bugs at once in the import path. The thing being proved here is
    // that it completes on a phone at all: the encoder streams stored entries
    // rather than buffering them, so peak memory is a buffer and not the file.
    final sources = <ZipSource>[
      for (var i = 0; i < 12; i++)
        realFile('big_$i.jpg', 5 * 1024, compressible: false),
    ];

    final progress = <int>[];
    final outcome = await buildAndVerify(
      sources,
      'Large',
      onProgress: (done, total, label) => progress.add(done),
    );

    expect(outcome.entryCount, 12);
    expect(outcome.sizeBytes, greaterThan(50 * 1024 * 1024));

    // Progress has to actually move, or the bar is a spinner with extra steps.
    expect(progress, isNotEmpty);
    expect(progress.last, greaterThan(progress.first));

    // And the whole thing is still readable end to end.
    final listing = ZipReader.listSync(outcome.path);
    expect(listing.fileCount, 12);
    expect(listing.totalBytes, greaterThan(50 * 1024 * 1024));
  });

  testWidgets('stopping part way leaves nothing behind', (tester) async {
    var cancelled = false;

    final result = await repository(
      writer: const ZipWriter(pollInterval: Duration(milliseconds: 1)),
    ).build(
      sources: <ZipSource>[
        for (var i = 0; i < 10; i++) realFile('big_$i.jpg', 2 * 1024),
      ],
      archiveName: 'Stopped',
      isCancelled: () => cancelled,
      onProgress: (progress) {
        if (progress.label.startsWith('big_')) cancelled = true;
      },
    );

    final failure = result.failureOrNull;
    expect(failure, isA<ImportFailure>());
    expect((failure! as ImportFailure).cancelled, isTrue);

    // The requirement, checked on the device's own file system: no archive, no
    // part file, nothing left in the cache for the next run to trip over.
    final root = Directory(
      p.join(cache.path, ZipBuilderRepositoryImpl.rootDirectory),
    );
    final leftovers = root.existsSync()
        ? root.listSync(recursive: true).whereType<File>().toList()
        : <File>[];

    expect(
      leftovers,
      isEmpty,
      reason: 'a stopped build must not leave a partial file anywhere',
    );
  });

  testWidgets('the result can be pulled off the phone and opened elsewhere', (
    tester,
  ) async {
    // Written where `adb pull` can reach it, so the archive can be opened by
    // something that is not this app — the only check that really answers "any
    // file manager can open it".
    final outcome = await buildAndVerify(<ZipSource>[
      realFile('report.pdf', 300, compressible: false),
      realFile('photo.jpg', 250, compressible: false),
      realFile('notes.txt', 30),
      realDocument('doc-a', 'Scanned letter'),
    ], 'Interop check');

    final external = await getExternalStorageDirectory();
    if (external == null) return;

    final copy = File(p.join(external.path, 'docuai_interop_check.zip'));
    await File(outcome.path).copy(copy.path);

    expect(copy.existsSync(), isTrue);
    // ignore: avoid_print
    print('DEVICE_ARCHIVE_AT ${copy.path}');
  });
}

/// The library, in memory over a real directory.
///
/// Hive is not what these tests are about, but the **file move** is: an archive
/// has to end up in persistent storage and leave nothing in the cache, and only
/// a fake that actually moves it can show that on a device.
class _DeviceDocuments implements DocumentRepository {
  _DeviceDocuments(this.root);

  /// Stands in for the app documents directory.
  final Directory root;

  final Map<String, Document> store = <String, Document>{};
  var _next = 0;

  @override
  FutureResult<Document> getDocument(String id) async {
    final document = store[id];
    if (document == null) {
      return Failed(StorageFailure('No document with id "$id".'));
    }
    return Success(document);
  }

  @override
  FutureResult<List<Document>> getDocuments() async =>
      Success(store.values.toList());

  @override
  FutureResult<Document> saveDocument(Document document) async {
    store[document.id] = document;
    return Success(document);
  }

  @override
  FutureResult<Document> createArchive({
    required String title,
    required String fileName,
    required String sourceZipPath,
  }) async {
    final id = 'archive-${_next++}';
    final relative = p.join('documents', id, fileName);
    final target = File(p.join(root.path, relative));
    target.parent.createSync(recursive: true);

    final source = File(sourceZipPath);
    final sizeBytes = await source.length();
    await source.rename(target.path);

    final now = DateTime(2026, 8, 21);
    final document = Document(
      id: id,
      title: title,
      createdAt: now,
      updatedAt: now,
      pages: const <DocumentPage>[],
      source: DocumentSource.archive,
      archivePath: relative,
      archiveBytes: sizeBytes,
    );

    store[id] = document;
    return Success(document);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here.');
}

/// Writes a PDF-shaped file where it says it did.
class _DeviceExport implements ExportRepository {
  _DeviceExport(this.root);

  final Directory root;

  @override
  FutureResult<String> buildPdf(Document document) async {
    final relative = p.join('documents', document.id, '${document.id}.pdf');
    final file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);

    // Big enough to be a real entry rather than a token, and incompressible
    // like a PDF of scanned pages.
    final bytes = Uint8List(220 * 1024);
    var seed = 0x51F3A7;
    for (var i = 0; i < bytes.length; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
      bytes[i] = seed & 0xFF;
    }
    bytes.setAll(0, '%PDF-1.4'.codeUnits);
    file.writeAsBytesSync(bytes);

    return Success(relative);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here.');
}
