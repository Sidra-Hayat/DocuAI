import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_state_view.dart';
import '../../domain/entities/pdf_tool_models.dart';
import '../providers/pdf_tools_providers.dart';
import '../widgets/pdf_tool_result.dart';

/// Builds a merge: add PDFs, put them in order, join them.
///
/// The list is the whole interface. Merging is one of the few operations where
/// the *order* is the user's entire input, so the screen is a list they can
/// drag and delete from rather than a picker followed by a hopeful button.
class MergePdfsScreen extends ConsumerStatefulWidget {
  const MergePdfsScreen({super.key});

  @override
  ConsumerState<MergePdfsScreen> createState() => _MergePdfsScreenState();
}

class _MergePdfsScreenState extends ConsumerState<MergePdfsScreen> {
  final List<PdfSource> _sources = <PdfSource>[];

  bool _busy = false;
  ToolProgress? _progress;

  /// Set once a merge has produced a document. While it is non-null the screen
  /// shows the result rather than the list, which is what turns "merge" from a
  /// thing that navigates away into a thing that finishes.
  MergeOutcome? _outcome;

  /// Adds one PDF to the end of the list.
  ///
  /// One at a time because the platform picker this app uses returns one path.
  /// There is deliberately no cap on how many times this can be pressed — the
  /// only limit is the page budget the merge itself enforces, which is about
  /// what the device can hold rather than a number chosen to look safe.
  Future<void> _add() async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(pickPdfProvider)();

    switch (result) {
      case Success(:final value):
        if (_sources.any((source) => source.id == value.id)) {
          messenger.showSnackBar(
            SnackBar(content: Text('"${value.name}" is already in the list.')),
          );
          return;
        }
        setState(() => _sources.add(value));
      case Failed(:final failure):
        // Backing out of the picker is not a failure worth reporting.
        if (failure is ImportFailure && failure.cancelled) return;
        messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  void _remove(PdfSource source) =>
      setState(() => _sources.removeWhere((item) => item.id == source.id));

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      // ReorderableListView reports the index the row would land at *before*
      // it is removed, so moving downwards is off by one without this.
      final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
      _sources.insert(target, _sources.removeAt(oldIndex));
    });
  }

  /// Runs the merge and shows the result **on this screen**.
  ///
  /// It used to finish with
  ///
  /// ```dart
  /// router.pushReplacementNamed(AppRoutes.documentDetailName, ...)
  /// ```
  ///
  /// which is what produced the Navigator assertion on a real device. This
  /// screen is pushed on the *root* navigator; the document detail route is
  /// nested inside the documents branch of the `StatefulShellRoute`. Replacing
  /// one with the other leaves GoRouter building a page list that contains the
  /// `/documents` page twice — once as the shell branch already underneath, and
  /// once as the parent of the detail route being pushed on top — and
  /// `Navigator._debugCheckDuplicatedPageKeys` asserts on exactly that.
  ///
  /// The merge itself had already finished by then, which is why the document
  /// appeared in Recents while the screen showed an error.
  ///
  /// So the merge no longer navigates at all. The result is a state of this
  /// screen, and every route change from here is one the user asks for.
  Future<void> _merge() async {
    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _busy = true;
      _outcome = null;
      _progress = ToolProgress(done: 0, total: _sources.length);
    });

    final result = await ref.read(mergePdfsProvider)(
      sources: List<PdfSource>.unmodifiable(_sources),
      title: '',
      onProgress: (progress) {
        if (mounted) setState(() => _progress = progress);
      },
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _progress = null;
    });

    switch (result) {
      case Success(:final value):
        setState(() => _outcome = value);
      case Failed(:final failure):
        // Only a genuine failure says so. A merge that produced a document is
        // never reported as one that did not.
        messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canMerge = _sources.length >= 2 && !_busy;
    final outcome = _outcome;

    if (outcome != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Merged')),
        body: PdfToolResult(
          title: 'Merged into one document',
          summary:
              '${outcome.sourceCount} PDFs · ${outcome.pageCount} '
              '${outcome.pageCount == 1 ? 'page' : 'pages'}',
          detail: outcome.truncated
              ? 'Saved as "${outcome.document.title}". Only the first '
                    '${outcome.pageCount} pages fitted in one document, so any '
                    'pages after that were left out. Your original PDFs are '
                    'unchanged.'
              : 'Saved as "${outcome.document.title}". Your original PDFs are '
                    'unchanged.',
          tone: outcome.truncated
              ? PdfToolResultTone.caution
              : PdfToolResultTone.success,
          document: outcome.document,
          onDone: () => setState(() {
            _outcome = null;
            _sources.clear();
          }),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Merge PDFs'),
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
          ? _Working(progress: _progress)
          : Column(
              children: <Widget>[
                if (_sources.isEmpty)
                  Expanded(
                    child: AppStateView(
                      icon: Icons.merge_outlined,
                      title: 'Add the PDFs to join',
                      message:
                          'Add two or more PDFs, drag them into the order you '
                          'want, and DocuAI will join them into one document. '
                          'Your original files are not changed.',
                      action: FilledButton.icon(
                        onPressed: _add,
                        icon: const Icon(Icons.add),
                        label: const Text('Add a PDF'),
                      ),
                    ),
                  )
                else ...<Widget>[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.sm,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            '${_sources.length} '
                            '${_sources.length == 1 ? 'PDF' : 'PDFs'} · drag to '
                            'reorder',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _add,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add'),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        0,
                        AppSpacing.lg,
                        AppSpacing.fabClearance,
                      ),
                      itemCount: _sources.length,
                      onReorder: _reorder,
                      itemBuilder: (context, index) => _SourceTile(
                        // The key is what the reorder animation follows; an
                        // index would make every row change identity on a drag.
                        key: ValueKey<String>(_sources[index].id),
                        position: index + 1,
                        source: _sources[index],
                        onRemove: () => _remove(_sources[index]),
                      ),
                    ),
                  ),
                ],
              ],
            ),
      floatingActionButton: _sources.isEmpty || _busy
          ? null
          : FloatingActionButton.extended(
              onPressed: canMerge ? _merge : null,
              backgroundColor: canMerge
                  ? null
                  : theme.colorScheme.surfaceContainerHighest,
              icon: const Icon(Icons.merge),
              label: Text(
                canMerge ? 'Merge ${_sources.length} PDFs' : 'Add one more',
              ),
            ),
    );
  }
}

/// One chosen file: where it will sit, what it is called, how big it is.
class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.position,
    required this.source,
    required this.onRemove,
    super.key,
  });

  final int position;
  final PdfSource source;
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
            // The position in the merge, stated. It is the one thing the list
            // exists to control, and counting rows by eye is what a number is
            // for.
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                borderRadius: AppRadius.chip,
              ),
              child: Text(
                '$position',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                ),
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
                    formatBytes(source.sizeBytes),
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
            ReorderableDragStartListener(
              index: position - 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Icon(
                  Icons.drag_handle,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What a merge looks like while it runs.
///
/// Named rather than spun: rendering six files is six waits, and a bar that
/// says which file it is on is the difference between slow and stuck.
class _Working extends StatelessWidget {
  const _Working({required this.progress});

  final ToolProgress? progress;

  @override
  Widget build(BuildContext context) {
    final label = progress?.label ?? '';

    return AppStateView.busy(
      title: label.isEmpty ? 'Merging…' : 'Reading $label…',
      progress: progress?.fraction,
    );
  }
}

