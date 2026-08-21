import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_state_view.dart';
import '../../../documents/domain/entities/document.dart';
import '../../../pdf_tools/domain/entities/pdf_tool_models.dart';
import '../../domain/entities/archive_entry.dart';
import '../../domain/usecases/import_archive_entries.dart';
import '../providers/archive_providers.dart';
import '../widgets/archive_entry_tile.dart';
import '../widgets/archive_import_report.dart';
import '../widgets/archive_path_bar.dart';
import 'file_reader_screen.dart';

/// What the browser was asked to open.
class ArchiveArgs {
  const ArchiveArgs({required this.path, required this.name});

  /// The `.zip` on disk, always inside DocuAI's own storage.
  final String path;

  /// What the user knows the archive as.
  final String name;
}

/// The inside of a ZIP.
///
/// **This screen is a reader, not an importer**, and everything about it is
/// arranged to keep that true. Opening a ZIP that somebody sent lands here, not
/// on "Import 34 files?" — because the first question anybody has about an
/// archive is what is in it, and an app that answers by copying all of it into
/// your library has answered a question nobody asked.
///
/// So tapping a row *reads*. Importing is a second, named action, on a selection
/// the user made, with a count in the label. The two never happen together.
///
/// Nothing is unpacked to draw this. The list comes from the archive's own
/// directory — see `ZipReader` — and a file is decompressed only when somebody
/// asks for that file.
class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({required this.args, super.key});

  final ArchiveArgs args;

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  ArchiveListing? _listing;
  Failure? _failure;
  bool _loading = true;

  /// Where in the archive the user is. Empty string is the root.
  String _folder = '';

  /// Selected entries, by path. Files only — a folder's checkbox selects what
  /// is inside it rather than the folder itself, because a folder is not a
  /// thing the library can hold.
  final Set<String> _selected = <String>{};

  /// The import currently running, or null.
  ///
  /// A token rather than a bool, and that is the fix for a real hang. Stop used
  /// to set a flag and then *keep waiting* for the use case to notice it — but
  /// the file being converted at that moment is a PDF rasterising inside a
  /// platform call, and nothing in Dart can interrupt one. The screen sat on
  /// "Finishing the current file… 0 of 7" with Back disabled, and the only way
  /// out was Recents.
  ///
  /// Now Stop marks the token cancelled *and detaches from it*. Whatever that
  /// run does afterwards, its result is no longer this screen's: the check
  /// `_run != run` throws it away. The work still winds down — the token is
  /// polled all the way into the page loop of the rasteriser — but the user
  /// never waits for it.
  _ImportRun? _run;

  /// Files reported finished so far, live. What makes an abandoned run still
  /// able to give a complete account of itself.
  final List<ArchiveImportEntryOutcome> _done = <ArchiveImportEntryOutcome>[];

  /// The selection the running import was given, so Stop can name what it
  /// never reached.
  List<ArchiveEntry> _running = const <ArchiveEntry>[];

  /// Set when an import finishes or is stopped. While it is non-null the screen
  /// shows the report rather than the list.
  ArchiveImportOutcome? _outcome;

  ToolProgress? _progress;

  bool get _importing => _run != null;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    // A screen that has gone must not leave a rasteriser running for it.
    _run?.cancelled = true;
    super.dispose();
  }

  Future<void> _open() async {
    final result = await ref.read(openArchiveProvider)(widget.args.path);
    if (!mounted) return;

    setState(() {
      _loading = false;
      switch (result) {
        case Success(:final value):
          _listing = value;
        case Failed(:final failure):
          _failure = failure;
      }
    });
  }

  // ---- Navigating inside the archive --------------------------------------

  void _enter(ArchiveEntry folder) => setState(() => _folder = folder.path);

  /// Up one level, or false when already at the root and there is nowhere to go.
  bool _leave() {
    if (_folder.isEmpty) return false;
    final slash = _folder.lastIndexOf('/');
    setState(() => _folder = slash < 0 ? '' : _folder.substring(0, slash));
    return true;
  }

  void _goTo(String folder) => setState(() => _folder = folder);

  // ---- Selection -----------------------------------------------------------

  void _toggle(ArchiveEntry entry) {
    setState(() {
      if (entry.isFolder) {
        // A folder's tick means everything importable beneath it. Ticking a
        // folder of forty photographs and being given nothing is the kind of
        // surprise that makes a checkbox untrustworthy.
        final beneath = _importableUnder(entry.path);
        final allSelected = beneath.every(
          (file) => _selected.contains(file.path),
        );
        for (final file in beneath) {
          if (allSelected) {
            _selected.remove(file.path);
          } else {
            _selected.add(file.path);
          }
        }
        return;
      }

      if (!_selected.remove(entry.path)) _selected.add(entry.path);
    });
  }

  List<ArchiveEntry> _importableUnder(String folder) =>
      (_listing?.filesUnder(folder) ?? const <ArchiveEntry>[])
          .where((file) => file.kind.isImportable)
          .toList();

  /// Everything importable in the archive, not merely in this folder.
  ///
  /// "Select all" that meant "all of the eleven rows you can currently see"
  /// would be a different promise depending on which folder you were standing
  /// in, which is not a promise at all.
  void _selectAll() {
    final all = _importableUnder('');
    setState(() {
      if (_selected.length == all.length) {
        _selected.clear();
      } else {
        _selected
          ..clear()
          ..addAll(all.map((file) => file.path));
      }
    });
  }

  // ---- Opening one entry ---------------------------------------------------

  /// Reads an entry, or hands it to another app.
  ///
  /// Extraction happens here rather than inside the reader so that a file which
  /// cannot be pulled out of the archive reports that *before* a reader opens
  /// on nothing.
  Future<void> _openEntry(ArchiveEntry entry) async {
    if (entry.isFolder) {
      _enter(entry);
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    final extracted = await ref.read(readArchiveEntryProvider)(
      archivePath: widget.args.path,
      entry: entry,
    );

    if (!mounted) return;

    final String path;
    switch (extracted) {
      case Failed(:final failure):
        messenger.showSnackBar(SnackBar(content: Text(failure.message)));
        return;
      case Success(value: final value):
        path = value;
    }

    // A nested archive, a spreadsheet, a video. DocuAI has nothing to show, so
    // the device's own chooser is offered rather than a dead row — and a nested
    // ZIP is deliberately among them: opening one in place would be unpacking
    // an archive out of an archive, which is where a bomb hides.
    if (!entry.kind.isReadable) {
      await _openElsewhere(entry, path);
      return;
    }

    await router.pushNamed<void>(
      AppRoutes.archiveEntryName,
      extra: FileReaderArgs(
        path: path,
        title: entry.name,
        kind: entry.kind,
        subtitle: widget.args.name,
      ),
    );
  }

  Future<void> _openElsewhere(ArchiveEntry entry, String path) async {
    final messenger = ScaffoldMessenger.of(context);

    final opened = await ref.read(externalOpenerProvider).open(path: path);
    if (!mounted || opened) return;

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '"${entry.name}" could not be opened. No app on this device '
          'offered to.',
        ),
      ),
    );
  }

  // ---- Importing -----------------------------------------------------------

  Future<void> _importSelected() async {
    final listing = _listing;
    if (listing == null || _selected.isEmpty || _importing) return;

    final entries = listing.files
        .where((file) => _selected.contains(file.path))
        .toList();

    final run = _ImportRun();

    setState(() {
      _run = run;
      _running = entries;
      _done.clear();
      _outcome = null;
      _progress = ToolProgress(done: 0, total: entries.length);
    });

    final result = await ref.read(importArchiveEntriesProvider)(
      archivePath: widget.args.path,
      entries: entries,
      isCancelled: () => run.cancelled,
      onProgress: (progress) {
        if (mounted && identical(_run, run)) {
          setState(() => _progress = progress);
        }
      },
      onEntryDone: (outcome) {
        if (mounted && identical(_run, run)) setState(() => _done.add(outcome));
      },
    );

    // Abandoned, or the screen is gone. Either way this result belongs to
    // nobody: Stop has already shown the user what happened.
    if (!mounted || !identical(_run, run)) return;

    setState(() {
      _run = null;
      _progress = null;
      _selected.clear();

      switch (result) {
        case Success(:final value):
          _outcome = value;
        case Failed(:final failure):
          // Still a report rather than a snackbar, so a run that produced
          // nothing says why on a screen the user can read at their own pace.
          _outcome = ArchiveImportOutcome(
            entries: <ArchiveImportEntryOutcome>[
              for (final entry in entries)
                ArchiveImportEntryOutcome(
                  name: entry.name,
                  path: entry.path,
                  status: ArchiveImportStatus.unreadable,
                  reason: failure.message,
                ),
            ],
          );
      }
    });
  }

  /// Stops the running import at once.
  ///
  /// Everything here is synchronous on purpose. The old Stop awaited the run it
  /// was cancelling, which is why it hung; this one asks the run to stop, lets
  /// go of it, and puts a finished report on screen in the same frame.
  ///
  /// The report is built from what actually completed plus everything the run
  /// never reached, so it adds up to the number the user selected rather than
  /// trailing off at whatever the last callback happened to be.
  void _stopImport() {
    final run = _run;
    if (run == null) return;

    run.cancelled = true;

    final reported = _done.map((outcome) => outcome.path).toSet();

    setState(() {
      _run = null;
      _progress = null;
      _selected.clear();
      _outcome = ArchiveImportOutcome(
        cancelled: true,
        entries: <ArchiveImportEntryOutcome>[
          ..._done,
          for (final entry in _running)
            if (!reported.contains(entry.path))
              ArchiveImportEntryOutcome(
                name: entry.name,
                path: entry.path,
                status: ArchiveImportStatus.stopped,
                reason: 'You stopped the import before this file.',
              ),
        ],
      );
    });
  }

  /// Opens the one document an import produced, when it produced exactly one.
  ///
  /// Several are not opened: landing in a document the user did not single out
  /// would hide the other ten behind it.
  Future<void> _openImported(Document document) => GoRouter.of(context)
      .pushNamed<void>(
        AppRoutes.documentDetailName,
        pathParameters: <String, String>{'id': document.id},
      );

  // ---- Building ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final listing = _listing;

    return PopScope(
      // Back steps *out of a folder* before it leaves the archive. Without
      // this, three taps into a folder tree, Back throws away the whole
      // session — and reopening means going through the sending app again.
      //
      // Every state answers Back with something. It used to `return` during an
      // import, which is precisely how a user ends up force-closing the app
      // from Recents: a screen that will not leave and a button that does
      // nothing look identical to a crash.
      canPop: _folder.isEmpty && !_importing && _outcome == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Back during an import means Stop, and Stop is immediate.
        if (_importing) {
          _stopImport();
          return;
        }
        // Back from the report returns to the archive, which is still open.
        if (_outcome != null) {
          setState(() => _outcome = null);
          return;
        }
        _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.args.name, overflow: TextOverflow.ellipsis),
          actions: <Widget>[
            // Hidden while a report is up: the report is about a selection
            // that has already been acted on, and offering to select again
            // over the top of it invites a second import of the same files.
            if (listing != null &&
                !listing.isEmpty &&
                !_importing &&
                _outcome == null)
              TextButton(
                onPressed: _selectAll,
                child: Text(
                  _selected.length == _importableUnder('').length &&
                          _selected.isNotEmpty
                      ? 'Clear'
                      : 'Select all',
                ),
              ),
            AppSpacing.gapHorizontalSm,
          ],
        ),
        body: _body(listing),
        bottomNavigationBar: listing == null || _selected.isEmpty || _importing
            ? null
            : _ImportBar(
                count: _selected.length,
                onImport: _importSelected,
                onClear: () => setState(_selected.clear),
              ),
      ),
    );
  }

  Widget _body(ArchiveListing? listing) {
    if (_loading) {
      return const AppStateView.busy(
        title: 'Opening the archive…',
        message: 'Reading what is inside. Nothing is unpacked yet.',
      );
    }

    if (_failure case final failure?) {
      return AppStateView.problem(
        icon: Icons.folder_zip_outlined,
        title: 'Could not open this archive',
        message: failure.message,
        action: FilledButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Go back'),
        ),
      );
    }

    if (_importing) {
      return _Importing(progress: _progress, onStop: _stopImport);
    }

    if (_outcome case final outcome?) {
      return ArchiveImportReport(
        outcome: outcome,
        archiveName: widget.args.name,
        onOpen: _openImported,
        onDone: () => setState(() => _outcome = null),
      );
    }

    if (listing == null || listing.isEmpty) {
      return const AppStateView(
        icon: Icons.folder_off_outlined,
        title: 'This archive is empty',
        message: 'There are no files inside it that DocuAI can list.',
      );
    }

    final children = listing.childrenOf(_folder);

    return Column(
      children: <Widget>[
        _Summary(listing: listing),
        ArchivePathBar(
          // The name the user knows, not `listing.name`.
          //
          // The listing is named after the file it read, and that file is the
          // copy in DocuAI's cache — which carries a timestamp prefix so two
          // shares of the same archive cannot collide. On a real device the
          // root crumb read "1787226886527_folders.zip", which is an internal
          // detail wearing the place where the archive's own name belongs.
          archiveName: widget.args.name,
          folder: _folder,
          onGoTo: _goTo,
        ),
        const Divider(height: 1),
        Expanded(
          child: children.isEmpty
              ? const AppStateView(
                  icon: Icons.folder_open_outlined,
                  title: 'This folder is empty',
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(
                    bottom: AppSpacing.fabClearance,
                  ),
                  itemCount: children.length,
                  itemBuilder: (context, index) {
                    final entry = children[index];
                    return ArchiveEntryTile(
                      entry: entry,
                      selected: _isSelected(entry),
                      selectable: entry.isFolder
                          ? _importableUnder(entry.path).isNotEmpty
                          : entry.kind.isImportable,
                      onOpen: () => _openEntry(entry),
                      onToggle: () => _toggle(entry),
                    );
                  },
                ),
        ),
      ],
    );
  }

  bool _isSelected(ArchiveEntry entry) {
    if (!entry.isFolder) return _selected.contains(entry.path);

    final beneath = _importableUnder(entry.path);
    return beneath.isNotEmpty &&
        beneath.every((file) => _selected.contains(file.path));
  }
}

/// What the archive is: how many files, how big, and what was left out.
class _Summary extends StatelessWidget {
  const _Summary({required this.listing});

  final ArchiveListing listing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = listing.fileCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        0,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.folder_zip_outlined,
            size: 20,
            color: theme.colorScheme.primary,
          ),
          AppSpacing.gapHorizontalSm,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '$count ${count == 1 ? 'file' : 'files'} · '
                  '${formatBytes(listing.totalBytes)} unpacked',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  // The archive's own size beside the unpacked total, because
                  // the gap between them is the thing worth knowing before
                  // importing anything.
                  '${formatBytes(listing.archiveBytes)} as a ZIP',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                // Said before the user selects anything, because the rows
                // themselves cannot say it: a file DocuAI does not import
                // simply has no checkbox, and silence there reads as an
                // oversight rather than as a rule.
                if (listing.importableCount < listing.fileCount)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      'DocuAI can import ${listing.importableCount} of them. '
                      'The rest open in another app.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (listing.refusedEntries > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Text(
                      // Never silent. An archive listing ten of its eleven
                      // files without saying so is one the user will believe
                      // DocuAI failed to read.
                      '${listing.refusedEntries} '
                      '${listing.refusedEntries == 1 ? 'entry' : 'entries'} '
                      'left out because they were unsafe to open.',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The bar that appears once something is ticked.
class _ImportBar extends StatelessWidget {
  const _ImportBar({
    required this.count,
    required this.onImport,
    required this.onClear,
  });

  final int count;
  final VoidCallback onImport;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: <Widget>[
              TextButton(onPressed: onClear, child: const Text('Clear')),
              const Spacer(),
              FilledButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.library_add_outlined, size: 18),
                // Counted in the label, so the action names its own scope.
                label: Text(
                  'Import $count ${count == 1 ? 'file' : 'files'}',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The import, running.
///
/// Named and counted rather than spun, for the reason the merge screen gives:
/// importing eleven files is eleven waits, and a bar that says which file it is
/// on is the difference between slow and stuck.
///
/// There is no "finishing the current file…" state any more. That message was
/// true — the file was still rendering — but it was shown while the user could
/// do nothing at all, which made an honest sentence into a trap. Stop now takes
/// effect in the frame it is pressed, so there is nothing left to narrate.
class _Importing extends StatelessWidget {
  const _Importing({required this.progress, required this.onStop});

  final ToolProgress? progress;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final label = progress?.label ?? '';

    return AppStateView(
      tone: AppStateTone.busy,
      title: label.isEmpty ? 'Importing…' : 'Importing $label…',
      message: progress == null
          ? null
          : '${progress!.done} of ${progress!.total}',
      progress: progress?.fraction,
      action: OutlinedButton.icon(
        onPressed: onStop,
        icon: const Icon(Icons.stop_circle_outlined, size: 18),
        label: const Text('Stop'),
      ),
    );
  }
}

/// One import, and whether it has been called off.
///
/// An object rather than a boolean on the state, so that a run the screen has
/// let go of can be told to stop without the *next* run inheriting the
/// instruction. Identity is what distinguishes them.
class _ImportRun {
  bool cancelled = false;
}
