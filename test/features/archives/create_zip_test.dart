import 'dart:io';

import 'package:archive/archive.dart';
import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/features/archives/data/datasources/zip_reader.dart';
import 'package:docuai/src/features/archives/data/datasources/zip_writer.dart';
import 'package:docuai/src/features/archives/data/repositories/zip_builder_repository_impl.dart';
import 'package:docuai/src/features/archives/domain/entities/zip_build.dart';
import 'package:docuai/src/features/archives/domain/repositories/zip_builder_repository.dart';
import 'package:docuai/src/features/archives/domain/usecases/create_zip.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/export/domain/repositories/export_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../helpers/fakes.dart';

/// Building an archive out of the library and the phone.
///
/// Wired to a **real writer over a real temporary directory**, with only the
/// two things a test cannot have faked out: the library, and the PDF composer.
/// The archives these produce are decoded afterwards, and one of them is read
/// back through the app's own `ZipReader` — because the two halves of this
/// feature have to agree, and a mock on either side of that seam would let them
/// stop agreeing without anybody noticing.
void main() {
  late Directory workspace;
  late Directory documentsRoot;
  late Directory cache;
  late StoragePaths paths;
  late FakeDocumentRepository documents;
  late _WritingExportRepository export;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('docuai_zip_build');
    documentsRoot = await Directory(p.join(workspace.path, 'docs')).create();
    cache = await Directory(p.join(workspace.path, 'cache')).create();

    paths = StoragePaths(documentsRoot);
    documents = FakeDocumentRepository()..archiveRoot = documentsRoot;
    export = _WritingExportRepository(documentsRoot);
  });

  tearDown(() async {
    if (workspace.existsSync()) await workspace.delete(recursive: true);
  });

  ZipBuilderRepositoryImpl repository({
    ZipBuildLimits limits = const ZipBuildLimits(),
    _RecordingShare? share,
    ZipWriter writer = const ZipWriter(),
    DateTime? now,
  }) => ZipBuilderRepositoryImpl(
    documents: documents,
    export: export,
    paths: paths,
    writer: writer,
    limits: limits,
    shareLauncher: (share ?? _RecordingShare()).call,
    clock: now == null ? DateTime.now : () => now,
    temporaryDirectory: () async => cache,
  );

  /// A file on disk outside the library — what the system picker hands back.
  ZipSource pickedFile(String name, String contents) {
    final path = p.join(cache.path, name);
    File(path).writeAsStringSync(contents);
    return ZipSource.file(
      path: path,
      name: name,
      sizeBytes: File(path).lengthSync(),
    );
  }

  ZipSource seedDocument({
    required String id,
    required String title,
    int pages = 1,
    String? pdfPath,
  }) {
    documents.seed(
      buildDocument(
        id: id,
        title: title,
        pdfPath: pdfPath,
        pages: <DocumentPage>[
          for (var i = 0; i < pages; i++)
            buildPage(id: '$id-page-$i', index: i, imagePath: 'documents/$id/p$i.jpg'),
        ],
      ),
    );
    return ZipSource.document(documentId: id, title: title, pageCount: pages);
  }

  Archive decode(String path) =>
      ZipDecoder().decodeBytes(File(path).readAsBytesSync());

  List<String> namesIn(String path) =>
      decode(path).files.map((file) => file.name).toList();

  group('what goes in', () {
    test('a picked file goes in under its own name', () async {
      final result = await repository().build(
        sources: <ZipSource>[pickedFile('statement.pdf', 'bank')],
        archiveName: 'Sent',
      );

      final outcome = result.valueOrNull!;
      expect(outcome.fileName, 'Sent.zip');
      expect(outcome.entryCount, 1);
      expect(namesIn(outcome.path), <String>['statement.pdf']);
    });

    test('a document goes in as a PDF named after its title', () async {
      final source = seedDocument(id: 'doc-a', title: 'Rent receipt');

      final result = await repository().build(
        sources: <ZipSource>[source],
        archiveName: 'Archive',
      );

      final outcome = result.valueOrNull!;
      expect(namesIn(outcome.path), <String>['Rent receipt.pdf']);
      expect(export.buildCount, 1);
    });

    test('documents and files travel together in one archive', () async {
      final result = await repository().build(
        sources: <ZipSource>[
          seedDocument(id: 'doc-a', title: 'Lease'),
          pickedFile('photo.jpg', 'jpeg bytes'),
          seedDocument(id: 'doc-b', title: 'Inventory'),
        ],
        archiveName: 'Move',
      );

      expect(namesIn(result.valueOrNull!.path), <String>[
        'Lease.pdf',
        'photo.jpg',
        'Inventory.pdf',
      ]);
    });

    test('two documents with the same title do not overwrite each other', () async {
      // Left alone, both would be "Invoice.pdf" and the recipient would extract
      // one file out of an archive that claims to hold two.
      final result = await repository().build(
        sources: <ZipSource>[
          seedDocument(id: 'doc-a', title: 'Invoice'),
          seedDocument(id: 'doc-b', title: 'Invoice'),
        ],
        archiveName: 'Invoices',
      );

      expect(namesIn(result.valueOrNull!.path), <String>[
        'Invoice.pdf',
        'Invoice (2).pdf',
      ]);
    });

    test('reuses a PDF the document already has', () async {
      // Composing a PDF re-encodes every page image. For an archive of a dozen
      // documents, doing it again for one that has not changed is the
      // difference between seconds and a minute.
      final existing = p.join(documentsRoot.path, 'documents', 'doc-a', 'x.pdf');
      File(existing).parent.createSync(recursive: true);
      File(existing).writeAsStringSync('%PDF already here');

      final source = seedDocument(
        id: 'doc-a',
        title: 'Cached',
        pdfPath: 'documents/doc-a/x.pdf',
      );

      final result = await repository().build(
        sources: <ZipSource>[source],
        archiveName: 'Archive',
      );

      expect(export.buildCount, 0, reason: 'nothing needed rendering');
      final entry = decode(result.valueOrNull!.path).files.single;
      expect(String.fromCharCodes(entry.readBytes()!), '%PDF already here');
    });

    test('archiving does not reorder the library', () async {
      // The PDF path is cached back onto the document, but `updatedAt` is left
      // alone. Bumping it on every archived document would float all of them to
      // the top of a library sorted newest-first, as a side effect of sending a
      // ZIP — which is not something the user asked for.
      final source = seedDocument(id: 'doc-a', title: 'Report');
      final before = documents.store['doc-a']!.updatedAt;

      await repository().build(
        sources: <ZipSource>[source],
        archiveName: 'Archive',
      );

      final after = documents.store['doc-a']!;
      expect(after.updatedAt, before);
      expect(after.pdfPath, isNotNull, reason: 'the path is still cached');
    });
  });

  group('an archive inside an archive', () {
    test('a saved archive goes in as the .zip it already is', () async {
      // Found on a device. A saved ZIP is a library item, so the picker offers
      // it — and it used to take the ordinary document path, where the builder
      // tries to render a PDF, finds no pages, and drops the entry saying
      // "That document has nothing in it yet". The archive was not empty; it
      // simply is not made of pages.
      final inner = await repository().build(
        sources: <ZipSource>[pickedFile('a.txt', 'inner')],
        archiveName: 'Inner',
      );
      final innerDocument = inner.valueOrNull!.document;

      final outer = await repository().build(
        sources: <ZipSource>[
          ZipSource.archive(
            documentId: innerDocument.id,
            title: innerDocument.title,
            sizeBytes: innerDocument.archiveBytes ?? 0,
          ),
          pickedFile('b.txt', 'outer'),
        ],
        archiveName: 'Outer',
      );

      final outcome = outer.valueOrNull!;

      expect(outcome.isComplete, isTrue, reason: 'nothing should be skipped');
      expect(outcome.entryCount, 2);
      // Named for what it is, rather than "Inner.zip.pdf".
      expect(namesIn(outcome.path), <String>['Inner.zip', 'b.txt']);
    });

    test('the nested archive survives byte-for-byte', () async {
      final inner = await repository().build(
        sources: <ZipSource>[pickedFile('a.txt', 'inner contents')],
        archiveName: 'Inner',
      );
      final innerDocument = inner.valueOrNull!.document;
      final innerBytes = File(inner.valueOrNull!.path).readAsBytesSync();

      final outer = await repository().build(
        sources: <ZipSource>[
          ZipSource.archive(
            documentId: innerDocument.id,
            title: innerDocument.title,
            sizeBytes: innerDocument.archiveBytes ?? 0,
          ),
        ],
        archiveName: 'Outer',
      );

      final extracted = decode(
        outer.valueOrNull!.path,
      ).files.single.readBytes()!;

      expect(extracted, innerBytes);
      // And the inner archive is still in the library, untouched by being
      // copied into another one.
      expect(File(inner.valueOrNull!.path).existsSync(), isTrue);
    });

    test('an archive whose file has gone says so, and says which', () async {
      final inner = await repository().build(
        sources: <ZipSource>[pickedFile('a.txt', 'inner')],
        archiveName: 'Inner',
      );
      final innerDocument = inner.valueOrNull!.document;
      File(inner.valueOrNull!.path).deleteSync();

      final outer = await repository().build(
        sources: <ZipSource>[
          ZipSource.archive(
            documentId: innerDocument.id,
            title: innerDocument.title,
            sizeBytes: innerDocument.archiveBytes ?? 0,
          ),
          pickedFile('b.txt', 'outer'),
        ],
        archiveName: 'Outer',
      );

      final outcome = outer.valueOrNull!;
      expect(outcome.entryCount, 1);
      expect(outcome.skipped.single.name, 'Inner.zip');
      expect(
        outcome.skipped.single.reason,
        contains('no longer on this device'),
      );
    });
  });

  group('what is left out, and said', () {
    test('a file that has gone is skipped and named', () async {
      final missing = ZipSource.file(
        path: p.join(cache.path, 'vanished.pdf'),
        name: 'vanished.pdf',
        sizeBytes: 10,
      );

      final result = await repository().build(
        sources: <ZipSource>[pickedFile('here.txt', 'ok'), missing],
        archiveName: 'Archive',
      );

      final outcome = result.valueOrNull!;
      expect(outcome.entryCount, 1);
      expect(outcome.isComplete, isFalse);
      expect(outcome.skipped.single.name, 'vanished.pdf');
      expect(outcome.skipped.single.reason, contains('no longer on this device'));
    });

    test('a document that cannot be rendered is skipped, not fatal', () async {
      export.failFor.add('doc-b');

      final result = await repository().build(
        sources: <ZipSource>[
          seedDocument(id: 'doc-a', title: 'Good'),
          seedDocument(id: 'doc-b', title: 'Broken'),
        ],
        archiveName: 'Archive',
      );

      final outcome = result.valueOrNull!;
      expect(namesIn(outcome.path), <String>['Good.pdf']);
      expect(outcome.skipped.single.name, 'Broken');
    });

    test('an empty document is skipped with a reason a person can act on', () async {
      documents.seed(
        buildDocument(id: 'doc-empty', title: 'Blank', pages: <DocumentPage>[]),
      );

      final result = await repository().build(
        sources: <ZipSource>[
          pickedFile('a.txt', 'ok'),
          ZipSource.document(
            documentId: 'doc-empty',
            title: 'Blank',
            pageCount: 0,
          ),
        ],
        archiveName: 'Archive',
      );

      expect(
        result.valueOrNull!.skipped.single.reason,
        'That document has nothing in it yet.',
      );
    });

    test('nothing archivable fails rather than writing an empty archive', () async {
      final result = await repository().build(
        sources: <ZipSource>[
          ZipSource.file(path: p.join(cache.path, 'gone'), name: 'gone', sizeBytes: 0),
        ],
        archiveName: 'Archive',
      );

      expect(result, isA<Failed<ZipBuildOutcome>>());
      expect(cache.listSync(), isNot(contains(predicate(
        (FileSystemEntity e) => e.path.endsWith('.zip'),
      ))));
    });
  });

  group('stopping', () {
    test('returns a cancelled failure and leaves no archive behind', () async {
      final result = await repository().build(
        sources: <ZipSource>[
          seedDocument(id: 'doc-a', title: 'One'),
          pickedFile('b.txt', 'two'),
        ],
        archiveName: 'Archive',
        isCancelled: () => true,
      );

      final failure = result.failureOrNull;
      expect(failure, isA<ImportFailure>());
      expect((failure! as ImportFailure).cancelled, isTrue);

      // The whole run directory goes, so there is no part file and no archive.
      final root = Directory(p.join(cache.path, ZipBuilderRepositoryImpl.rootDirectory));
      expect(root.existsSync() ? root.listSync() : const <FileSystemEntity>[], isEmpty);
    });

    test('stopping part way through still leaves nothing', () async {
      var cancelled = false;

      final result = await repository(
        writer: const ZipWriter(pollInterval: Duration(milliseconds: 1)),
      ).build(
        sources: <ZipSource>[
          for (var i = 0; i < 6; i++) pickedFile('file_$i.txt', 'x' * 40000),
        ],
        archiveName: 'Archive',
        // Left running until the writing half has begun, so this exercises the
        // encoder being stopped rather than the request being refused.
        isCancelled: () => cancelled,
        onProgress: (progress) {
          if (progress.label.startsWith('file_')) cancelled = true;
        },
      );

      expect((result.failureOrNull! as ImportFailure).cancelled, isTrue);

      final root = Directory(p.join(cache.path, ZipBuilderRepositoryImpl.rootDirectory));
      final leftovers = root.existsSync()
          ? root.listSync(recursive: true).whereType<File>().toList()
          : <File>[];
      expect(leftovers, isEmpty);
    });
  });

  group('limits', () {
    test('refuses more files than one archive will hold', () async {
      final result = await repository(
        limits: const ZipBuildLimits(maxEntries: 2),
      ).build(
        sources: <ZipSource>[
          pickedFile('a.txt', 'a'),
          pickedFile('b.txt', 'b'),
          pickedFile('c.txt', 'c'),
        ],
        archiveName: 'Archive',
      );

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(result.failureOrNull!.message, contains('up to 2 files'));
    });

    test('refuses a selection larger than one archive will read', () async {
      final result = await repository(
        limits: const ZipBuildLimits(maxTotalBytes: 10),
      ).build(
        sources: <ZipSource>[pickedFile('big.txt', 'x' * 200)],
        archiveName: 'Archive',
      );

      expect(result.failureOrNull, isA<ValidationFailure>());
    });

    test('an empty selection is refused before anything is opened', () async {
      final result = await repository().build(
        sources: const <ZipSource>[],
        archiveName: 'Archive',
      );

      expect(result.failureOrNull, isA<ValidationFailure>());
    });
  });

  group('the archive itself', () {
    test('is kept in the library’s storage, not in the cache', () async {
      // The change this feature is: an archive used to live in the cache and be
      // swept after a few hours. It is now a library item, so it has to be
      // somewhere Android will not reclaim — and nowhere the user chose, which
      // would need a storage permission this app does not have.
      final result = await repository().build(
        sources: <ZipSource>[pickedFile('a.txt', 'hello')],
        archiveName: 'Archive',
      );

      final outcome = result.valueOrNull!;

      expect(File(outcome.path).existsSync(), isTrue);
      expect(p.isWithin(documentsRoot.path, outcome.path), isTrue);
      expect(
        p.isWithin(cache.path, outcome.path),
        isFalse,
        reason: 'the cache is where it is built, not where it is kept',
      );
    });

    test('leaves nothing of itself in the cache afterwards', () async {
      // Moved, not copied. A second copy of something that can be hundreds of
      // megabytes is not a detail on a phone that may be nearly full.
      final result = await repository().build(
        sources: <ZipSource>[pickedFile('a.txt', 'hello')],
        archiveName: 'Archive',
      );

      expect(File(result.valueOrNull!.path).existsSync(), isTrue);

      final root = Directory(
        p.join(cache.path, ZipBuilderRepositoryImpl.rootDirectory),
      );
      final leftInCache = root.existsSync()
          ? root.listSync(recursive: true).whereType<File>().toList()
          : <File>[];

      expect(leftInCache, isEmpty);
    });

    test('becomes a library item that names and measures itself', () async {
      final result = await repository().build(
        sources: <ZipSource>[pickedFile('a.txt', 'x' * 5000)],
        archiveName: 'Holiday photos',
      );

      final document = result.valueOrNull!.document;

      expect(document.isArchive, isTrue);
      expect(document.source, DocumentSource.archive);
      expect(document.title, 'Holiday photos.zip');
      expect(document.archiveBytes, File(result.valueOrNull!.path).lengthSync());
      // No pages, and therefore nothing outstanding to read — a library card
      // that said "Text not read yet" on a ZIP would be waiting for ever.
      expect(document.pages, isEmpty);
      expect(document.ocrStatus, OcrStatus.completed);

      // And it is in the store, which is what makes it survive a restart.
      expect(documents.store[document.id], isNotNull);
    });

    test('two archives on the same day do not overwrite each other', () async {
      final first = await repository().build(
        sources: <ZipSource>[pickedFile('a.txt', 'one')],
        archiveName: 'DocuAI 2026-08-21',
      );
      final second = await repository().build(
        sources: <ZipSource>[pickedFile('b.txt', 'two')],
        archiveName: 'DocuAI 2026-08-21',
      );
      final third = await repository().build(
        sources: <ZipSource>[pickedFile('c.txt', 'three')],
        archiveName: 'DocuAI 2026-08-21',
      );

      expect(first.valueOrNull!.fileName, 'DocuAI 2026-08-21.zip');
      expect(second.valueOrNull!.fileName, 'DocuAI 2026-08-21 (2).zip');
      expect(third.valueOrNull!.fileName, 'DocuAI 2026-08-21 (3).zip');

      // All three still on disk, each holding what it was given.
      for (final built in <Result<ZipBuildOutcome>>[first, second, third]) {
        expect(File(built.valueOrNull!.path).existsSync(), isTrue);
      }
      expect(namesIn(first.valueOrNull!.path), <String>['a.txt']);
      expect(namesIn(third.valueOrNull!.path), <String>['c.txt']);
    });

    test('a cancelled build leaves no library item behind either', () async {
      final result = await repository().build(
        sources: <ZipSource>[pickedFile('a.txt', 'hello')],
        archiveName: 'Archive',
        isCancelled: () => true,
      );

      expect((result.failureOrNull! as ImportFailure).cancelled, isTrue);
      // The record is written only once there is an archive to point at, so a
      // stopped build cannot leave a row in the library that opens nothing.
      expect(documents.store, isEmpty);
      expect(documents.archivedFrom, isEmpty);
    });

    test('opens in the app’s own archive browser', () async {
      // The seam between creating and reading. If these two ever disagree the
      // symptom is a user sending somebody a file their own phone cannot open.
      final result = await repository().build(
        sources: <ZipSource>[
          seedDocument(id: 'doc-a', title: 'Lease'),
          pickedFile('notes.txt', 'plain words'),
        ],
        archiveName: 'Bundle',
      );

      final listing = ZipReader.listSync(result.valueOrNull!.path);
      expect(listing.name, 'Bundle.zip');
      expect(listing.fileCount, 2);
      expect(listing.refusedEntries, 0);
      expect(
        listing.files.map((entry) => entry.path),
        containsAll(<String>['Lease.pdf', 'notes.txt']),
      );
    });

    test('reports both sizes so the user can see whether zipping helped', () async {
      final result = await repository().build(
        sources: <ZipSource>[pickedFile('a.txt', 'x' * 50000)],
        archiveName: 'Archive',
      );

      final outcome = result.valueOrNull!;
      expect(outcome.sourceBytes, 50000);
      expect(outcome.sizeBytes, File(outcome.path).lengthSync());
      expect(outcome.savedFraction, greaterThan(0.5));
    });

    test('a saved archive is never swept, however old it gets', () async {
      // The sweep used to delete finished archives, because that was where they
      // lived. Now it must not touch one: the library says the ZIP is there
      // until the user deletes it, and a cleanup that quietly disagreed would
      // leave a row in the library that opens nothing.
      final first = await repository().build(
        sources: <ZipSource>[pickedFile('a.txt', 'one')],
        archiveName: 'First',
      );

      // Scratch left behind by a build the system killed part way, which is the
      // one thing the sweep is still for.
      final stale = Directory(
        p.join(cache.path, ZipBuilderRepositoryImpl.rootDirectory, 'run_stale'),
      )..createSync(recursive: true);
      File(p.join(stale.path, 'archive.zip.part')).writeAsStringSync('half');

      // Time is moved rather than the directory aged: a `Directory` has no
      // settable modification time, and waiting six hours is not a test.
      final later = DateTime.now().add(ZipBuilderRepositoryImpl.keepFor * 2);

      final second = await repository(now: later).build(
        sources: <ZipSource>[pickedFile('b.txt', 'two')],
        archiveName: 'Second',
      );

      expect(
        File(first.valueOrNull!.path).existsSync(),
        isTrue,
        reason: 'a saved archive outlives every sweep',
      );
      expect(
        stale.existsSync(),
        isFalse,
        reason: 'scratch nobody came back for is not kept for ever',
      );
      expect(File(second.valueOrNull!.path).existsSync(), isTrue);
    });
  });

  group('sharing', () {
    test('offers the archive to the share sheet as a ZIP', () async {
      final share = _RecordingShare();
      final built = await repository(share: share).build(
        sources: <ZipSource>[pickedFile('a.txt', 'hello')],
        archiveName: 'Archive',
      );

      final result = await repository(share: share).share(built.valueOrNull!.path);

      expect(result, isA<Success<void>>());
      expect(share.files.single.path, built.valueOrNull!.path);
      expect(
        share.files.single.mimeType,
        'application/zip',
        reason: 'without a type the apps that filter on one do not appear',
      );
    });

    test('an archive that has gone says so rather than opening an empty sheet', () async {
      final result = await repository().share(p.join(cache.path, 'nope.zip'));

      expect(result.failureOrNull, isA<ExportFailure>());
      expect(result.failureOrNull!.message, contains('no longer on this device'));
    });
  });

  group('CreateZip', () {
    test('substitutes a name when the field was cleared', () async {
      final result = await CreateZip(repository())(
        sources: <ZipSource>[pickedFile('a.txt', 'hello')],
        archiveName: '   ',
      );

      expect(result.valueOrNull!.fileName, '${CreateZip.fallbackName}.zip');
    });

    test('trims a name rather than baking the spaces into the file', () async {
      final result = await CreateZip(repository())(
        sources: <ZipSource>[pickedFile('a.txt', 'hello')],
        archiveName: '  Holiday  ',
      );

      expect(result.valueOrNull!.fileName, 'Holiday.zip');
    });
  });

  group('picking', () {
    test('a dismissed picker is an empty selection, not a failure', () async {
      // No platform under a unit test, so the channel reports nothing picked —
      // which is exactly what backing out of the chooser produces, and must not
      // surface to the user as an error.
      final result = await repository().pickFiles();

      expect(result, isA<Success<ZipSourceSelection>>());
      expect(result.valueOrNull!.sources, isEmpty);
    });
  });
}

/// An exporter that writes a PDF where it says it did.
///
/// [FakeExportRepository] returns a path without creating a file, which is
/// enough for the export tests and not enough here — the builder checks that
/// the PDF exists before putting it in an archive, and a fake that skipped that
/// step would let the check rot.
class _WritingExportRepository implements ExportRepository {
  _WritingExportRepository(this.root);

  final Directory root;

  /// Document ids to fail for, standing in for a damaged page.
  final Set<String> failFor = <String>{};

  int buildCount = 0;

  @override
  FutureResult<String> buildPdf(Document document) async {
    if (failFor.contains(document.id)) {
      return const Failed(
        ExportFailure('The image for page 1 is missing.'),
      );
    }

    buildCount++;

    final relative = p.join('documents', document.id, '${document.id}.pdf');
    final file = File(p.join(root.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('%PDF-1.4 ${document.title}');

    return Success(relative);
  }

  @override
  FutureResult<String> buildDocx(Document document) async =>
      const Failed(ExportFailure('not used here'));

  @override
  FutureResult<void> shareFile(String relativePath, {String? subject}) async =>
      const Success<void>(null);

  @override
  FutureResult<void> shareText(String text, {String? subject}) async =>
      const Success<void>(null);
}

/// Captures what was handed to the share sheet.
class _RecordingShare {
  final List<XFile> files = <XFile>[];
  String? subject;

  Future<ShareResult> call(ShareParams params) async {
    files.addAll(params.files ?? const <XFile>[]);
    subject = params.subject;
    return const ShareResult('ok', ShareResultStatus.success);
  }
}
