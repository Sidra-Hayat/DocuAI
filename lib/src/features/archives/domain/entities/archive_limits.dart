/// The ceilings an archive has to stay under to be opened at all.
///
/// A ZIP is the one file format this app accepts where the *file* says how much
/// work it is and the file is written by somebody else. Forty-two kilobytes of
/// archive can describe four petabytes of output; ten entries can describe ten
/// million. Every limit here exists because the alternative is letting a
/// stranger's file decide how much memory and disk DocuAI uses.
///
/// The numbers are deliberately generous for real archives and hopeless for
/// hostile ones. A folder of scanned invoices, a chat export, a term's lecture
/// notes — none of them come close to any of these.
class ArchiveLimits {
  const ArchiveLimits({
    this.maxEntries = 4000,
    this.maxTotalBytes = 512 * 1024 * 1024,
    this.maxEntryBytes = 128 * 1024 * 1024,
    this.maxRatio = 300,
  });

  /// How many entries will be listed.
  ///
  /// The browser holds one object per file, so this bounds memory before
  /// anything is decompressed. Four thousand is more than a person browses and
  /// far less than the millions a crafted directory can claim.
  final int maxEntries;

  /// The largest total uncompressed size that will be opened.
  ///
  /// Read from the central directory, so this is a refusal *before* any
  /// decompression rather than a check that stops one part way.
  final int maxTotalBytes;

  /// The largest single entry that will be extracted.
  ///
  /// The total above is not enough on its own: one entry claiming everything
  /// under the total is still a single allocation the device may not survive,
  /// and it is the shape a bomb usually takes.
  final int maxEntryBytes;

  /// The largest uncompressed-to-compressed ratio an entry may claim.
  ///
  /// This is the actual zip-bomb test. Ordinary data does not compress anywhere
  /// near this well — text reaches perhaps ten to one, images and PDFs barely
  /// compress at all — while a bomb is built out of a repeated byte and reaches
  /// a thousand to one and beyond. Three hundred leaves room for the genuinely
  /// compressible (a log file, a huge sparse CSV) and none for the deliberate.
  final int maxRatio;

  /// Whether the archive as a whole is within its ceilings.
  bool allowsArchive({required int entryCount, required int totalBytes}) =>
      entryCount <= maxEntries && totalBytes <= maxTotalBytes;

  /// Whether one entry may be listed and, later, extracted.
  ///
  /// A refused entry is left out of the listing rather than failing the whole
  /// archive: one hostile file among two hundred holiday photographs should
  /// cost the user that one file, not the archive.
  bool allowsEntry({required int sizeBytes, required int compressedBytes}) {
    if (sizeBytes < 0 || sizeBytes > maxEntryBytes) return false;

    // A stored (uncompressed) entry has a ratio of one and is fine. Only a
    // *claim* of extreme compression is refused, and a compressed size of zero
    // with a non-zero uncompressed size is the most extreme claim there is.
    if (compressedBytes <= 0) return sizeBytes == 0;

    return sizeBytes ~/ compressedBytes <= maxRatio;
  }
}
