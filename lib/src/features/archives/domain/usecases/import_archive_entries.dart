import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../documents/domain/entities/document.dart';
import '../../../import/domain/usecases/import_file.dart';
// Reused rather than redeclared. `ToolProgress` is a count, a total and a
// label, and the PDF tools already report exactly that shape from exactly this
// kind of loop — a second identical class in this feature would only guarantee
// that the two drift.
import '../../../pdf_tools/domain/entities/pdf_tool_models.dart';
import '../entities/archive_entry.dart';
import '../repositories/archive_repository.dart';

/// What became of one selected file.
///
/// Every status here is a different sentence the user needs to read, which is
/// why they are not collapsed into a bool. "DocuAI does not import .xlsx",
/// "that PDF is damaged" and "you stopped before this one" are three different
/// facts, and an import that reports all three as "failed" has told the user
/// nothing they can act on.
enum ArchiveImportStatus {
  /// It is in the library now.
  imported,

  /// Not a format the library holds. Known before anything was extracted.
  unsupported,

  /// It should have worked and did not — a damaged file, a PDF the renderer
  /// refused, an entry that could not be pulled out of the archive.
  unreadable,

  /// Never attempted, because the user stopped the run before reaching it.
  stopped,
}

/// One file's fate, with the reason attached.
class ArchiveImportEntryOutcome {
  const ArchiveImportEntryOutcome({
    required this.name,
    required this.path,
    required this.status,
    this.reason,
    this.document,
  });

  /// The entry's own file name, as the browser showed it.
  final String name;

  /// Its full path inside the archive, which is what tells two files of the
  /// same name in different folders apart.
  final String path;

  final ArchiveImportStatus status;

  /// Why, in the words the user should see. Null for [ArchiveImportStatus
  /// .imported], where there is nothing to explain.
  final String? reason;

  /// The document created, when one was.
  final Document? document;

  bool get isImported => status == ArchiveImportStatus.imported;
}

/// What importing a selection produced.
///
/// **Every selected file appears in [entries], whatever happened to it.** That
/// is the whole point of this class and it was the bug it was rewritten for: a
/// user selected seventeen files, four arrived, and nothing on screen accounted
/// for the other thirteen. Silently dropping the unsupported ones before the
/// loop even started was most of it.
class ArchiveImportOutcome {
  const ArchiveImportOutcome({required this.entries, this.cancelled = false});

  /// One per selected file, in the order they were selected.
  final List<ArchiveImportEntryOutcome> entries;

  /// True when the user stopped it part way. Everything already imported is
  /// kept — the documents exist, and deleting them because the *next* one was
  /// interrupted would be the opposite of what Stop means.
  final bool cancelled;

  List<ArchiveImportEntryOutcome> get imported =>
      entries.where((entry) => entry.isImported).toList();

  /// Everything that did not make it, whatever the reason.
  List<ArchiveImportEntryOutcome> get notImported =>
      entries.where((entry) => !entry.isImported).toList();

  List<ArchiveImportEntryOutcome> withStatus(ArchiveImportStatus status) =>
      entries.where((entry) => entry.status == status).toList();

  /// The documents created, for callers that only want what arrived.
  List<Document> get documents => entries
      .map((entry) => entry.document)
      .whereType<Document>()
      .toList();

  /// The names of everything that did not arrive.
  List<String> get failed =>
      notImported.map((entry) => entry.name).toList();

  int get importedCount => imported.length;

  bool get isEmpty => importedCount == 0;

  /// True when every single selected file arrived — the case worth saying
  /// plainly rather than making the user count rows.
  bool get isComplete => notImported.isEmpty;
}

/// Reports each file the moment it is finished with.
///
/// The screen accumulates these rather than waiting for the return value,
/// which is what lets Stop abandon the run and *still* show a complete account
/// of what happened before it was stopped.
typedef ArchiveEntryOutcomeCallback =
    void Function(ArchiveImportEntryOutcome outcome);

/// Brings chosen files out of an archive and into the library.
///
/// **One document per file.** A ZIP of twelve invoices becomes twelve
/// documents, not one twelve-page document: they are separate things that
/// happened to travel together, and joining them would be a merge the user did
/// not ask for — which the app already offers, separately, for when they want
/// it.
///
/// Every file goes through [ImportFileAsDocument.fromPath], which is the same
/// use case the Files button uses. A PDF from an archive is rasterised by the
/// same rasteriser, capped at the same page limit and indexed by the same
/// search index as a PDF picked from Downloads. Nothing here knows how a
/// document gets made.
class ImportArchiveEntries {
  const ImportArchiveEntries({
    required ArchiveRepository archives,
    required ImportFileAsDocument importer,
  }) : _archives = archives,
       _importer = importer;

  final ArchiveRepository _archives;
  final ImportFileAsDocument _importer;

  /// Imports [entries], one at a time, accounting for every one of them.
  ///
  /// Sequential rather than concurrent, deliberately. Each import rasterises a
  /// PDF or decodes an image at full size, and running six of those at once on
  /// a phone is how an out-of-memory kill happens on the device that can least
  /// afford it. It also makes progress mean something: "4 of 17" is true.
  ///
  /// [isCancelled] is polled around every step, and passed down into the file
  /// importer so that a multi-page PDF stops between pages rather than running
  /// to the end of a file nobody is waiting for any more. What it cannot do is
  /// interrupt a page already being rendered — that is inside a platform call
  /// this has no handle on — which is why the screen abandons the result as
  /// well as asking for it to stop.
  FutureResult<ArchiveImportOutcome> call({
    required String archivePath,
    required List<ArchiveEntry> entries,
    ToolProgressCallback? onProgress,
    ArchiveEntryOutcomeCallback? onEntryDone,
    bool Function()? isCancelled,
  }) async {
    // Folders are not files and were never going to be imported; the browser
    // does not put them in a selection either. Everything else is attempted or
    // explained.
    final selected = entries.where((entry) => !entry.isFolder).toList();

    if (selected.isEmpty) {
      return const Failed(
        ImportFailure('There were no files in that selection.'),
      );
    }

    final results = <ArchiveImportEntryOutcome>[];

    void record(ArchiveImportEntryOutcome outcome) {
      results.add(outcome);
      onEntryDone?.call(outcome);
    }

    var stopped = false;

    for (var index = 0; index < selected.length; index++) {
      final entry = selected[index];

      if (isCancelled?.call() ?? false) {
        stopped = true;
        // Everything from here on is accounted for as untouched, so the report
        // adds up to the number the user selected rather than trailing off.
        for (final remaining in selected.sublist(index)) {
          record(
            ArchiveImportEntryOutcome(
              name: remaining.name,
              path: remaining.path,
              status: ArchiveImportStatus.stopped,
              reason: 'You stopped the import before this file.',
            ),
          );
        }
        break;
      }

      onProgress?.call(
        ToolProgress(done: index, total: selected.length, label: entry.name),
      );

      // Known before any work: this is the case that used to vanish. Filtering
      // these out ahead of the loop is what let thirteen files disappear
      // without a word.
      if (!entry.kind.isImportable) {
        record(
          ArchiveImportEntryOutcome(
            name: entry.name,
            path: entry.path,
            status: ArchiveImportStatus.unsupported,
            reason: entry.kind == ArchiveEntryKind.archive
                ? 'DocuAI does not open an archive inside an archive.'
                : 'DocuAI imports PDFs, Word files, text files and pictures.',
          ),
        );
        continue;
      }

      final extracted = await _archives.extract(
        archivePath: archivePath,
        entry: entry,
      );

      switch (extracted) {
        case Failed(:final failure):
          record(
            ArchiveImportEntryOutcome(
              name: entry.name,
              path: entry.path,
              status: ArchiveImportStatus.unreadable,
              reason: failure.message,
            ),
          );
        case Success(value: final path):
          final imported = await _importer.fromPath(
            path,
            // Titled from the entry rather than from the temporary file, whose
            // name carries the de-duplicating prefix the cache needs and the
            // user has no business seeing.
            title: _titleFor(entry),
            isCancelled: isCancelled,
          );

          switch (imported) {
            case Failed(:final failure):
              record(
                ArchiveImportEntryOutcome(
                  name: entry.name,
                  path: entry.path,
                  // A conversion that stopped because the user stopped is not
                  // a broken file, and must not be reported as one.
                  status: failure is ImportFailure && failure.cancelled
                      ? ArchiveImportStatus.stopped
                      : ArchiveImportStatus.unreadable,
                  reason: failure.message,
                ),
              );
            case Success(value: final result):
              record(
                ArchiveImportEntryOutcome(
                  name: entry.name,
                  path: entry.path,
                  status: ArchiveImportStatus.imported,
                  document: result.document,
                ),
              );
          }
      }
    }

    onProgress?.call(
      ToolProgress(done: selected.length, total: selected.length),
    );

    return Success(
      ArchiveImportOutcome(entries: results, cancelled: stopped),
    );
  }

  /// An entry's name without its extension — what the library row will show.
  static String _titleFor(ArchiveEntry entry) {
    final name = entry.name;
    final dot = name.lastIndexOf('.');
    final stem = dot <= 0 ? name : name.substring(0, dot);
    return stem.trim().isEmpty ? name : stem.trim();
  }
}
