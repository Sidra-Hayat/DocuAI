import 'dart:io';

import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/features/archives/domain/entities/archive_entry.dart';
import 'package:docuai/src/features/archives/domain/repositories/archive_repository.dart';
import 'package:docuai/src/features/archives/domain/usecases/import_archive_entries.dart';
import 'package:docuai/src/features/import/domain/repositories/file_import_repository.dart';
import 'package:docuai/src/features/import/domain/usecases/import_file.dart';
import 'package:docuai/src/features/pdf_tools/domain/entities/pdf_tool_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';

/// Importing a selection out of an archive.
///
/// The interesting behaviour is not that it works — it delegates to the file
/// importer, which has its own tests — but what it does when a long run goes
/// wrong halfway: what it counts, what it keeps, and what happens when the user
/// presses Stop.
void main() {
  late Directory workspace;
  late FakeDocumentRepository documents;
  late _FakeArchives archives;
  late ImportArchiveEntries importEntries;

  ArchiveEntry entry(String path, [ArchiveEntryKind kind = ArchiveEntryKind.text]) =>
      ArchiveEntry(path: path, kind: kind, sizeBytes: 16, compressedBytes: 8);

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('docuai_archive_import');
    documents = FakeDocumentRepository();
    archives = _FakeArchives(workspace);

    importEntries = ImportArchiveEntries(
      archives: archives,
      // The real use case over fake storage: "through the existing pipeline" is
      // the claim being tested, so the pipeline is not the thing faked.
      importer: ImportFileAsDocument(
        importer: const _TextImporter(),
        documents: documents,
        search: FakeSearchRepository(),
      ),
    );
  });

  tearDown(() async {
    documents.dispose();
    if (workspace.existsSync()) await workspace.delete(recursive: true);
  });

  test('makes one document per file, named after the entry', () async {
    final result = await importEntries(
      archivePath: 'archive.zip',
      entries: <ArchiveEntry>[entry('a/first.txt'), entry('b/second.md')],
    );

    final outcome = (result as Success<ArchiveImportOutcome>).value;
    expect(outcome.importedCount, 2);
    expect(outcome.failed, isEmpty);
    expect(
      documents.store.values.map((document) => document.title),
      containsAll(<String>['first', 'second']),
    );
  });

  test('reports progress by file, so a long run is not a blank wait', () async {
    final seen = <String>[];

    await importEntries(
      archivePath: 'archive.zip',
      entries: <ArchiveEntry>[entry('one.txt'), entry('two.txt')],
      onProgress: (progress) =>
          seen.add('${progress.done}/${progress.total} ${progress.label}'),
    );

    expect(seen.first, '0/2 one.txt');
    expect(seen, contains('1/2 two.txt'));
    // Finishes at the total, so a bar that reached 90% does not sit there.
    expect(seen.last, '2/2 ');
  });

  test('stopping keeps what was already imported', () async {
    final result = await importEntries(
      archivePath: 'archive.zip',
      entries: <ArchiveEntry>[
        entry('one.txt'),
        entry('two.txt'),
        entry('three.txt'),
      ],
      // Stop pressed as soon as the first document exists. Polled between
      // files, which is the only place it can be — a file already being
      // rasterised is inside an isolate nothing here has a handle on.
      isCancelled: () => documents.store.isNotEmpty,
    );

    final outcome = (result as Success<ArchiveImportOutcome>).value;
    expect(outcome.cancelled, isTrue);
    expect(outcome.importedCount, 1);
    // Not rolled back. Stopping the queue is not undoing the work.
    expect(documents.store, hasLength(1));
  });

  test('a file that fails is named, and the rest still arrive', () async {
    archives.failFor = 'b/broken.txt';

    final result = await importEntries(
      archivePath: 'archive.zip',
      entries: <ArchiveEntry>[
        entry('a/good.txt'),
        entry('b/broken.txt'),
        entry('c/alsogood.txt'),
      ],
    );

    final outcome = (result as Success<ArchiveImportOutcome>).value;
    expect(outcome.importedCount, 2);
    expect(outcome.failed, <String>['broken.txt']);
  });

  test('a file it cannot import is reported, not silently dropped', () async {
    // The bug this replaced: unsupported entries were filtered out *before*
    // the loop, so seventeen selected files could produce four documents and
    // no account at all of the other thirteen.
    final result = await importEntries(
      archivePath: 'archive.zip',
      entries: <ArchiveEntry>[
        entry('nested.zip', ArchiveEntryKind.archive),
        entry('clip.mp4', ArchiveEntryKind.other),
        entry('note.txt'),
      ],
    );

    final outcome = (result as Success<ArchiveImportOutcome>).value;

    // Three selected, three accounted for.
    expect(outcome.entries, hasLength(3));
    expect(outcome.importedCount, 1);
    expect(outcome.withStatus(ArchiveImportStatus.unsupported), hasLength(2));
    expect(documents.store, hasLength(1));

    // And each one says why, in words meant for a person.
    final nested = outcome.entries.firstWhere((e) => e.name == 'nested.zip');
    expect(nested.reason, contains('archive inside an archive'));

    final clip = outcome.entries.firstWhere((e) => e.name == 'clip.mp4');
    expect(clip.reason, contains('PDFs, Word files, text files and pictures'));
  });

  test('a selection with no files at all is refused', () async {
    final result = await importEntries(
      archivePath: 'archive.zip',
      entries: <ArchiveEntry>[entry('a', ArchiveEntryKind.folder)],
    );

    expect(result, isA<Failed<ArchiveImportOutcome>>());
    expect(documents.store, isEmpty);
  });

  test('folders in the selection are skipped rather than attempted', () async {
    final result = await importEntries(
      archivePath: 'archive.zip',
      entries: <ArchiveEntry>[
        entry('a', ArchiveEntryKind.folder),
        entry('a/inside.txt'),
      ],
    );

    expect((result as Success<ArchiveImportOutcome>).value.importedCount, 1);
    expect(archives.extracted, <String>['a/inside.txt']);
  });

  test('when every file fails, each one still says why', () async {
    archives.failEverything = true;

    final result = await importEntries(
      archivePath: 'archive.zip',
      entries: <ArchiveEntry>[entry('one.txt'), entry('two.txt')],
    );

    final outcome = (result as Success<ArchiveImportOutcome>).value;

    expect(outcome.importedCount, 0);
    expect(outcome.isComplete, isFalse);
    expect(outcome.withStatus(ArchiveImportStatus.unreadable), hasLength(2));
    // The repository's own message reaches the report rather than being
    // flattened into "could not be read".
    expect(outcome.entries.first.reason, contains('damaged'));
    expect(documents.store, isEmpty);
  });

  test('stopping accounts for the files it never reached', () async {
    final result = await importEntries(
      archivePath: 'archive.zip',
      entries: <ArchiveEntry>[
        entry('one.txt'),
        entry('two.txt'),
        entry('three.txt'),
      ],
      isCancelled: () => documents.store.isNotEmpty,
    );

    final outcome = (result as Success<ArchiveImportOutcome>).value;

    // Three selected, three reported: one in, two named as untouched. The
    // numbers add up, which is what the report is for.
    expect(outcome.entries, hasLength(3));
    expect(outcome.importedCount, 1);
    expect(outcome.withStatus(ArchiveImportStatus.stopped), hasLength(2));
    expect(
      outcome.withStatus(ArchiveImportStatus.stopped).first.reason,
      contains('stopped the import'),
    );
  });

  test('a cancelled conversion is stopped, not called a broken file', () async {
    // A PDF abandoned between pages comes back as a cancelled ImportFailure.
    // Reporting that as "damaged" would blame the user's file for their own
    // tap on Stop.
    importEntries = ImportArchiveEntries(
      archives: archives,
      importer: ImportFileAsDocument(
        importer: const _CancelledImporter(),
        documents: documents,
        search: FakeSearchRepository(),
      ),
    );

    final result = await importEntries(
      archivePath: 'archive.zip',
      entries: <ArchiveEntry>[entry('big.pdf', ArchiveEntryKind.pdf)],
    );

    final outcome = (result as Success<ArchiveImportOutcome>).value;
    expect(outcome.withStatus(ArchiveImportStatus.stopped), hasLength(1));
    expect(outcome.withStatus(ArchiveImportStatus.unreadable), isEmpty);
  });
}

/// Writes a real file per entry, because the importer opens what it is given.
class _FakeArchives implements ArchiveRepository {
  _FakeArchives(this._workspace);

  final Directory _workspace;
  final List<String> extracted = <String>[];

  String? failFor;
  bool failEverything = false;

  @override
  FutureResult<ArchiveListing> open(String archivePath) async =>
      const Failed(ImportFailure('not used'));

  @override
  FutureResult<String> extract({
    required String archivePath,
    required ArchiveEntry entry,
  }) async {
    if (failEverything || entry.path == failFor) {
      return const Failed(ImportFailure('That entry is damaged.'));
    }

    extracted.add(entry.path);
    final file = File(p.join(_workspace.path, entry.name))
      ..writeAsStringSync('contents');
    return Success(file.path);
  }
}

/// Every file reads as text, so no renderer or image codec is involved.
class _TextImporter implements FileImportRepository {
  const _TextImporter();

  @override
  FutureResult<ImportedFile> pickFile() async =>
      const Failed(ImportFailure('not used'));

  @override
  FutureResult<ImportedFile> readFile(
    String path, {
    bool Function()? isCancelled,
  }) async => Success(
    ImportedFile(
      name: p.basenameWithoutExtension(path),
      kind: ImportedFileKind.text,
      text: 'contents',
    ),
  );
}

/// A conversion that was called off part way, the way an abandoned PDF is.
class _CancelledImporter implements FileImportRepository {
  const _CancelledImporter();

  @override
  FutureResult<ImportedFile> pickFile() async =>
      const Failed(ImportFailure('not used'));

  @override
  FutureResult<ImportedFile> readFile(
    String path, {
    bool Function()? isCancelled,
  }) async => const Failed(ImportFailure('Import stopped.', cancelled: true));
}

/// Kept honest: `ToolProgress` is the PDF tools' type, reused here on purpose.
/// If it ever stops being importable from this feature, this fails to compile
/// before anything else does.
// ignore: unused_element
ToolProgress _progressTypeIsShared() => const ToolProgress(done: 0, total: 0);
