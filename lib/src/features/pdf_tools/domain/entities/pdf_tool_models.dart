import '../../../documents/domain/entities/document.dart';

/// A PDF the user has chosen but not yet merged.
///
/// Holds a path into the app's cache rather than the content URI the picker
/// returned: a URI grant does not survive into the isolate that renders the
/// pages, which is why the picker is asked to copy the file in first.
///
/// The [id] exists because two files can genuinely have the same name and the
/// same size — the same statement downloaded twice — and a reorderable list
/// needs a key that tells them apart.
class PdfSource {
  const PdfSource({
    required this.id,
    required this.path,
    required this.name,
    required this.sizeBytes,
  });

  final String id;
  final String path;

  /// The file's own name, without its extension. What the list shows.
  final String name;

  final int sizeBytes;

  @override
  bool operator ==(Object other) => other is PdfSource && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// How hard to squeeze.
///
/// Three, named for the outcome rather than for the settings. "Balanced" means
/// something to somebody choosing; "1800px at quality 68" does not.
///
/// The numbers are the two that actually decide a page's size: how many pixels
/// it keeps, and how hard the JPEG encoder is pushed. Both matter — dropping
/// quality alone leaves a needlessly large image, and resizing alone leaves it
/// needlessly fine.
enum CompressionLevel {
  /// Barely touched. For a document that has to stay legible when printed.
  highQuality(
    label: 'High quality',
    description: 'Slightly smaller, still sharp enough to print',
    maxEdge: 2400,
    jpegQuality: 80,
  ),

  /// The default, and the one most documents want.
  balanced(
    label: 'Balanced',
    description: 'Noticeably smaller, still comfortable to read',
    maxEdge: 1800,
    jpegQuality: 68,
  ),

  /// For sending over a slow connection or a size-limited form.
  smallerSize(
    label: 'Smaller size',
    description: 'Much smaller, best for email and uploads',
    maxEdge: 1200,
    jpegQuality: 52,
  );

  const CompressionLevel({
    required this.label,
    required this.description,
    required this.maxEdge,
    required this.jpegQuality,
  });

  final String label;
  final String description;

  /// Longest edge kept, in pixels.
  final int maxEdge;

  final int jpegQuality;
}

/// What a merge produced.
class MergeOutcome {
  const MergeOutcome({
    required this.document,
    required this.pageCount,
    required this.sourceCount,
    this.truncated = false,
  });

  final Document document;
  final int pageCount;
  final int sourceCount;

  /// True when the page budget was reached and later pages were left out.
  ///
  /// Reported rather than swallowed. A merge that quietly stops at page two
  /// hundred is a document the user believes is complete, and they would only
  /// find out after sending it to somebody.
  final bool truncated;
}

/// What a compression run produced.
///
/// Carries both sizes whether or not it saved anything, because "it could not
/// be made smaller" is only a useful answer when it comes with the numbers.
///
/// **A copy is kept only when it is smaller.** This has been both ways. It
/// used to be discarded, then it was always kept — on the reasoning that the
/// user had waited for the work and deserved something for it, and that pages
/// bounded to 1200px can be what an upload form needs whatever the byte count
/// did. Real-device use settled it the other way: a 742 KB document came back
/// as a 765 KB "(compressed)" copy, and a library filling with larger
/// duplicates of the same document — each one named "(compressed)" again — is
/// a worse outcome than being told plainly that there was nothing to gain.
///
/// So [document] is null when the copy came out no smaller, and nothing was
/// written. The original is never touched either way.
class CompressionOutcome {
  const CompressionOutcome({
    required this.originalBytes,
    required this.compressedBytes,
    required this.level,
    required this.document,
    required this.sourceLabel,
  });

  /// The size of what went in — a document's pages, or a PDF file on disk.
  final int originalBytes;

  /// The size the pages came to after re-encoding.
  final int compressedBytes;

  final CompressionLevel level;

  /// The document that was saved, or null when nothing was.
  ///
  /// Null exactly when [reduced] is false — the two always agree, because the
  /// size comparison is the only thing that decides whether a copy is written.
  final Document? document;

  /// What was compressed, for an answer that names its subject.
  final String sourceLabel;

  /// False when re-encoding produced no saving, which is a normal outcome for
  /// a PDF that has already been through this once. Nothing is saved when this
  /// is false — see [document].
  bool get reduced => compressedBytes < originalBytes;

  /// The title a compressed copy of [sourceTitle] should carry.
  ///
  /// A document that is already "X (compressed)" stays "X (compressed)" rather
  /// than becoming "X (compressed) (compressed)". The suffix says what the
  /// document *is*, and it is no more true twice than once.
  static const String compressedSuffix = ' (compressed)';

  static String titleFor(String sourceTitle) =>
      sourceTitle.trimRight().endsWith(compressedSuffix.trim())
      ? sourceTitle
      : '$sourceTitle$compressedSuffix';

  /// How much was saved, as a fraction between 0 and 1.
  double get savedFraction {
    if (originalBytes <= 0 || compressedBytes >= originalBytes) return 0;
    return (originalBytes - compressedBytes) / originalBytes;
  }

  int get savedBytes =>
      compressedBytes >= originalBytes ? 0 : originalBytes - compressedBytes;
}

/// How far through a long job the tools have got.
///
/// A merge of six files is six rasterisations, each of which can take seconds;
/// a spinner with no end in sight is the difference between a slow tool and an
/// app that looks hung.
class ToolProgress {
  const ToolProgress({
    required this.done,
    required this.total,
    this.label = '',
  });

  final int done;
  final int total;

  /// What is being worked on — a file name, or a page number.
  final String label;

  double? get fraction => total <= 0 ? null : (done / total).clamp(0, 1);
}

/// Reports progress back to the caller. Optional everywhere it is accepted.
typedef ToolProgressCallback = void Function(ToolProgress progress);

/// Bytes as a person would say them.
///
/// Lives with the models because both tools report sizes and a second
/// formatter written at a call site would round differently.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';

  const units = <String>['KB', 'MB', 'GB'];
  var value = bytes / 1024;
  var unit = 0;

  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }

  // One decimal below ten, none above: "9.4 MB" is worth the digit and
  // "247.3 MB" is not.
  return value >= 10
      ? '${value.round()} ${units[unit]}'
      : '${value.toStringAsFixed(1)} ${units[unit]}';
}
