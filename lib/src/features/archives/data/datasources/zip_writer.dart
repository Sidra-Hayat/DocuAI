import 'dart:async';
import 'dart:io';
import 'dart:isolate';

// `archive_io` re-exports everything `archive` has plus the file-backed
// encoder, which is the half that matters here — the whole point is to stream
// entries off disk rather than hold an archive in memory.
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

import '../../domain/entities/zip_build.dart';

/// How a write ended.
enum ZipWriteStatus {
  /// The archive is at the target path and is complete.
  written,

  /// The user stopped it. Nothing was left on disk — see [ZipWriter].
  cancelled,

  /// Something went wrong. Nothing was left on disk either.
  failed,
}

/// The result of one write.
class ZipWriteResult {
  const ZipWriteResult({
    required this.status,
    this.path,
    this.sizeBytes = 0,
    this.message,
  });

  final ZipWriteStatus status;

  /// Where the finished archive is. Null unless [status] is
  /// [ZipWriteStatus.written] — there is no half-written archive to point at.
  final String? path;

  final int sizeBytes;

  /// Why it failed, for the user. Null when it did not.
  final String? message;

  bool get isWritten => status == ZipWriteStatus.written;
  bool get isCancelled => status == ZipWriteStatus.cancelled;
}

/// How far a write has got, as plain values that cross an isolate boundary.
class ZipWriteProgress {
  const ZipWriteProgress({
    required this.done,
    required this.total,
    required this.label,
  });

  final int done;
  final int total;
  final String label;
}

/// Writes a standard ZIP, off the main isolate, and can be stopped.
///
/// **Nothing here is DocuAI-specific.** It is handed a list of names and paths
/// that already exist and writes them into an archive; documents have already
/// become PDFs and picked files have already been copied in by the time this
/// runs. That is what keeps the encoder testable with three text files and no
/// Hive, no platform channel and no library.
///
/// **A cancelled build leaves nothing behind, and that is enforced three
/// times.** The bug this is written against happened once already in the import
/// path — a stopped job left a half-written file that opened as a damaged
/// document and was reported as the user's file being broken — so one defence
/// was not considered enough:
///
///  1. *The archive is never written at its final name.* It is built at
///     `<build dir>/archive.zip.part` and moved to the target only after the
///     central directory has been written and the stream closed. A rename
///     within one directory tree is atomic, so the target path either does not
///     exist or holds a complete archive. There is no moment in between.
///  2. *The part file is deleted on the way out.* Cancellation and failure both
///     land in the same `finally`, which closes the encoder and deletes the
///     part file whatever happened.
///  3. *The build directory is the caller's to remove.* It is unique per run,
///     so a run the screen has abandoned cannot have its scratch space deleted
///     out from under it by the next one — the mistake `ImportScratch` warns
///     about — and the repository removes it in its own `finally`.
///
/// **Stopping is cooperative, between entries.** Deflating one file is a single
/// synchronous call that nothing in Dart can interrupt, so the loop yields
/// after each entry, which is when the cancel message is delivered. For a
/// selection of ordinary documents that is a wait of milliseconds. For one very
/// large file it can be a second or two — during which the *user* is not
/// waiting, because the screen lets go of the run the moment Stop is pressed
/// and shows the outcome in that frame. This is the same shape as the archive
/// browser's Stop, and for the same reason.
///
/// Killing the isolate outright would stop it sooner and was rejected: it
/// abandons an open file handle inside this process, and the thing it would
/// save is a wait nobody is sitting through.
///
/// **One known asymmetry with DocuAI's own reader.** `ArchiveLimits.maxRatio`
/// refuses to *list* an entry claiming better than 300:1 compression, because
/// that is what a zip bomb looks like and the reader's job is to survive a file
/// a stranger wrote. Nothing here caps the ratio going the other way, so an
/// archive of pathologically repetitive content — a multi-megabyte log of one
/// repeated line, a sparse CSV of mostly commas — can come out with an entry
/// DocuAI itself would then leave out of the listing.
///
/// It is left alone deliberately, on three counts. The archive is still correct
/// and every other extractor opens it in full, which is what the feature
/// promises. Real content does not reach the threshold: text compresses perhaps
/// ten to one, and what this app mostly archives — PDFs of scanned pages,
/// photographs — is stored rather than deflated and has a ratio of one. And the
/// alternative is either weakening a security control that exists to protect
/// against strangers, or re-encoding an entry after discovering how well it
/// compressed. It is recorded here rather than fixed because the next person to
/// see an entry vanish from a browser should find this paragraph.
class ZipWriter {
  const ZipWriter({this.pollInterval = const Duration(milliseconds: 120)});

  /// How often [write] reads its caller's cancellation flag.
  ///
  /// Injectable so a test can drive cancellation without racing a timer. On a
  /// device it is a tenth of a second, which is far below the point anybody
  /// notices and far above the point polling a boolean costs anything.
  final Duration pollInterval;

  /// Files whose content is already compressed, by extension.
  ///
  /// Deflating a JPEG buys nothing — the entry comes out the same size or a
  /// few bytes larger — and costs the whole file being read, compressed and
  /// buffered. Storing it instead is *faster and smaller*, and the archive is
  /// no less standard for it: "stored" is the other half of the ZIP
  /// specification and every extractor has implemented it since 1989.
  ///
  /// This matters more here than it would elsewhere, because it is what DocuAI
  /// mostly archives. A document goes in as a PDF of JPEG pages, and a picked
  /// file is usually a photograph or a PDF. Deflating those was the difference
  /// between a 55 MB archive taking about a minute and taking a few seconds.
  ///
  /// The Office formats are in the list because a `.docx` is itself a ZIP.
  static const Set<String> alreadyCompressed = <String>{
    'jpg', 'jpeg', 'png', 'webp', 'gif', 'heic', 'heif', 'avif',
    'pdf',
    'zip', '7z', 'rar', 'gz', 'bz2', 'xz',
    'mp3', 'm4a', 'aac', 'ogg', 'opus', 'flac',
    'mp4', 'mov', 'mkv', 'avi', 'webm',
    'docx', 'xlsx', 'pptx', 'odt', 'ods', 'odp',
  };

  /// Above this, an entry is stored rather than deflated whatever it is.
  ///
  /// Not about speed. `ZipEncoder` buffers a deflated entry in memory before
  /// writing it, so compressing a 200 MB log file would mean a 200 MB
  /// allocation on a phone to save some of it. Storing streams straight
  /// through at a constant cost.
  static const int maxDeflateBytes = 64 * 1024 * 1024;

  /// Writes [entries] into an archive at [targetPath].
  ///
  /// [buildDirectory] must be a directory this run owns; the part file is
  /// written there and the caller is expected to remove it afterwards.
  ///
  /// [isCancelled] is polled on this isolate and forwarded to the worker. It is
  /// read at [_pollInterval], which bounds how long after Stop the worker
  /// learns about it — the worker then acts on it at the next entry boundary.
  Future<ZipWriteResult> write({
    required List<ZipEntryPlan> entries,
    required String targetPath,
    required Directory buildDirectory,
    void Function(ZipWriteProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (entries.isEmpty) {
      return const ZipWriteResult(
        status: ZipWriteStatus.failed,
        message: 'There was nothing to put in the archive.',
      );
    }

    // Stop pressed between the caller deciding to build and this being reached.
    // Answered here rather than by spawning an isolate to discover it, which
    // would be a worker started only to be told to stop.
    if (isCancelled?.call() ?? false) {
      return const ZipWriteResult(status: ZipWriteStatus.cancelled);
    }

    final partPath = p.join(buildDirectory.path, 'archive.zip.part');

    final responses = ReceivePort();
    final completer = Completer<ZipWriteResult>();

    SendPort? control;
    Timer? poll;
    Isolate? worker;

    void finish(ZipWriteResult result) {
      if (completer.isCompleted) return;
      poll?.cancel();
      responses.close();
      completer.complete(result);
    }

    responses.listen((Object? message) {
      if (message is! List) {
        // `onExit` and `onError` both report here. A worker that stopped
        // without saying why is a failure, not a silent success — and without
        // this the future would never complete and the screen would sit on a
        // progress bar for ever.
        finish(
          const ZipWriteResult(
            status: ZipWriteStatus.failed,
            message: 'The archive could not be created.',
          ),
        );
        return;
      }

      switch (message.first) {
        case _ready:
          control = message[1] as SendPort;
          // Stop may already have been pressed while the isolate was starting.
          if (isCancelled?.call() ?? false) control?.send(_cancel);
        case _progress:
          onProgress?.call(
            ZipWriteProgress(
              done: message[1] as int,
              total: message[2] as int,
              label: message[3] as String,
            ),
          );
        case _done:
          finish(
            ZipWriteResult(
              status: ZipWriteStatus.written,
              path: message[1] as String,
              sizeBytes: message[2] as int,
            ),
          );
        case _cancelled:
          finish(const ZipWriteResult(status: ZipWriteStatus.cancelled));
        case _failed:
          finish(
            ZipWriteResult(
              status: ZipWriteStatus.failed,
              message: message[1] as String,
            ),
          );
      }
    });

    try {
      worker = await Isolate.spawn(
        _writeIsolate,
        <Object?>[
          responses.sendPort,
          <String>[for (final entry in entries) entry.entryName],
          <String>[for (final entry in entries) entry.sourcePath],
          partPath,
          targetPath,
        ],
        // Both routed to the same port so a worker that dies — an allocation
        // it could not make, a bug — completes the future instead of hanging
        // it. Without these a crash is indistinguishable from a slow archive.
        onError: responses.sendPort,
        onExit: responses.sendPort,
        errorsAreFatal: true,
        debugName: 'zip-writer',
      );
    } catch (error) {
      finish(
        const ZipWriteResult(
          status: ZipWriteStatus.failed,
          message: 'The archive could not be created on this device.',
        ),
      );
    }

    if (isCancelled != null && !completer.isCompleted) {
      poll = Timer.periodic(pollInterval, (timer) {
        if (!isCancelled()) return;
        timer.cancel();
        control?.send(_cancel);
      });
    }

    final result = await completer.future;

    // Belt to the part file's braces. The worker deletes it on every path it
    // controls; this covers the ones it does not — a worker killed by the
    // system, or one that never started.
    _deleteQuietly(partPath);

    // The worker exits on its own after replying. This is only for the case
    // where it never got that far.
    if (result.status != ZipWriteStatus.written) worker?.kill();

    return result;
  }

  static const String _ready = 'ready';
  static const String _progress = 'progress';
  static const String _done = 'done';
  static const String _cancelled = 'cancelled';
  static const String _failed = 'failed';
  static const String _cancel = 'cancel';

  static void _deleteQuietly(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {
      // Best effort. A part file that will not delete is inside a build
      // directory the repository removes wholesale, and inside a cache
      // directory the system reclaims — there is nobody useful to tell.
    }
  }

  /// The worker.
  ///
  /// Top-level-ish by necessity: `Isolate.spawn` needs a function with no
  /// captured state, which is also what keeps the rules above honest — this
  /// closes over nothing and can only touch the paths it was handed.
  static Future<void> _writeIsolate(List<Object?> request) async {
    final reply = request[0] as SendPort;
    final names = (request[1] as List).cast<String>();
    final paths = (request[2] as List).cast<String>();
    final partPath = request[3] as String;
    final targetPath = request[4] as String;

    var cancelled = false;

    final control = ReceivePort();
    control.listen((Object? message) {
      if (message == _cancel) cancelled = true;
    });

    reply.send(<Object?>[_ready, control.sendPort]);

    final encoder = ZipFileEncoder();
    var opened = false;

    try {
      encoder.create(partPath);
      opened = true;

      for (var index = 0; index < names.length; index++) {
        // Checked before the entry rather than after, so a build stopped at
        // the very first file writes nothing at all.
        if (cancelled) break;

        reply.send(<Object?>[_progress, index, names.length, names[index]]);

        final file = File(paths[index]);
        if (!file.existsSync()) {
          // Not a failure of the archive. The planner checked every file
          // existed a moment ago; one that has gone since is a cache the
          // system reclaimed mid-build, and the honest thing is to leave it
          // out rather than abandon everything already written.
          continue;
        }

        _addEntry(encoder, file, names[index]);

        // The yield that makes Stop possible. Without it the control port
        // never gets a turn and the loop runs to the end whatever was pressed.
        await Future<void>.delayed(Duration.zero);
      }

      if (cancelled) {
        // Closed before deleting: the encoder holds the output stream open,
        // and on Windows a file with an open handle will not delete. Android
        // is more forgiving, and this still runs in tests on a desktop.
        encoder.closeSync();
        opened = false;
        _deleteQuietly(partPath);
        reply.send(const <Object?>[_cancelled]);
        return;
      }

      // The central directory is written here. Everything before this point is
      // a file that no extractor would recognise as an archive, which is
      // precisely why the target name is only claimed afterwards.
      encoder.closeSync();
      opened = false;

      final part = File(partPath);
      final size = part.lengthSync();

      // The one moment the archive becomes real. Both paths are inside the
      // app's cache, so this is a rename within one file system: it either
      // happens or it does not, and there is no state where the target holds
      // half an archive.
      final target = File(targetPath);
      if (target.existsSync()) target.deleteSync();
      part.renameSync(targetPath);

      reply.send(<Object?>[_done, targetPath, size]);
    } catch (error) {
      if (opened) {
        try {
          encoder.closeSync();
        } catch (_) {
          // Already broken; the delete below is what matters.
        }
      }
      _deleteQuietly(partPath);

      reply.send(<Object?>[
        _failed,
        _messageFor(error),
      ]);
    } finally {
      control.close();
    }
  }

  /// Adds one file, choosing whether to compress it.
  ///
  /// Built by hand rather than through `ZipFileEncoder.addFile` because that
  /// one always deflates. Setting [CompressionType.none] is what routes an
  /// already-compressed file down the encoder's streaming path instead of
  /// through a full in-memory buffer.
  static void _addEntry(ZipFileEncoder encoder, File file, String entryName) {
    final stream = InputFileStream(file.path);
    final entry = ArchiveFile.stream(entryName, stream);

    // Kept from the file so an extractor shows the date the user recognises
    // rather than the moment the archive happened to be built.
    entry.lastModTime = file.lastModifiedSync().millisecondsSinceEpoch ~/ 1000;

    if (_shouldStore(file, entryName)) {
      entry.compression = CompressionType.none;
    } else {
      entry.compression = CompressionType.deflate;
      entry.compressionLevel = DeflateLevel.defaultCompression;
    }

    // `add` closes the entry's content when it is finished with it, which is
    // what closes `stream`. Closing it here as well would be a double close.
    encoder.addArchiveFile(entry);
  }

  static bool _shouldStore(File file, String entryName) {
    final extension = p
        .extension(entryName)
        .replaceFirst('.', '')
        .toLowerCase();

    if (alreadyCompressed.contains(extension)) return true;

    try {
      return file.lengthSync() > maxDeflateBytes;
    } catch (_) {
      // Unreadable length is not a reason to fail; storing is the safe answer
      // because it cannot allocate.
      return true;
    }
  }

  static String _messageFor(Object error) {
    if (error is FileSystemException) {
      final code = error.osError?.errorCode;
      // ENOSPC on Linux and Android. The one failure with a specific, useful
      // thing for the user to do about it.
      if (code == 28) {
        return 'There is not enough free space on this phone to create that '
            'archive. Free some space and try again.';
      }
      return 'The archive could not be written to this phone’s storage.';
    }
    return 'The archive could not be created. If it is very large, try '
        'creating it with fewer files.';
  }
}
