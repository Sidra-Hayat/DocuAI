import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// The working directory an import normalises files into before they are
/// persisted.
///
/// Importing is a two-step move: a picked file is decoded, made upright, bounded
/// in size and re-encoded here, and only then copied into the document store.
/// The copy is what the library keeps; this directory is scaffolding.
///
/// It used to be scaffolding that was never taken down. Both importers created
/// the directory, wrote into it and left, so every photograph a user imported
/// stayed on disk twice — once as a page and once as the temporary JPEG it was
/// made from. Android's cache directory is reclaimable, so the copies were not
/// permanent, but "the system will delete it eventually under memory pressure"
/// is not the same as tidying up.
///
/// Clearing on entry rather than on exit is deliberate. An import can end in a
/// dozen places — a picker dismissed, a decode that failed, a document the
/// store refused — and a cleanup step at each of them is a cleanup step that
/// will be forgotten at the next one. Doing it once, here, means the directory
/// holds one import's worth of files at most, whatever happened to the last one.
abstract final class ImportScratch {
  /// Folder name inside the app's cache directory.
  static const String directoryName = 'docuai_import';

  /// An empty directory to normalise into.
  static Future<Directory> prepare({
    Future<Directory> Function()? temporaryDirectory,
  }) async {
    final root = await (temporaryDirectory ?? getTemporaryDirectory)();
    final scratch = Directory(p.join(root.path, directoryName));

    // Anything still here belongs to an import that has already finished, and
    // whatever it produced was copied into the document store at the time.
    if (scratch.existsSync()) {
      await scratch.delete(recursive: true);
    }
    await scratch.create(recursive: true);

    return scratch;
  }
}
