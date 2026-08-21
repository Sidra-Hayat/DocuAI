import 'package:flutter/material.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../pdf_tools/domain/entities/pdf_tool_models.dart';
import '../../domain/entities/archive_entry.dart';

/// One row of the archive browser.
///
/// Two targets in one row, and keeping them apart is the whole job. The
/// checkbox selects for import; everything else opens the thing for reading.
/// They are different intentions — "I want this" and "what is this?" — and a
/// row where a stray tap does the wrong one of them is a row that fills the
/// library with files the user was only looking at.
class ArchiveEntryTile extends StatelessWidget {
  const ArchiveEntryTile({
    required this.entry,
    required this.selected,
    required this.selectable,
    required this.onOpen,
    required this.onToggle,
    super.key,
  });

  final ArchiveEntry entry;
  final bool selected;

  /// False for what the library cannot hold — a video, a nested archive, a
  /// folder with nothing importable in it. The row still opens; it simply has
  /// no tick, because offering one that produces nothing is worse than none.
  final bool selectable;

  final VoidCallback onOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      onTap: onOpen,
      leading: _EntryIcon(kind: entry.kind),
      title: Text(
        entry.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        _subtitle(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: entry.isFolder && !selectable
          ? const Icon(Icons.chevron_right)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (entry.isFolder) const Icon(Icons.chevron_right),
                if (selectable)
                  Checkbox(
                    value: selected,
                    onChanged: (_) => onToggle(),
                    // Named for what ticking it will do, not for the row it is
                    // in: a screen reader announcing "checkbox, invoice.pdf"
                    // has not said whether that means open or import.
                    semanticLabel: entry.isFolder
                        ? 'Select everything in ${entry.name}'
                        : 'Select ${entry.name} for import',
                  ),
              ],
            ),
    );
  }

  String _subtitle() {
    if (entry.isFolder) {
      final count = entry.childCount;
      return '$count ${count == 1 ? 'item' : 'items'} · '
          '${formatBytes(entry.sizeBytes)}';
    }

    final size = formatBytes(entry.sizeBytes);

    return switch (entry.kind) {
      ArchiveEntryKind.pdf => 'PDF · $size',
      ArchiveEntryKind.image => 'Picture · $size',
      ArchiveEntryKind.text => 'Text · $size',
      // Said, rather than left for the user to discover by tapping. A ZIP
      // inside a ZIP is not opened here on purpose.
      ArchiveEntryKind.archive => 'Archive · $size · opens in another app',
      _ => '$size · opens in another app',
    };
  }
}

/// The type badge.
///
/// Colour by kind, and only three colours: what DocuAI can read, what it can
/// step into, and what belongs to another app. A palette with one entry per
/// file extension would be decoration; this is the row's actual answer to
/// "what happens if I tap this?".
class _EntryIcon extends StatelessWidget {
  const _EntryIcon({required this.kind});

  final ArchiveEntryKind kind;

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;

    final (icon, foreground, background) = switch (kind) {
      ArchiveEntryKind.folder => (
        Icons.folder_outlined,
        colours.onSecondaryContainer,
        colours.secondaryContainer,
      ),
      ArchiveEntryKind.pdf => (
        Icons.picture_as_pdf_outlined,
        colours.onPrimaryContainer,
        colours.primaryContainer,
      ),
      ArchiveEntryKind.image => (
        Icons.image_outlined,
        colours.onPrimaryContainer,
        colours.primaryContainer,
      ),
      ArchiveEntryKind.text => (
        Icons.description_outlined,
        colours.onPrimaryContainer,
        colours.primaryContainer,
      ),
      ArchiveEntryKind.archive => (
        Icons.folder_zip_outlined,
        colours.onSurfaceVariant,
        colours.surfaceContainerHighest,
      ),
      ArchiveEntryKind.other => (
        Icons.insert_drive_file_outlined,
        colours.onSurfaceVariant,
        colours.surfaceContainerHighest,
      ),
    };

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.card,
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 20, color: foreground),
    );
  }
}
