import 'package:path/path.dart' as p;

/// Where one thing going into a ZIP came from.
///
/// The distinction is not cosmetic: a file is already a file and goes in as it
/// stands, while a document is a row in Hive plus a folder of page images and
/// has to be *rendered* into something a recipient can open. Only this app
/// knows what a DocuAI document is, so the archive gets the PDF.
enum ZipSourceKind {
  /// A document from the library. Goes in as its exported PDF.
  document,

  /// A file the user picked with the system picker, already copied into the
  /// app's cache by the time it becomes one of these.
  file,
}

/// One thing the user has chosen to put in a ZIP.
///
/// Deliberately holds no file handle and no bytes. A selection can sit on
/// screen for minutes while the user picks more, and anything opened at
/// selection time would be a handle held for the whole of it — on files that,
/// for the document case, do not exist yet.
///
/// [id] is what tells two entries apart in a list, and it has to survive two
/// documents with the same title and two downloads of the same statement.
/// Documents key on their id and files on their cache path, both of which are
/// unique by construction.
class ZipSource {
  const ZipSource({
    required this.id,
    required this.kind,
    required this.name,
    required this.sizeBytes,
    this.documentId,
    this.path,
    this.pageCount,
  });

  /// A document, identified by id and titled as the library shows it.
  ///
  /// Carries a page count rather than a size, and that is a deliberate refusal
  /// to guess. A document's size in the archive is the size of a PDF that does
  /// not exist yet; the only honest figures available before the build are the
  /// page images, which are not what goes in, and rendering every selected
  /// document just to put a number beside it would make choosing as slow as
  /// archiving. "8 pages" is true, useful, and free.
  factory ZipSource.document({
    required String documentId,
    required String title,
    required int pageCount,
  }) => ZipSource(
    id: 'document:$documentId',
    kind: ZipSourceKind.document,
    name: title,
    sizeBytes: 0,
    documentId: documentId,
    pageCount: pageCount,
  );

  /// A file already copied into the app's cache.
  factory ZipSource.file({
    required String path,
    required String name,
    required int sizeBytes,
  }) => ZipSource(
    id: 'file:$path',
    kind: ZipSourceKind.file,
    name: name,
    sizeBytes: sizeBytes,
    path: path,
  );

  final String id;
  final ZipSourceKind kind;

  /// What the row shows: a document's title, or a file's own name *with* its
  /// extension — the extension is the only thing distinguishing `notes.txt`
  /// from `notes.pdf` in a list somebody is about to send to someone else.
  final String name;

  /// The file's size on disk, for a file. Zero for a document, whose size is
  /// not knowable until its PDF has been rendered — see [ZipSource.document].
  ///
  /// Never presented as the size of the finished ZIP either way: that depends
  /// on how well the content compresses, and is only known once it is written.
  final int sizeBytes;

  /// Set when [kind] is [ZipSourceKind.document].
  final String? documentId;

  /// Set when [kind] is [ZipSourceKind.file]. An absolute path into the app's
  /// own cache — never a content URI, whose grant would not outlive the picker.
  final String? path;

  /// Set when [kind] is [ZipSourceKind.document]. What its row shows instead
  /// of a size.
  final int? pageCount;

  bool get isDocument => kind == ZipSourceKind.document;

  /// The name this will carry *inside* the archive, before de-duplication.
  ///
  /// A document becomes a PDF because a PDF is what was put in for it. A file
  /// keeps the name it already had, which is the name the user recognises and
  /// the one the recipient will see.
  String get preferredEntryName =>
      isDocument ? '${sanitiseEntryName(name)}.pdf' : sanitiseEntryName(name);

  @override
  bool operator ==(Object other) => other is ZipSource && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ZipSource($id, $name, $sizeBytes)';
}

/// Reduces a name to something every file system will accept.
///
/// Document titles are typed by the user and are not file names: they may hold
/// slashes, colons and newlines, all of which are legal in a ZIP entry name and
/// none of which survive extraction on Windows. The slash is worse than untidy
/// — left in, it would silently turn one document into a folder in the
/// recipient's extractor, which is the same shape as the path-traversal problem
/// the reader refuses on the way in.
String sanitiseEntryName(String raw) {
  final cleaned = raw
      .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
      // Control characters, including the NUL that makes a checked string and
      // a written string differ.
      .replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '_')
      .trim();

  // A trailing dot or space is legal here and rejected by Windows.
  final trimmed = cleaned.replaceAll(RegExp(r'[. ]+$'), '');

  // Long names are refused by some extractors and truncated by others, and a
  // truncated name can collide with one that was unique before it was cut.
  final bounded = trimmed.length <= 120 ? trimmed : trimmed.substring(0, 120);

  return bounded.isEmpty ? 'document' : bounded;
}

/// One resolved entry, ready to be written.
///
/// The gap between this and [ZipSource] is where all the work happens: a
/// document has been rendered to a PDF that exists on disk, names have been
/// made unique against each other, and anything that could not be produced has
/// already been dropped and accounted for. The writer takes only these, so it
/// never has to know what a document is.
class ZipEntryPlan {
  const ZipEntryPlan({
    required this.entryName,
    required this.sourcePath,
    required this.sourceId,
  });

  /// The name inside the archive. Unique across one build.
  final String entryName;

  /// An absolute path to a file that exists right now.
  final String sourcePath;

  /// Which [ZipSource] this came from, so a failure can name it.
  final String sourceId;

  @override
  String toString() => 'ZipEntryPlan($entryName <- $sourcePath)';
}

/// Why one chosen thing did not make it into the archive.
///
/// Reported rather than swallowed, for the reason the archive importer learned
/// the hard way: a user who selects twelve things and receives a ZIP of ten has
/// no way to find out which two are missing, and will assume the app lost them.
class ZipSkippedSource {
  const ZipSkippedSource({required this.name, required this.reason});

  final String name;

  /// Why, in the words the user should read.
  final String reason;
}

/// What a finished build produced.
class ZipBuildOutcome {
  const ZipBuildOutcome({
    required this.path,
    required this.fileName,
    required this.entryCount,
    required this.sizeBytes,
    required this.sourceBytes,
    this.skipped = const <ZipSkippedSource>[],
  });

  /// Absolute path to the finished `.zip`, inside the app's cache.
  final String path;

  /// Its own name, as the share sheet and the recipient will show it.
  final String fileName;

  /// How many entries went in — which is not always how many were chosen.
  final int entryCount;

  /// The size of the archive on disk.
  final int sizeBytes;

  /// What went into it, uncompressed. Both numbers are shown, because
  /// "12.4 MB from 31.8 MB" is the one line that says whether zipping helped.
  final int sourceBytes;

  final List<ZipSkippedSource> skipped;

  bool get isComplete => skipped.isEmpty;

  /// How much smaller the archive is than its contents, 0–1.
  ///
  /// Zero rather than negative when the archive came out larger, which happens
  /// honestly: a ZIP of already-compressed files carries a header per entry and
  /// nothing compresses, so it ends up a few kilobytes bigger than the sum of
  /// its parts. That is not a saving of -0.02% worth reporting.
  double get savedFraction {
    if (sourceBytes <= 0 || sizeBytes >= sourceBytes) return 0;
    return (sourceBytes - sizeBytes) / sourceBytes;
  }
}

/// What one build will not do, whatever it is asked for.
///
/// The archive *reader* has `ArchiveLimits` for the same reason in the other
/// direction. These bound a job the user started rather than a file a stranger
/// sent, so they are looser — but a phone still has a cache directory with an
/// end to it, and a ZIP that fills the disk is a worse outcome than one that
/// was refused.
class ZipBuildLimits {
  const ZipBuildLimits({
    this.maxEntries = 500,
    this.maxTotalBytes = 2 * 1024 * 1024 * 1024,
  });

  /// The most things one archive will hold.
  final int maxEntries;

  /// The most it will read in, uncompressed.
  ///
  /// Two gigabytes. Past this the archive needs 64-bit offsets to be readable
  /// at all, and while the encoder does write them, an archive that large is
  /// not something a phone should be building into a cache directory Android is
  /// free to reclaim halfway through.
  final int maxTotalBytes;

  bool allows({required int entryCount, required int totalBytes}) =>
      entryCount <= maxEntries && totalBytes <= maxTotalBytes;
}

/// Makes every entry name unique, in the order they were chosen.
///
/// A ZIP may legally contain two entries with the same name and no extractor
/// agrees on what that means — most write one over the other, so a user who
/// archives two documents both called "Invoice" would send somebody a ZIP that
/// unpacks to a single file. Suffixing is what every desktop zipper does, and
/// it is what the recipient expects to see.
///
/// The comparison is case-insensitive because the extractor's file system
/// probably is: `Invoice.pdf` and `invoice.pdf` collide on Windows and macOS
/// even though the archive holds them as two distinct names.
List<String> uniqueEntryNames(Iterable<String> preferred) {
  final taken = <String>{};
  final result = <String>[];

  for (final name in preferred) {
    var candidate = name;

    if (taken.contains(candidate.toLowerCase())) {
      final extension = p.extension(name);
      final stem = name.substring(0, name.length - extension.length);

      // Starts at 2, so the pair reads "Invoice.pdf" and "Invoice (2).pdf" —
      // the numbering a person would have written themselves.
      var counter = 2;
      do {
        candidate = '$stem ($counter)$extension';
        counter++;
      } while (taken.contains(candidate.toLowerCase()));
    }

    taken.add(candidate.toLowerCase());
    result.add(candidate);
  }

  return result;
}

/// The name a new archive is offered under.
///
/// Dated rather than "Archive.zip", because these land in a downloads folder
/// beside everything else the recipient has ever been sent, and a name that
/// says when it was made is the difference between finding it again and not.
/// The user can change it before creating; this is only the starting point.
String defaultArchiveName(DateTime now) {
  String two(int value) => value.toString().padLeft(2, '0');
  return 'DocuAI ${now.year}-${two(now.month)}-${two(now.day)}';
}
