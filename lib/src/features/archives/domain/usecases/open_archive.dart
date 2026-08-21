import '../../../../core/error/result.dart';
import '../entities/archive_entry.dart';
import '../repositories/archive_repository.dart';

/// Describes an archive so it can be browsed.
class OpenArchive {
  const OpenArchive(this._archives);

  final ArchiveRepository _archives;

  FutureResult<ArchiveListing> call(String archivePath) =>
      _archives.open(archivePath);
}

/// Pulls one file out of an archive so it can be *read*.
///
/// Named for reading rather than for extracting, because that is the only thing
/// the app does with the result. The file lands in a cache directory the next
/// archive will clear; nothing about this puts it in the library, and the
/// screen it opens has no way to.
class ReadArchiveEntry {
  const ReadArchiveEntry(this._archives);

  final ArchiveRepository _archives;

  FutureResult<String> call({
    required String archivePath,
    required ArchiveEntry entry,
  }) => _archives.extract(archivePath: archivePath, entry: entry);
}
