import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../import/data/datasources/import_scratch.dart';
import '../../domain/entities/archive_entry.dart';
import '../../domain/repositories/archive_repository.dart';
import '../datasources/zip_reader.dart';

/// The ZIP reader, wrapped in the app's error contract.
///
/// Thin on purpose. Everything that decides what is safe lives in [ZipReader],
/// where it can be tested against a real archive without a repository, a
/// provider or a widget; what this adds is the translation from "the reader
/// threw" to "the domain has a [Failure]", which is the boundary every other
/// repository in this app draws in the same place.
class ArchiveRepositoryImpl implements ArchiveRepository {
  const ArchiveRepositoryImpl({
    ZipReader reader = const ZipReader(),
    Future<Directory> Function()? temporaryDirectory,
  }) : _reader = reader,
       _tempDir = temporaryDirectory ?? getTemporaryDirectory;

  final ZipReader _reader;
  final Future<Directory> Function() _tempDir;

  /// Scratch space for the entries a user opens, separate from the importer's.
  ///
  /// Two names rather than one shared folder, because `ImportScratch.prepare`
  /// empties what it prepares: an import running inside an archive session
  /// would otherwise delete the PDF the reader is displaying, mid-read. The
  /// class documents exactly this case.
  static const String scratchName = 'docuai_archive';

  @override
  FutureResult<ArchiveListing> open(String archivePath) async {
    try {
      final listing = await _reader.list(archivePath);

      // Cleared here rather than on the way out. An archive session ends in as
      // many places as an import does — a back gesture, a crash, a corrupt
      // entry — and the one moment that reliably happens exactly once per
      // session is its start.
      await ImportScratch.prepare(
        temporaryDirectory: _tempDir,
        name: scratchName,
      );

      return Success(listing);
    } on ArchiveReadException catch (error, stackTrace) {
      return Failed(
        ImportFailure(error.message, cause: error.cause, stackTrace: stackTrace),
      );
    } catch (error, stackTrace) {
      return Failed(
        ImportFailure(
          'That archive could not be opened.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  FutureResult<String> extract({
    required String archivePath,
    required ArchiveEntry entry,
  }) async {
    if (entry.isFolder) {
      return const Failed(ImportFailure('That is a folder, not a file.'));
    }

    try {
      final root = await _tempDir();
      final directory = Directory(p.join(root.path, scratchName));
      if (!directory.existsSync()) {
        await directory.create(recursive: true);
      }

      // Two entries in different folders of one archive can share a name —
      // `january/summary.pdf` and `february/summary.pdf` — and extracting the
      // second over the first would show the user the wrong document. The
      // prefix is derived from the entry's full path, so it is stable: opening
      // the same entry twice writes the same file rather than filling the cache
      // with copies.
      final prefix = '${entry.path.hashCode.toUnsigned(32).toRadixString(16)}_';

      final path = await _reader.extractEntry(
        archivePath: archivePath,
        entryPath: entry.path,
        into: directory,
        prefix: prefix,
      );

      return Success(path);
    } on ArchiveReadException catch (error, stackTrace) {
      return Failed(
        ImportFailure(error.message, cause: error.cause, stackTrace: stackTrace),
      );
    } catch (error, stackTrace) {
      return Failed(
        ImportFailure(
          'That file could not be read out of the archive.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }
}
