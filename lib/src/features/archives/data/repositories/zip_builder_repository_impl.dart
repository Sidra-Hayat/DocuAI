import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/storage/storage_paths.dart';
import '../../../../core/utils/clock.dart';
import '../../../documents/domain/entities/document.dart';
import '../../../documents/domain/repositories/document_repository.dart';
import '../../../export/domain/repositories/export_repository.dart';
import '../../../pdf_tools/domain/entities/pdf_tool_models.dart';
import '../../domain/entities/zip_build.dart';
import '../../domain/repositories/zip_builder_repository.dart';
import '../datasources/picked_files_channel.dart';
import '../datasources/zip_writer.dart';

/// How the share sheet is opened. Injected so tests need no platform.
typedef ZipShareLauncher = Future<ShareResult> Function(ShareParams params);

Future<ShareResult> _launchSystemShare(ShareParams params) =>
    SharePlus.instance.share(params);

/// Builds archives in the app's cache and hands them to the share sheet.
///
/// **Where the archive goes, and why it goes there.** A finished archive is
/// kept. It is built in the app's cache and then *moved* into the library, into
/// the document folder of the record that describes it — the same private
/// storage every scanned page and exported PDF already lives in. Nothing is
/// written to a folder the user chose, nothing asks for a storage permission,
/// and `MANAGE_EXTERNAL_STORAGE` does not appear anywhere in this app.
///
/// It used to stop at the cache, on the reasoning that an archive is a thing
/// being *sent* rather than a thing being kept. That was wrong in the way that
/// only shows up a day later: the user shares the ZIP, the chat fails to send,
/// they come back — and Android has reclaimed the only copy, with nothing in
/// the app that ever admitted it was temporary. Keeping it makes "share it
/// again" an ordinary thing to do, and makes deleting it the user's decision
/// rather than the system's.
///
/// The cache is still where it is *made*. Building in a scratch directory is
/// what lets a stopped build leave nothing behind — see [ZipWriter] — and the
/// move into the library is the last step, taken only once there is a complete
/// archive to move.
///
/// **How it is handed over.** Through `share_plus`, which is the mechanism the
/// rest of the app already shares with — the document export has used it since
/// Phase 5. It mints a `content://` URI through a `FileProvider` and grants it
/// to the app the user picks, which is the same contract DocuAI's own provider
/// offers `ExternalOpener`. Writing a second, native ACTION_SEND path against
/// `com.sidrahayat.docuai.fileprovider` would duplicate a working, tested
/// mechanism to arrive at the same place; the one thing it would change is that
/// the app would then have two ways to share a file that could drift apart.
///
/// **One directory per build.** Each run gets `docuai_zip/<run>/`, holding its
/// part file and then its finished archive. Two runs cannot collide, a run the
/// screen has abandoned cannot have its working files deleted by the next one
/// — the mistake `ImportScratch` documents — and a build that ends badly is
/// cleaned up by removing one directory rather than by remembering which files
/// it made.
class ZipBuilderRepositoryImpl implements ZipBuilderRepository {
  ZipBuilderRepositoryImpl({
    required DocumentRepository documents,
    required ExportRepository export,
    required StoragePaths paths,
    PickedFilesChannel picker = const PickedFilesChannel(),
    ZipWriter writer = const ZipWriter(),
    ZipBuildLimits limits = const ZipBuildLimits(),
    ZipShareLauncher shareLauncher = _launchSystemShare,
    Clock clock = systemClock,
    Future<Directory> Function()? temporaryDirectory,
  }) : _documents = documents,
       _export = export,
       _paths = paths,
       _picker = picker,
       _writer = writer,
       _limits = limits,
       _share = shareLauncher,
       _now = clock,
       _tempDir = temporaryDirectory;

  final DocumentRepository _documents;
  final ExportRepository _export;
  final StoragePaths _paths;
  final PickedFilesChannel _picker;
  final ZipWriter _writer;
  final ZipBuildLimits _limits;
  final ZipShareLauncher _share;

  /// Only ever used to decide what is old enough to sweep, and to name a run
  /// directory. Injected so a test can move time forward rather than wait.
  final Clock _now;

  final Future<Directory> Function()? _tempDir;

  /// Root for everything this repository writes, inside the app's cache.
  static const String rootDirectory = 'docuai_zip';

  /// How long an abandoned scratch directory is left before it is swept.
  ///
  /// Nothing the user owns is in here any more — a finished archive is moved
  /// into the library, and a stopped one is deleted on the way out. What this
  /// catches is the case neither of those can: a process killed mid-build,
  /// which leaves a part file that nothing will ever come back for.
  ///
  /// Six hours, generously longer than any build, so a sweep can never delete
  /// the scratch space of a build still running.
  static const Duration keepFor = Duration(hours: 6);

  /// Distinguishes two builds started in the same microsecond.
  static int _runCounter = 0;

  @override
  FutureResult<ZipSourceSelection> pickFiles() async {
    try {
      final picked = await _picker.pick();

      return Success(
        ZipSourceSelection(
          sources: <ZipSource>[
            for (final file in picked.files)
              ZipSource.file(
                path: file.path,
                name: file.name,
                sizeBytes: file.sizeBytes,
              ),
          ],
          rejected: picked.rejected,
        ),
      );
    } catch (error, stackTrace) {
      return Failed(
        ImportFailure(
          'Those files could not be opened.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  FutureResult<ZipBuildOutcome> build({
    required List<ZipSource> sources,
    required String archiveName,
    ToolProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (sources.isEmpty) {
      return const Failed(
        ValidationFailure('Choose at least one document or file to archive.'),
      );
    }

    if (sources.length > _limits.maxEntries) {
      return Failed(
        ValidationFailure(
          'An archive can hold up to ${_limits.maxEntries} files. Remove some '
          'and try again.',
        ),
      );
    }

    Directory? run;

    try {
      final root = await _root();
      await _sweep(root);

      run = await _newRunDirectory(root);

      final skipped = <ZipSkippedSource>[];
      final plans = <ZipEntryPlan>[];
      var sourceBytes = 0;

      // ---- Resolving ------------------------------------------------------
      //
      // Every source becomes a file on disk before anything is compressed. A
      // document has to be rendered, which is the slow half of the job for a
      // library selection, so it is reported as progress in its own right
      // rather than left as a pause before the bar starts moving.

      final names = uniqueEntryNames(
        sources.map((source) => source.preferredEntryName),
      );

      for (var index = 0; index < sources.length; index++) {
        if (isCancelled?.call() ?? false) return _cancelled();

        final source = sources[index];

        onProgress?.call(
          ToolProgress(
            done: index,
            // Resolving is the first half and writing is the second, so the
            // bar is scaled over both. A run that reached 100% and then sat
            // there compressing would be a bar that lies twice.
            total: sources.length * 2,
            label: source.name,
          ),
        );

        final resolved = source.isDocument
            ? await _resolveDocument(source)
            : _resolveFile(source);

        switch (resolved) {
          case _ResolvedSkip(:final reason):
            skipped.add(ZipSkippedSource(name: source.name, reason: reason));
          case _ResolvedPath(:final path):
            final bytes = File(path).lengthSync();

            if (sourceBytes + bytes > _limits.maxTotalBytes) {
              return Failed(
                ValidationFailure(
                  'That selection adds up to more than '
                  '${_limits.maxTotalBytes ~/ (1024 * 1024 * 1024)} GB, which '
                  'is more than DocuAI will put in one archive.',
                ),
              );
            }

            sourceBytes += bytes;
            plans.add(
              ZipEntryPlan(
                entryName: names[index],
                sourcePath: path,
                sourceId: source.id,
              ),
            );
        }
      }

      if (plans.isEmpty) {
        return Failed(
          ExportFailure(
            skipped.length == 1
                ? skipped.first.reason
                : 'None of those could be put into an archive.',
          ),
        );
      }

      if (isCancelled?.call() ?? false) return _cancelled();

      // ---- Writing --------------------------------------------------------
      //
      // Still built in a scratch directory, and still under a temporary name
      // inside it. Persisting the archive did not change where it is *made*:
      // the guarantee that a stopped build leaves nothing behind rests on the
      // finished name being claimed only by a finished file, and on the whole
      // run directory being removable in one step. It becomes a library item
      // afterwards, once there is something worth keeping.

      final fileName = await _freeArchiveName(archiveName);
      final targetPath = p.join(run.path, fileName);

      final written = await _writer.write(
        entries: plans,
        targetPath: targetPath,
        buildDirectory: run,
        isCancelled: isCancelled,
        onProgress: (progress) => onProgress?.call(
          ToolProgress(
            // Offset past the resolving half, so the bar carries on from where
            // it was rather than restarting.
            done: sources.length + progress.done,
            total: sources.length + progress.total,
            label: progress.label,
          ),
        ),
      );

      switch (written.status) {
        case ZipWriteStatus.cancelled:
          return _cancelled();
        case ZipWriteStatus.failed:
          return Failed(
            ExportFailure(
              written.message ?? 'The archive could not be created.',
            ),
          );
        case ZipWriteStatus.written:
          break;
      }

      onProgress?.call(
        ToolProgress(
          done: sources.length * 2,
          total: sources.length * 2,
          label: 'Saving',
        ),
      );

      // ---- Keeping it -----------------------------------------------------
      //
      // The archive moves out of the cache and into the library. `createArchive`
      // takes ownership of the file — it is renamed into the new document's own
      // folder rather than copied, so there is never a second copy of something
      // that may be hundreds of megabytes.

      final saved = await _documents.createArchive(
        // The library shows the file name, extension and all. A ZIP is a thing
        // with a name rather than a document with a title, and "DocuAI
        // 2026-08-21" in a list beside "DocuAI 2026-08-21.zip" in a share sheet
        // would be two names for one object.
        title: fileName,
        fileName: fileName,
        sourceZipPath: written.path!,
      );

      switch (saved) {
        case Failed(:final failure):
          return Failed(failure);
        case Success(value: final document):
          return Success(
            ZipBuildOutcome(
              document: document,
              path: _paths.absolutePath(document.archivePath!),
              fileName: fileName,
              entryCount: plans.length,
              sizeBytes: written.sizeBytes,
              sourceBytes: sourceBytes,
              skipped: skipped,
            ),
          );
      }
    } catch (error, stackTrace) {
      return Failed(
        ExportFailure(
          'That archive could not be created. If it holds very large files, '
          'try creating it with fewer of them.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    } finally {
      // Reached on *every* path now, success included — the archive has been
      // moved into the library by then, so the scratch directory is empty of
      // anything worth keeping. This is the guarantee that a stopped build
      // leaves nothing behind: the part file, and the directory that held it,
      // both go, whatever happened.
      if (run != null) await _deleteQuietly(run);
    }
  }

  @override
  FutureResult<void> share(String archivePath) async {
    final file = File(archivePath);

    if (!file.existsSync()) {
      return const Failed(
        ExportFailure(
          'That archive is no longer on this device. Create it again.',
        ),
      );
    }

    try {
      final result = await _share(
        ShareParams(
          files: <XFile>[
            // Named explicitly. Without the type the sheet offers the file as
            // `application/octet-stream`, and the apps that filter on type —
            // which is most of them — do not appear.
            XFile(archivePath, mimeType: 'application/zip'),
          ],
          subject: p.basenameWithoutExtension(archivePath),
        ),
      );

      // Dismissing the sheet is a success, for the reason the document export
      // gives: Android reports "dismissed" both for a user who changed their
      // mind and for a share it declined to describe, so treating it as an
      // error would show a failure after a share that worked.
      return switch (result.status) {
        ShareResultStatus.unavailable => const Failed(
          ExportFailure('No app on this device can receive the archive.'),
        ),
        _ => const Success<void>(null),
      };
    } catch (error, stackTrace) {
      return Failed(
        ExportFailure(
          'The archive could not be shared.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  // ---- Resolving one source -------------------------------------------------

  /// Renders a document to a PDF and returns where it landed.
  ///
  /// Reuses the export already on the document when there is one, exactly as
  /// `ShareDocument` does: composing a PDF re-encodes every page image, and a
  /// document whose pages have not changed does not need it again. For an
  /// archive of a dozen documents that is the difference between a few seconds
  /// and a minute.
  ///
  /// **The path is cached back onto the document, but `updatedAt` is not
  /// touched** — which is where this deliberately parts company with
  /// `ExportDocumentAsPdf`. That use case moves the timestamp because exporting
  /// is something the user did *to* that document. Archiving is not: bumping
  /// the timestamp on ten documents would reorder the whole library, newest
  /// first, as a side effect of sending a ZIP. The PDF is a derived artefact
  /// and recording where it went is not a change to the document.
  Future<_Resolved> _resolveDocument(ZipSource source) async {
    final loaded = await _documents.getDocument(source.documentId!);

    final Document document;
    switch (loaded) {
      case Failed():
        return const _ResolvedSkip(
          'That document is no longer in your library.',
        );
      case Success(:final value):
        document = value;
    }

    // A library item that is itself an archive goes in as the file it already
    // is. Checked before the page test below, which would otherwise refuse it
    // for having no pages — true, and beside the point.
    final archive = document.archivePath;
    if (archive != null) {
      final absolute = _paths.absolutePath(archive);
      if (!File(absolute).existsSync()) {
        return const _ResolvedSkip(
          'That archive is no longer on this device.',
        );
      }
      return _ResolvedPath(absolute);
    }

    if (!document.hasPages) {
      return const _ResolvedSkip('That document has nothing in it yet.');
    }

    final existing = document.pdfPath;
    if (existing != null) {
      final absolute = _paths.absolutePath(existing);
      if (File(absolute).existsSync()) return _ResolvedPath(absolute);
    }

    final built = await _export.buildPdf(document);
    switch (built) {
      case Failed(:final failure):
        return _ResolvedSkip(failure.message);
      case Success(value: final relative):
        final absolute = _paths.absolutePath(relative);
        if (!File(absolute).existsSync()) {
          return const _ResolvedSkip(
            'That document could not be turned into a PDF.',
          );
        }

        // Best effort, and deliberately not checked. The archive has its PDF
        // either way; failing the whole entry because a cache write did not
        // stick would trade something that worked for something that did not.
        await _documents.saveDocument(document.copyWith(pdfPath: relative));

        return _ResolvedPath(absolute);
    }
  }

  _Resolved _resolveFile(ZipSource source) {
    final path = source.path!;
    if (!File(path).existsSync()) {
      return const _ResolvedSkip(
        'That file is no longer on this device. Choose it again.',
      );
    }
    return _ResolvedPath(path);
  }

  /// A `.zip` name no archive in the library is already using.
  ///
  /// Two archives made on the same day both want to be called
  /// "DocuAI 2026-08-21.zip". They no longer live in separate throwaway
  /// directories where that was harmless — they sit in one library, where two
  /// rows with the same name are two things the user cannot tell apart, and the
  /// second would be the one they never find again.
  ///
  /// Numbered with the same helper that numbers entries *inside* an archive, so
  /// the library reads the way the archive does: "(2)", "(3)", and so on.
  ///
  /// Checked against the store rather than against the file system. The file
  /// lands in a folder of its own named by a fresh uuid, so nothing on disk can
  /// collide; what has to stay unique is the name a person reads.
  Future<String> _freeArchiveName(String requested) async {
    final base = '${sanitiseEntryName(requested)}.zip';

    final existing = await _documents.getDocuments();
    if (existing is! Success<List<Document>>) return base;

    final taken = <String>{
      for (final document in existing.value)
        if (document.isArchive) document.title.toLowerCase(),
    };

    return uniqueNameAgainst(base, taken);
  }

  Failed<ZipBuildOutcome> _cancelled() => const Failed<ZipBuildOutcome>(
    ImportFailure('The archive was not created.', cancelled: true),
  );

  // ---- The cache directory --------------------------------------------------

  Future<Directory> _root() async {
    final temp = await (_tempDir ?? getTemporaryDirectory)();
    final root = Directory(p.join(temp.path, rootDirectory));
    if (!root.existsSync()) await root.create(recursive: true);
    return root;
  }

  Future<Directory> _newRunDirectory(Directory root) async {
    final run = Directory(
      p.join(
        root.path,
        'run_${_now().microsecondsSinceEpoch}_${_runCounter++}',
      ),
    );
    await run.create(recursive: true);
    return run;
  }

  /// Removes scratch directories left by builds that never finished.
  ///
  /// The backstop for the one case the writer cannot cover: a process killed
  /// mid-build leaves a run directory with a part file in it, and nothing else
  /// will ever come back for it. Best effort throughout — a directory that will
  /// not delete is one the next build will offer to delete again, which beats
  /// an exception taking down a build that was fine.
  Future<void> _sweep(Directory root) async {
    try {
      final cutoff = _now().subtract(keepFor);

      for (final entity in root.listSync()) {
        try {
          if (entity.statSync().modified.isBefore(cutoff)) {
            await _deleteQuietly(entity);
          }
        } catch (_) {
          // One unreadable entry must not stop the rest being swept.
        }
      }
    } catch (_) {
      // Nothing to do, and nobody to tell.
    }
  }

  Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      if (entity.existsSync()) await entity.delete(recursive: true);
    } catch (_) {
      // Cache. The system reclaims what this could not.
    }
  }
}

/// What resolving one source produced: a file to archive, or a reason not to.
sealed class _Resolved {
  const _Resolved();
}

final class _ResolvedPath extends _Resolved {
  const _ResolvedPath(this.path);
  final String path;
}

final class _ResolvedSkip extends _Resolved {
  const _ResolvedSkip(this.reason);
  final String reason;
}
