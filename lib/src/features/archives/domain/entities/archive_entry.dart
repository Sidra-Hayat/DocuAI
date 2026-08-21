import 'package:path/path.dart' as p;

/// What one thing inside an archive is, as far as this app is concerned.
///
/// Not a file format list. The question every screen asks is what tapping the
/// row should do — open it for reading, hand it to another app, or step into it
/// — and these are the answers to that. Which is why a `.docx` is [text] and a
/// nested `.zip` is [archive] rather than both being "other": one of them the
/// reader can show, and the other is a thing this app deliberately will not
/// open in place.
enum ArchiveEntryKind {
  folder,

  /// Rendered page by page, through the renderer Android already has.
  pdf,

  /// JPEG, PNG or WebP. Shown full screen, zoomable.
  image,

  /// Plain text, Markdown or a Word file — anything that becomes words.
  text,

  /// A ZIP inside a ZIP. Listed, never opened in place. See [ArchiveLimits].
  archive,

  /// Everything else: a video, a spreadsheet, a binary. Offered to whichever
  /// app on the device does know what to do with it.
  other;

  bool get isFolder => this == ArchiveEntryKind.folder;

  /// Whether DocuAI can show this without leaving the app.
  bool get isReadable =>
      this == ArchiveEntryKind.pdf ||
      this == ArchiveEntryKind.image ||
      this == ArchiveEntryKind.text;

  /// Whether the library can hold it. The same set the file importer accepts,
  /// which is not a coincidence — importing an entry *is* that importer.
  bool get isImportable => isReadable;
}

/// One file or folder inside an archive.
///
/// [path] is the entry's own name as it appears in the archive, already
/// normalised and already checked — `ZipReader` refuses anything that escapes
/// the archive root before an entry is ever built, so nothing downstream has to
/// ask whether a path is safe. It is a key, not a location: no file exists at
/// it until somebody asks for the entry to be extracted.
class ArchiveEntry {
  const ArchiveEntry({
    required this.path,
    required this.kind,
    required this.sizeBytes,
    this.compressedBytes = 0,
    this.childCount = 0,
  });

  /// Slash-separated, relative to the archive root, no leading slash.
  final String path;

  final ArchiveEntryKind kind;

  /// Uncompressed size. For a folder, the total of everything beneath it.
  final int sizeBytes;

  /// What it occupies inside the archive. Zero for a folder.
  final int compressedBytes;

  /// How many things are directly inside. Zero for a file.
  final int childCount;

  /// The last segment — what a row displays.
  String get name => p.basename(path);

  /// The folder holding this entry, or the empty string at the archive root.
  String get parent {
    final index = path.lastIndexOf('/');
    return index < 0 ? '' : path.substring(0, index);
  }

  bool get isFolder => kind.isFolder;

  @override
  bool operator ==(Object other) =>
      other is ArchiveEntry && other.path == path && other.kind == kind;

  @override
  int get hashCode => Object.hash(path, kind);

  @override
  String toString() => 'ArchiveEntry($path, $kind, $sizeBytes)';
}

/// Everything an archive turned out to contain.
///
/// Holds the *files* only, flat, with their full paths. Folders are not stored
/// because a ZIP does not reliably contain them — an archive written by one
/// tool has an entry per directory and one written by another has none at all,
/// and a browser whose folders appear or vanish depending on which zipper made
/// the file is a browser nobody can trust. [childrenOf] derives them from the
/// paths instead, which is the one description that is always right.
class ArchiveListing {
  const ArchiveListing({
    required this.name,
    required this.sourcePath,
    required this.archiveBytes,
    required this.files,
    this.refusedEntries = 0,
  });

  /// The archive's own file name, as the user knows it.
  final String name;

  /// Where the `.zip` sits on disk — always inside DocuAI's own storage.
  final String sourcePath;

  /// The size of the archive file itself.
  final int archiveBytes;

  /// Every file in the archive, in the order the archive lists them.
  final List<ArchiveEntry> files;

  /// How many entries were refused on the way in — a path that tried to escape
  /// the archive, a symbolic link, something past the size caps.
  ///
  /// Surfaced rather than swallowed. An archive that lists eleven files and
  /// shows ten is one the user will assume this app failed to read, and
  /// "one entry was left out because it was unsafe" is a different fact from
  /// "this archive is broken".
  final int refusedEntries;

  int get fileCount => files.length;

  /// How many of them the library can actually hold.
  ///
  /// Surfaced because the browser has no other way to say it. A file DocuAI
  /// cannot import has no checkbox, and a row that simply lacks a control is
  /// indistinguishable from one the user failed to notice — which is how
  /// somebody comes away from a seventeen-file archive with four documents and
  /// no idea what happened to the rest.
  int get importableCount =>
      files.where((file) => file.kind.isImportable).length;

  /// The uncompressed total, which is what the header reports and what the
  /// caps are enforced against.
  int get totalBytes =>
      files.fold<int>(0, (sum, file) => sum + file.sizeBytes);

  bool get isEmpty => files.isEmpty;

  /// What sits directly inside [folder] — its files, plus a synthesised entry
  /// for each folder below it.
  ///
  /// Folders first and each group alphabetical, case-insensitively. A ZIP's own
  /// order is whatever its writer felt like, which for an archive of two
  /// hundred entries is no order at all.
  List<ArchiveEntry> childrenOf(String folder) {
    final prefix = folder.isEmpty ? '' : '$folder/';

    final children = <ArchiveEntry>[];

    /// Folder path -> the names of the things directly inside it.
    ///
    /// Names rather than a running count, because the same subfolder is reached
    /// once per file beneath it and must be counted once. A plain counter said
    /// "0 items" for a folder holding nothing but subfolders — which is what
    /// `invoices/january/…` and `invoices/february/…` make of `invoices` — and
    /// a row that reports a folder as empty while offering a chevron into it is
    /// a row nobody believes.
    final folderChildren = <String, Set<String>>{};

    /// Folder path -> total bytes anywhere beneath it, however deep.
    final folderBytes = <String, int>{};

    for (final file in files) {
      if (!file.path.startsWith(prefix)) continue;

      final rest = file.path.substring(prefix.length);
      if (rest.isEmpty) continue;

      final slash = rest.indexOf('/');
      if (slash < 0) {
        children.add(file);
        continue;
      }

      final childFolder = '$prefix${rest.substring(0, slash)}';

      // What sits directly inside that folder on the way to this file: either
      // the file itself, or the next folder down.
      final remainder = rest.substring(slash + 1);
      final nextSlash = remainder.indexOf('/');
      final directChild = nextSlash < 0
          ? remainder
          : remainder.substring(0, nextSlash);

      if (directChild.isNotEmpty) {
        folderChildren.putIfAbsent(childFolder, () => <String>{}).add(directChild);
      }

      // Everything deeper counts towards the folder that starts here, so a row
      // can say how much is inside without a second pass over the list.
      folderBytes[childFolder] = (folderBytes[childFolder] ?? 0) + file.sizeBytes;
    }

    final folderEntries = folderChildren.entries
        .map(
          (entry) => ArchiveEntry(
            path: entry.key,
            kind: ArchiveEntryKind.folder,
            sizeBytes: folderBytes[entry.key] ?? 0,
            childCount: entry.value.length,
          ),
        )
        .toList()
      ..sort(_byName);

    children.sort(_byName);

    return <ArchiveEntry>[...folderEntries, ...children];
  }

  /// Every file at or below [folder]. What "Select all" inside a folder means.
  List<ArchiveEntry> filesUnder(String folder) {
    if (folder.isEmpty) return files;
    final prefix = '$folder/';
    return files.where((file) => file.path.startsWith(prefix)).toList();
  }

  static int _byName(ArchiveEntry a, ArchiveEntry b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

/// Works out what an entry is from its name.
///
/// The name is all there is: a ZIP records no content type, and sniffing the
/// bytes would mean decompressing every entry to draw a list — the exact thing
/// this feature is built not to do.
ArchiveEntryKind kindForName(String name) {
  final extension = p.extension(name).replaceFirst('.', '').toLowerCase();

  return switch (extension) {
    'pdf' => ArchiveEntryKind.pdf,
    'jpg' || 'jpeg' || 'png' || 'webp' => ArchiveEntryKind.image,
    'txt' || 'md' || 'docx' => ArchiveEntryKind.text,
    'zip' || 'rar' || '7z' || 'tar' || 'gz' => ArchiveEntryKind.archive,
    _ => ArchiveEntryKind.other,
  };
}
