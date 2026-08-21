import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_state_view.dart';
import '../../../pdf_tools/domain/entities/pdf_tool_models.dart';
import '../../domain/entities/zip_build.dart';
import '../providers/zip_create_providers.dart';
import '../widgets/pick_documents_sheet.dart';
import '../widgets/zip_create_result.dart';

/// Builds a ZIP out of documents, files, or both.
///
/// The list is the whole interface, as it is on the merge screen — but without
/// the drag handles, because order is the user's entire input to a merge and
/// means nothing in an archive. A ZIP is a bag; every extractor sorts it its
/// own way, and offering a reordering that the recipient will not see would be
/// a control that does nothing.
///
/// Two ways in, side by side and equal: the library, and the phone. Neither is
/// the "real" one — archiving three scans with two downloads is the case this
/// screen exists for, and a design that made one of those a secondary action
/// would be picking a favourite.
class CreateZipScreen extends ConsumerStatefulWidget {
  const CreateZipScreen({super.key});

  @override
  ConsumerState<CreateZipScreen> createState() => _CreateZipScreenState();
}

class _CreateZipScreenState extends ConsumerState<CreateZipScreen>
    with WidgetsBindingObserver {
  final List<ZipSource> _sources = <ZipSource>[];
  late final TextEditingController _name;

  /// The build currently running, or null.
  ///
  /// A token rather than a bool, for the reason the archive browser sets out at
  /// length: Stop must not *wait* for the work it is cancelling. Compressing
  /// one entry is a synchronous call nothing in Dart can interrupt, so a Stop
  /// that awaited the result would leave the user on a progress bar with no way
  /// out. This one marks the token, lets go of the run, and shows the screen
  /// back in the same frame. Whatever that run does afterwards belongs to
  /// nobody: the `identical(_run, run)` checks throw its result away.
  ///
  /// The archive it was writing is deleted by the layer that owns it, on the
  /// way out, whether or not anybody is still listening.
  _BuildRun? _run;

  ToolProgress? _progress;

  /// Set once a build has produced an archive. While it is non-null the screen
  /// shows the result rather than the list.
  ZipBuildOutcome? _outcome;

  /// True from the moment Share is pressed until the sheet is out of the way.
  ///
  /// It exists only to stop a second tap while a cold share sheet is opening,
  /// which on a slow device takes long enough for somebody to press twice.
  ///
  /// **It is cleared on resume, not only when the share completes**, and that
  /// is the fix for a real dead end found on a device. `SharePlus.share`
  /// returns a future that resolves when the chooser reports back — and the
  /// chooser does not always report. Picking DocuAI itself out of its own share
  /// sheet is the case that exposed it: `MainActivity` is `singleTask`, so the
  /// chooser hands the archive straight back to this app rather than to a
  /// separate one, the future never resolves, and the button stayed disabled on
  /// "Opening…" for good. The user was left on a finished archive they could
  /// not send.
  ///
  /// Resume is the honest signal regardless of what the future does: if this
  /// screen is in front of the user again, the sheet is not.
  bool _sharing = false;

  bool get _busy => _run != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _name = TextEditingController(text: defaultArchiveName(DateTime.now()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // A screen that has gone must not leave an encoder running for it.
    _run?.cancelled = true;
    _name.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!_sharing || !mounted) return;
    setState(() => _sharing = false);
  }

  // ---- Choosing --------------------------------------------------------------

  Future<void> _addDocuments() async {
    final chosen = await showPickDocumentsSheet(
      context,
      alreadyChosen: <String>{
        for (final source in _sources)
          if (source.documentId != null) source.documentId!,
      },
    );

    if (chosen == null || chosen.isEmpty || !mounted) return;
    setState(() => _sources.addAll(chosen));
  }

  Future<void> _addFiles() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(pickZipFilesProvider)();

    if (!mounted) return;

    switch (result) {
      case Failed(:final failure):
        messenger.showSnackBar(SnackBar(content: Text(failure.message)));
      case Success(:final value):
        // Already in the list, by cache path. Picking the same file twice is
        // an easy thing to do across two trips to the picker, and a ZIP with
        // "statement.pdf" and "statement (2).pdf" in it — the same file — is
        // not what anybody meant.
        final existing = _sources.map((source) => source.id).toSet();
        final fresh = value.sources
            .where((source) => !existing.contains(source.id))
            .toList();

        if (fresh.isNotEmpty) setState(() => _sources.addAll(fresh));

        if (value.rejected > 0) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                value.rejected == 1
                    ? 'One file could not be read and was not added.'
                    : '${value.rejected} files could not be read and were '
                          'not added.',
              ),
            ),
          );
        }
    }
  }

  void _remove(ZipSource source) =>
      setState(() => _sources.removeWhere((item) => item.id == source.id));

  // ---- Building --------------------------------------------------------------

  Future<void> _create() async {
    if (_sources.isEmpty || _busy) return;

    final messenger = ScaffoldMessenger.of(context);
    final run = _BuildRun();

    setState(() {
      _run = run;
      _outcome = null;
      _progress = ToolProgress(done: 0, total: _sources.length * 2);
    });

    final result = await ref.read(createZipProvider)(
      sources: List<ZipSource>.unmodifiable(_sources),
      archiveName: _name.text,
      isCancelled: () => run.cancelled,
      onProgress: (progress) {
        if (mounted && identical(_run, run)) {
          setState(() => _progress = progress);
        }
      },
    );

    // Abandoned, or the screen is gone. Either way this result belongs to
    // nobody — Stop has already told the user what happened.
    if (!mounted || !identical(_run, run)) return;

    setState(() {
      _run = null;
      _progress = null;

      switch (result) {
        case Success(:final value):
          _outcome = value;
        case Failed(:final failure):
          // A build the user stopped is not a failure to report. They know.
          if (failure is ImportFailure && failure.cancelled) break;
          messenger.showSnackBar(SnackBar(content: Text(failure.message)));
      }
    });
  }

  /// Stops the running build at once.
  ///
  /// Synchronous throughout, on purpose. It asks the run to stop, lets go of
  /// it, and hands the screen back in the same frame — the user is never left
  /// watching a bar they have already dismissed.
  ///
  /// Nothing is left on disk. The archive is built under a temporary name in a
  /// directory belonging to this run, and both are removed by the builder on
  /// its way out; the finished name is only ever claimed by a complete archive.
  void _stop() {
    final run = _run;
    if (run == null) return;

    run.cancelled = true;

    setState(() {
      _run = null;
      _progress = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Stopped. No archive was created.'),
      ),
    );
  }

  Future<void> _share() async {
    final outcome = _outcome;
    if (outcome == null || _sharing) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sharing = true);

    final result = await ref.read(shareZipProvider)(outcome);

    if (!mounted) return;
    // May already have been cleared on resume — see [_sharing]. Setting it
    // again is harmless, and this is still the path that reports a share the
    // system refused outright.
    setState(() => _sharing = false);

    if (result case Failed(:final failure)) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  // ---- Rendering -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outcome = _outcome;

    if (outcome != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Archive ready')),
        body: ZipCreateResult(
          outcome: outcome,
          sharing: _sharing,
          onShare: _share,
          onDone: () => setState(() {
            _outcome = null;
            _sources.clear();
            _name.text = defaultArchiveName(DateTime.now());
          }),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create a ZIP'),
        actions: <Widget>[
          if (_sources.isNotEmpty && !_busy)
            TextButton(
              onPressed: () => setState(_sources.clear),
              child: const Text('Clear'),
            ),
          AppSpacing.gapHorizontalSm,
        ],
      ),
      body: _busy
          ? _Working(progress: _progress, onStop: _stop)
          : _sources.isEmpty
          ? AppStateView(
              icon: Icons.folder_zip_outlined,
              title: 'Choose what to put in the ZIP',
              message:
                  'Add documents from your library, files from this phone, or '
                  'both. DocuAI makes one .zip that any file manager or chat '
                  'app can open, and nothing you chose is changed.',
              action: FilledButton.icon(
                onPressed: _addDocuments,
                icon: const Icon(Icons.folder_outlined, size: 18),
                label: const Text('Add documents'),
              ),
              secondaryAction: OutlinedButton.icon(
                onPressed: _addFiles,
                icon: const Icon(Icons.attach_file, size: 18),
                label: const Text('Add files from phone'),
              ),
            )
          : Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: TextField(
                    controller: _name,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'Archive name',
                      // The extension is shown rather than typed. A user who
                      // types ".zip" themselves would otherwise get
                      // "invoices.zip.zip", and one who deletes it would get a
                      // file the recipient's phone does not recognise.
                      suffixText: '.zip',
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          '${_sources.length} '
                          '${_sources.length == 1 ? 'item' : 'items'}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _addDocuments,
                        icon: const Icon(Icons.folder_outlined, size: 18),
                        label: const Text('Documents'),
                      ),
                      TextButton.icon(
                        onPressed: _addFiles,
                        icon: const Icon(Icons.attach_file, size: 18),
                        label: const Text('Files'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.fabClearance +
                          MediaQuery.paddingOf(context).bottom,
                    ),
                    itemCount: _sources.length,
                    itemBuilder: (context, index) => _SourceTile(
                      key: ValueKey<String>(_sources[index].id),
                      source: _sources[index],
                      onRemove: () => _remove(_sources[index]),
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: _sources.isEmpty || _busy
          ? null
          : FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.folder_zip_outlined),
              label: Text(
                'Create ZIP of ${_sources.length} '
                '${_sources.length == 1 ? 'item' : 'items'}',
              ),
            ),
    );
  }
}

/// One chosen thing: what it is, what it is called, and how big.
class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.source,
    required this.onRemove,
    super.key,
  });

  final ZipSource source;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: AppRadius.card,
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.xs,
          AppSpacing.sm,
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: AppRadius.chip,
              ),
              child: Icon(
                // Says where it came from, which is the one thing the name
                // cannot: "Invoice" from the library and "Invoice.pdf" from
                // Downloads are different things with nearly the same label.
                source.isDocument
                    ? Icons.description_outlined
                    : Icons.insert_drive_file_outlined,
                size: 18,
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            AppSpacing.gapHorizontalMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    source.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _subtitleFor(source),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove "${source.name}"',
              onPressed: onRemove,
              icon: const Icon(Icons.close),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  static String _subtitleFor(ZipSource source) {
    if (source.isDocument) {
      final pages = source.pageCount ?? 0;
      return 'Document · $pages ${pages == 1 ? 'page' : 'pages'}';
    }
    return 'File · ${formatBytes(source.sizeBytes)}';
  }
}

/// What a build looks like while it runs.
///
/// Named and counted rather than spun, for the reason the merge screen gives:
/// a bar that says which file it is on is the difference between slow and
/// stuck. Stop takes effect in the frame it is pressed — there is no
/// "finishing the current file…" state, which was an honest sentence shown at
/// the one moment the user could do nothing about it.
class _Working extends StatelessWidget {
  const _Working({required this.progress, required this.onStop});

  final ToolProgress? progress;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final label = progress?.label ?? '';

    return AppStateView(
      tone: AppStateTone.busy,
      title: label.isEmpty ? 'Creating the archive…' : 'Adding $label…',
      message: 'Nothing is saved until it is finished.',
      progress: progress?.fraction,
      action: OutlinedButton.icon(
        onPressed: onStop,
        icon: const Icon(Icons.stop_circle_outlined, size: 18),
        label: const Text('Stop'),
      ),
    );
  }
}

/// One build, and whether it has been called off.
///
/// An object rather than a boolean on the state, so a run the screen has let go
/// of can be told to stop without the *next* run inheriting the instruction.
/// Identity is what distinguishes them.
class _BuildRun {
  bool cancelled = false;
}
