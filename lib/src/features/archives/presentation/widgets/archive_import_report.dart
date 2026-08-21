import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../documents/domain/entities/document.dart';
import '../../domain/usecases/import_archive_entries.dart';

/// What an import actually did, file by file.
///
/// This screen exists because of a report from a real device: seventeen files
/// selected, four in the library, and nothing anywhere saying what happened to
/// the other thirteen. The old answer was a snackbar — one sentence, five
/// seconds, gone before it was read, and it could only ever say "13 files could
/// not be read", which is not a reason.
///
/// So the rule this screen keeps is: **every file the user selected appears
/// here, with a reason if it is not in their library.** The counts add up. An
/// import that half worked is a normal outcome, not an error state, and the
/// user is owed the detail rather than a number.
class ArchiveImportReport extends StatelessWidget {
  const ArchiveImportReport({
    required this.outcome,
    required this.archiveName,
    required this.onDone,
    this.onOpen,
    super.key,
  });

  final ArchiveImportOutcome outcome;

  /// The archive these files came out of, so the report says what it is about.
  final String archiveName;

  /// Back to the archive listing.
  final VoidCallback onDone;

  /// Opens a document that was imported. Absent in tests that do not route.
  final Future<void> Function(Document document)? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final imported = outcome.imported;
    final missing = outcome.notImported;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.fabClearance,
      ),
      children: <Widget>[
        _Headline(outcome: outcome, archiveName: archiveName),
        AppSpacing.gapXl,

        if (imported.isNotEmpty) ...<Widget>[
          _GroupHeader(
            icon: Icons.check_circle_outline,
            colour: theme.colorScheme.primary,
            label: 'In your library',
            count: imported.length,
          ),
          for (final entry in imported)
            _Row(
              entry: entry,
              // Tappable, because the obvious next thought after "it worked"
              // is "show me".
              onTap: entry.document == null || onOpen == null
                  ? null
                  : () => onOpen!(entry.document!),
            ),
          AppSpacing.gapLg,
        ],

        if (missing.isNotEmpty) ...<Widget>[
          _GroupHeader(
            icon: Icons.remove_circle_outline,
            colour: theme.colorScheme.error,
            label: 'Not imported',
            count: missing.length,
          ),
          // Grouped by reason rather than listed flat: "DocuAI does not import
          // this kind of file" said once above four rows reads as a rule, and
          // said four times reads as four failures.
          for (final entry in missing) _Row(entry: entry),
          AppSpacing.gapLg,
        ],

        AppSpacing.gapMd,
        FilledButton(
          onPressed: onDone,
          child: Text(
            outcome.cancelled ? 'Back to the archive' : 'Done',
          ),
        ),
      ],
    );
  }
}

/// The one sentence, with the numbers in it.
class _Headline extends StatelessWidget {
  const _Headline({required this.outcome, required this.archiveName});

  final ArchiveImportOutcome outcome;
  final String archiveName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final total = outcome.entries.length;
    final done = outcome.importedCount;

    final (icon, colour, title) = switch (outcome) {
      _ when outcome.cancelled => (
        Icons.stop_circle_outlined,
        theme.colorScheme.tertiary,
        'Import stopped',
      ),
      _ when outcome.isComplete => (
        Icons.check_circle_outline,
        theme.colorScheme.primary,
        done == 1 ? 'One file imported' : 'All $total files imported',
      ),
      _ when done == 0 => (
        Icons.error_outline,
        theme.colorScheme.error,
        'Nothing was imported',
      ),
      _ => (
        Icons.info_outline,
        theme.colorScheme.tertiary,
        '$done of $total files imported',
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, color: colour),
            AppSpacing.gapHorizontalSm,
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        AppSpacing.gapSm,
        Text(
          outcome.cancelled
              ? 'You stopped this part way. What had already been imported was '
                    'kept — nothing was undone. Everything below is from '
                    '"$archiveName".'
              : 'From "$archiveName". Your original archive is unchanged.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.icon,
    required this.colour,
    required this.label,
    required this.count,
  });

  final IconData icon;
  final Color colour;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: colour),
          AppSpacing.gapHorizontalSm,
          Text(
            '$label · $count',
            style: theme.textTheme.labelLarge?.copyWith(
              color: colour,
              fontWeight: FontWeight.w700,
              letterSpacing: .4,
            ),
          ),
        ],
      ),
    );
  }
}

/// One file, and what became of it.
class _Row extends StatelessWidget {
  const _Row({required this.entry, this.onTap});

  final ArchiveImportEntryOutcome entry;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.card,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        entry.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      // The folder it came from, when it came from one. Two
                      // files called `bill.pdf` are told apart by nothing else.
                      if (entry.path.contains('/'))
                        Text(
                          entry.path.substring(
                            0,
                            entry.path.lastIndexOf('/'),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      if (entry.reason case final reason?) ...<Widget>[
                        AppSpacing.gapXs,
                        Text(
                          reason,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                AppSpacing.gapHorizontalSm,
                _StatusChip(status: entry.status),
                if (onTap != null) ...<Widget>[
                  AppSpacing.gapHorizontalXs,
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A word for the status, because a colour alone is not readable to everyone.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ArchiveImportStatus status;

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;

    final (label, foreground, background) = switch (status) {
      ArchiveImportStatus.imported => (
        'Imported',
        colours.onPrimaryContainer,
        colours.primaryContainer,
      ),
      ArchiveImportStatus.unsupported => (
        'Not supported',
        colours.onSurfaceVariant,
        colours.surfaceContainerHighest,
      ),
      ArchiveImportStatus.unreadable => (
        'Failed',
        colours.onErrorContainer,
        colours.errorContainer,
      ),
      ArchiveImportStatus.stopped => (
        'Stopped',
        colours.onTertiaryContainer,
        colours.tertiaryContainer,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.chip,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
