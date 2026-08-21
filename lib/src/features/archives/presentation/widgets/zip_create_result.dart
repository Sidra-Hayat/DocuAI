import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../pdf_tools/domain/entities/pdf_tool_models.dart';
import '../../domain/entities/zip_build.dart';

/// What a finished archive offers next.
///
/// Open and Share, laid out the way `PdfToolResult` lays out View and Share,
/// because an archive is now a library item like anything else those two
/// screens produce — and there are exactly two reasonable things to do with a
/// finished one: look inside it, or send it.
///
/// Still its own widget rather than `PdfToolResult`. That one's View goes to
/// the document detail screen and its Share offers a PDF or a Word file;
/// neither is right for a ZIP, which opens in the archive reader and is already
/// the file it would be shared as. What it also has that this needs is an
/// account of anything left out.
///
/// **Neither action is urgent, and that is the change.** This screen used to
/// warn that the archive was kept for a few hours and then removed, which made
/// Share the only thing worth doing before it vanished. The archive is saved
/// now, so the message says where it went instead.
class ZipCreateResult extends StatelessWidget {
  const ZipCreateResult({
    required this.outcome,
    required this.onOpen,
    required this.onShare,
    required this.onDone,
    this.sharing = false,
    super.key,
  });

  final ZipBuildOutcome outcome;

  /// Opens the archive in the reader the rest of the app uses.
  final VoidCallback onOpen;

  final VoidCallback onShare;

  /// Clears the result and returns the screen to its starting state.
  final VoidCallback onDone;

  /// True while the share sheet is being opened, which on a cold sheet can take
  /// long enough for somebody to press the button twice.
  final bool sharing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final complete = outcome.isComplete;

    final background = complete
        ? theme.colorScheme.secondaryContainer
        : theme.colorScheme.tertiaryContainer;
    final foreground = complete
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onTertiaryContainer;

    final saved = outcome.savedFraction;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        // The app draws edge to edge, so a scroll view that stops at its own
        // padding stops underneath the gesture bar.
        AppSpacing.xxl + MediaQuery.paddingOf(context).bottom,
      ),
      children: <Widget>[
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: background,
            borderRadius: AppRadius.surface,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(
                    complete ? Icons.check_circle_outline : Icons.info_outline,
                    color: foreground,
                  ),
                  AppSpacing.gapHorizontalSm,
                  Expanded(
                    child: Text(
                      'Archive saved',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              AppSpacing.gapMd,
              Text(
                '${outcome.entryCount} '
                '${outcome.entryCount == 1 ? 'file' : 'files'} · '
                '${formatBytes(outcome.sizeBytes)}',
                style: theme.textTheme.bodyLarge?.copyWith(color: foreground),
              ),
              AppSpacing.gapSm,
              Text(
                _detailFor(saved),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: foreground,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        if (outcome.skipped.isNotEmpty) ...<Widget>[
          AppSpacing.gapLg,
          _SkippedReport(skipped: outcome.skipped),
        ],
        AppSpacing.gapXl,
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                onPressed: onOpen,
                icon: const Icon(Icons.folder_zip_outlined, size: 18),
                label: const Text('Open'),
              ),
            ),
            AppSpacing.gapHorizontalSm,
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: sharing ? null : onShare,
                icon: sharing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share, size: 18),
                label: Text(sharing ? 'Opening…' : 'Share'),
              ),
            ),
          ],
        ),
        AppSpacing.gapMd,
        Text(
          'Your ZIP is saved in the DocuAI Library. You can open it or share it '
          'again later, and it stays until you delete it.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
        AppSpacing.gapMd,
        TextButton(
          // Pops nothing and pushes nothing: it clears the result and hands the
          // screen back, which the user leaves with Back like everywhere else.
          onPressed: onDone,
          child: const Text('Done'),
        ),
      ],
    );
  }

  String _detailFor(double saved) {
    final name = '"${outcome.fileName}"';

    if (saved <= 0.01) {
      // Said plainly rather than dressed up. Photographs and PDFs are already
      // compressed, so an archive of them is about the size of its contents —
      // which is normal, and not a sign that anything failed.
      return 'Saved as $name. It is about the same size as the files in it, '
          'because pictures and PDFs are already compressed. Everything you '
          'chose is unchanged.';
    }

    return 'Saved as $name — ${(saved * 100).round()}% smaller than the '
        '${formatBytes(outcome.sourceBytes)} that went into it. Everything you '
        'chose is unchanged.';
  }
}

/// What did not make it in, and why.
///
/// One row per thing, with the reason attached. The archive importer learned
/// this the hard way in the other direction: a user who chose twelve things and
/// received ten had nothing on screen accounting for the other two, and
/// concluded the app had lost them.
class _SkippedReport extends StatelessWidget {
  const _SkippedReport({required this.skipped});

  final List<ZipSkippedSource> skipped;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: AppRadius.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            skipped.length == 1
                ? 'One thing was left out'
                : '${skipped.length} things were left out',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          AppSpacing.gapSm,
          for (final entry in skipped) ...<Widget>[
            AppSpacing.gapXs,
            Text(
              entry.name,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              entry.reason,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
