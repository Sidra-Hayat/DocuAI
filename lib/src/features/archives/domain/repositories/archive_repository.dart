import '../../../../core/error/result.dart';
import '../entities/archive_entry.dart';

/// Looking inside a ZIP without unpacking it.
///
/// Two operations, and the split between them is the feature's central
/// distinction: [open] describes an archive and touches no content, [extract]
/// produces one file and imports nothing. **Reading is not importing.** A user
/// who opens a ZIP to check which invoice is in it has added nothing to their
/// library, and nothing here can add anything to it — that takes the import use
/// case, which the user asks for by name.
abstract interface class ArchiveRepository {
  /// Lists what is inside the archive at [archivePath].
  ///
  /// Reads the archive's directory only. The cost is the same for a ten-file
  /// archive and a four-thousand-file one, and no entry is decompressed.
  ///
  /// Fails when the file is not a readable ZIP, or when it is outside the
  /// limits in `ArchiveLimits` — the caller shows the message as an error
  /// screen rather than an empty archive, because "damaged" and "empty" are
  /// different things to be told.
  FutureResult<ArchiveListing> open(String archivePath);

  /// Decompresses one entry into DocuAI's own cache and returns its path.
  ///
  /// The file it writes is temporary and belongs to the archive session — the
  /// next archive opened clears it. Nothing about this call puts anything in
  /// the library.
  FutureResult<String> extract({
    required String archivePath,
    required ArchiveEntry entry,
  });
}
