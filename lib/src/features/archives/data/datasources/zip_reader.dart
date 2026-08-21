import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../../domain/entities/archive_entry.dart';
import '../../domain/entities/archive_limits.dart';

/// Something an archive did that means it cannot be shown.
///
/// Deliberately not a [Failure]: this is the data layer, and the repository
/// above is what turns a thrown reason into the failure the domain sees. The
/// message is written for the user, because the repository has nothing to add
/// to "this archive is damaged" that this class does not already know.
class ArchiveReadException implements Exception {
  const ArchiveReadException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'ArchiveReadException: $message';
}

/// Reads a ZIP without unpacking it.
///
/// **Lazily, and that is the whole design.** A ZIP keeps a central directory at
/// its end listing every entry with its name, its compressed size and its real
/// size. Reading that is enough to draw the entire browser — names, folders,
/// icons, sizes — and it costs one seek and a few kilobytes whatever the
/// archive weighs. Nothing is decompressed until a specific entry is tapped,
/// and then only that entry.
///
/// The alternative — `extractArchiveToDisk`, which is what the `archive`
/// package makes easiest — would write a gigabyte to the cache so the user
/// could look at a list of file names, and would do it before anything had
/// checked whether the archive was hostile.
///
/// **Nothing here trusts the archive.** Every name in a ZIP is written by
/// whoever made it, and the classic attack (Zip Slip) is an entry called
/// `../../databases/documents.hive` that a naive extractor writes exactly where
/// it says. [safeEntryPath] is the single gate every entry passes through, and
/// [extractEntry] additionally reduces the name to its last segment before
/// joining it to a directory this app chose — so an escape would have to get
/// past two independent defences that fail in different directions.
class ZipReader {
  const ZipReader({this.limits = const ArchiveLimits()});

  final ArchiveLimits limits;

  /// Lists what is inside [archivePath].
  ///
  /// Runs on another isolate. Parsing four thousand directory entries is not
  /// slow, but it is not free either, and it happens while the user is looking
  /// at a screen that has just opened — the one moment a dropped frame is
  /// certain to be noticed.
  Future<ArchiveListing> list(String archivePath) {
    final limits = this.limits;
    return Isolate.run(() => listSync(archivePath, limits: limits));
  }

  /// Extracts one entry into [into] and returns the path written.
  ///
  /// [entryPath] must be a path this reader itself produced. It is looked up in
  /// the archive rather than trusted as a location, and what is written is
  /// named from its last segment only.
  Future<String> extractEntry({
    required String archivePath,
    required String entryPath,
    required Directory into,
    String prefix = '',
  }) {
    final limits = this.limits;
    final target = into.path;
    return Isolate.run(
      () => extractEntrySync(
        archivePath: archivePath,
        entryPath: entryPath,
        intoPath: target,
        prefix: prefix,
        limits: limits,
      ),
    );
  }

  // ---- The isolate bodies, and the testable surface ------------------------
  //
  // Static and synchronous so that a test can call them directly without
  // spawning anything, and so that `Isolate.run` above closes over nothing but
  // plain values.

  /// Reads the central directory and builds the listing.
  static ArchiveListing listSync(
    String archivePath, {
    ArchiveLimits limits = const ArchiveLimits(),
  }) {
    final file = File(archivePath);
    if (!file.existsSync()) {
      throw const ArchiveReadException(
        'That archive is no longer on the device.',
      );
    }

    final archiveBytes = file.lengthSync();
    if (archiveBytes == 0) {
      throw const ArchiveReadException('That archive is empty.');
    }

    const damaged =
        'That archive could not be opened. It may be damaged, only partly '
        'downloaded, or locked with a password.';

    // Checked before decoding, because the decoder will not do it.
    //
    // `ZipDecoder` is forgiving to a fault: handed a text file, or a ZIP whose
    // download stopped half way, it does not throw — it returns an archive with
    // no entries in it. That is indistinguishable from a genuinely empty
    // archive, and the difference is the whole of what the user needs told:
    // "there is nothing in this" and "this file is broken" are different
    // problems with different next steps.
    //
    // A ZIP's first four bytes say which it is. Every archive with content
    // starts with a local file header, `PK\x03\x04`; an empty one is a lone
    // end-of-central-directory record, `PK\x05\x06`. Anything else is not a ZIP
    // this app should be reading.
    final header = _readHeader(file);
    if (header == null || header[0] != 0x50 || header[1] != 0x4B) {
      throw const ArchiveReadException(damaged);
    }
    final isEmptyArchive = header[2] == 0x05 && header[3] == 0x06;

    final (input, archive) = _open(archivePath, damaged);

    try {
      // No entries and no claim to be empty: the directory at the end of the
      // file is missing or unreadable, which is a truncated download.
      if (archive.files.isEmpty && !isEmptyArchive) {
        throw const ArchiveReadException(damaged);
      }

      // Counted before anything is built. A directory claiming a million
      // entries is refused having allocated a million nothing.
      if (archive.files.length > limits.maxEntries) {
        throw ArchiveReadException(
          'That archive holds more than ${limits.maxEntries} files, which is '
          'more than DocuAI will open at once.',
        );
      }

      final files = <ArchiveEntry>[];
      var refused = 0;
      var totalBytes = 0;

      for (final entry in archive.files) {
        // A folder entry carries no content and is re-derived from the file
        // paths anyway, so it is skipped rather than refused — leaving it out
        // is not a fact about the archive worth reporting.
        if (!entry.isFile) continue;

        // A symbolic link is a name pointing at another location, and an
        // extractor that follows one writes wherever it says. This app has no
        // use for links inside an archive, so they are refused outright rather
        // than resolved carefully.
        if (entry.isSymbolicLink) {
          refused++;
          continue;
        }

        final safe = safeEntryPath(entry.name);
        if (safe == null) {
          refused++;
          continue;
        }

        final compressed = compressedSizeOf(entry);
        if (!limits.allowsEntry(
          sizeBytes: entry.size,
          compressedBytes: compressed,
        )) {
          refused++;
          continue;
        }

        totalBytes += entry.size;
        if (totalBytes > limits.maxTotalBytes) {
          throw ArchiveReadException(
            'That archive unpacks to more than '
            '${limits.maxTotalBytes ~/ (1024 * 1024)} MB, which is more than '
            'DocuAI will open.',
          );
        }

        files.add(
          ArchiveEntry(
            path: safe,
            kind: kindForName(safe),
            sizeBytes: entry.size,
            compressedBytes: compressed,
          ),
        );
      }

      return ArchiveListing(
        name: p.basename(archivePath),
        sourcePath: archivePath,
        archiveBytes: archiveBytes,
        files: files,
        refusedEntries: refused,
      );
    } finally {
      // The decoder holds the file open so entries can be decompressed on
      // demand. This one is finished with.
      archive.clearSync();
      input.closeSync();
    }
  }

  /// Decompresses a single entry to disk.
  static String extractEntrySync({
    required String archivePath,
    required String entryPath,
    required String intoPath,
    String prefix = '',
    ArchiveLimits limits = const ArchiveLimits(),
  }) {
    final (input, archive) = _open(
      archivePath,
      'That archive could not be opened. It may be damaged.',
    );

    try {
      // Found by comparing *normalised* names, so an entry stored as
      // `.\folder\file.pdf` is still the one the browser listed as
      // `folder/file.pdf`.
      ArchiveFile? found;
      for (final entry in archive.files) {
        if (!entry.isFile || entry.isSymbolicLink) continue;
        if (safeEntryPath(entry.name) == entryPath) {
          found = entry;
          break;
        }
      }

      if (found == null) {
        throw const ArchiveReadException(
          'That file is no longer in the archive.',
        );
      }

      // Re-checked at extraction rather than trusted from the listing. The
      // listing was built from the same archive a moment ago, but the check is
      // one comparison and the thing it guards is a write to disk.
      if (!limits.allowsEntry(
        sizeBytes: found.size,
        compressedBytes: compressedSizeOf(found),
      )) {
        throw const ArchiveReadException(
          'That file is too large, or too heavily compressed, for DocuAI to '
          'open safely.',
        );
      }

      // The second, independent defence against a crafted name. Whatever
      // `entryPath` says, only its last segment survives, and it is joined to a
      // directory this app owns — so the write lands inside [intoPath] even if
      // the first defence had a hole in it.
      final safeName = p.basename(entryPath);
      final target = File(p.join(intoPath, '$prefix$safeName'));

      // And the proof, rather than the argument. A resolved path that does not
      // start inside the target directory is never written, whatever produced
      // it.
      final resolvedDirectory = p.normalize(intoPath);
      if (!p.isWithin(resolvedDirectory, p.normalize(target.path))) {
        throw const ArchiveReadException(
          'That file has a name DocuAI will not write.',
        );
      }

      target.parent.createSync(recursive: true);

      // Streamed to disk rather than read into a list first.
      //
      // `readBytes()` is the obvious call and it holds the whole entry in
      // memory — for the hundred-megabyte video an archive is allowed to
      // contain, that is a hundred-megabyte allocation on a phone, to produce a
      // file that is then written straight out again. `writeContent` inflates
      // through a buffer instead, so the peak cost is the buffer whatever the
      // entry weighs.
      final output = OutputFileStream(target.path);
      try {
        found.writeContent(output);
        output.closeSync();
      } catch (error) {
        output.closeSync();
        // A half-inflated file is worse than none. Left on disk it opens as a
        // damaged PDF and gets reported as the user's file being broken, when
        // what actually happened is that the archive is.
        if (target.existsSync()) target.deleteSync();
        throw ArchiveReadException(
          'That file could not be read out of the archive. It may be damaged.',
          cause: error,
        );
      }

      return target.path;
    } finally {
      archive.clearSync();
      input.closeSync();
    }
  }

  /// The first four bytes, or null when there are not four to read.
  ///
  /// Read through a handle rather than by loading the file: this runs on an
  /// archive that may be half a gigabyte, and the question is about four bytes
  /// at the front of it.
  static List<int>? _readHeader(File file) {
    RandomAccessFile? handle;
    try {
      handle = file.openSync();
      final header = handle.readSync(4);
      return header.length < 4 ? null : header;
    } catch (_) {
      return null;
    } finally {
      handle?.closeSync();
    }
  }

  /// Opens the archive's directory, or reports why it could not be read.
  ///
  /// Both callers need the stream *and* the archive back — the stream because
  /// the decoder keeps reading through it as entries are decompressed, and so
  /// somebody has to close it afterwards. Returning the pair from one place is
  /// what keeps the "a failed open closes what it opened" rule in one place
  /// too.
  static (InputFileStream, Archive) _open(String archivePath, String message) {
    final InputFileStream input;
    try {
      input = InputFileStream(archivePath);
    } catch (error) {
      throw ArchiveReadException(message, cause: error);
    }

    try {
      return (input, ZipDecoder().decodeStream(input));
    } catch (error) {
      input.closeSync();
      throw ArchiveReadException(message, cause: error);
    }
  }

  /// The compressed size an entry claims, or zero when it does not say.
  ///
  /// The `archive` package models an entry's backing store as a `FileContent`,
  /// and for a ZIP that object is the `ZipFile` header — which is where the
  /// compressed size lives. It is worth reaching for: without it the only
  /// zip-bomb test available is the total, and the total does not catch a
  /// single entry claiming to be a thousand times its stored size.
  static int compressedSizeOf(ArchiveFile entry) {
    final raw = entry.rawContent;
    return raw is ZipFile ? raw.compressedSize : 0;
  }

  /// The one gate every entry name passes through.
  ///
  /// Returns the normalised, archive-relative path, or null when the entry must
  /// be refused. Refused, not repaired: an entry named `../secrets` has no
  /// sensible interpretation, and quietly turning it into `secrets` would put a
  /// file the user never saw named into a list they will select from.
  ///
  /// What is refused, and why each one is a real archive somebody has shipped:
  ///
  ///  * `../` anywhere in the path — Zip Slip, the whole point.
  ///  * A leading `/` — an absolute path, which an extractor joining paths will
  ///    happily treat as the root.
  ///  * A Windows drive or UNC prefix (`C:\`, `\\server\share`) — the same
  ///    attack in the other family of path syntax, and `path` on Android does
  ///    not recognise either as absolute.
  ///  * An embedded NUL — the historical trick for making a checked string and
  ///    a written string differ.
  ///
  /// Backslashes are folded to forward slashes first. A ZIP written on Windows
  /// legitimately uses them as separators, so treating one as an ordinary
  /// character would turn `folder\..\..\file` into a single innocent-looking
  /// name that no `..` check would ever see.
  static String? safeEntryPath(String rawName) {
    if (rawName.isEmpty) return null;
    if (rawName.contains('\u0000')) return null;

    final unified = rawName.replaceAll(r'\', '/');

    // `C:/...` and `//server/share/...`, neither of which `p.isAbsolute`
    // recognises when the app is running on Android.
    if (RegExp(r'^[A-Za-z]:').hasMatch(unified)) return null;
    if (unified.startsWith('//')) return null;
    if (unified.startsWith('/')) return null;

    final segments = <String>[];
    for (final segment in unified.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      // Not resolved against what came before it. `a/../b` is a legal path that
      // means `b`, but an archive that contains it is an archive doing
      // something no zipper does by accident.
      if (segment == '..') return null;
      segments.add(segment);
    }

    if (segments.isEmpty) return null;

    return segments.join('/');
  }
}
