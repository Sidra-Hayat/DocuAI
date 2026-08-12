import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_action_sheet.dart';
import 'new_document_sheet.dart';
import 'pick_document_sheet.dart';

/// The four ways a document gets into the library.
///
/// Given as a row of equal tiles rather than hidden behind one floating button.
/// The button was a single "+" that opened a sheet, which meant the answer to
/// "how do I scan something?" was two taps and a guess — and on the empty
/// library the three ways in were spelled out in the empty state and then
/// vanished the moment a document existed.
///
/// Four, and no more. Scanning, photos, files and writing are genuinely
/// different starting points; anything else worth doing happens *to* a document
/// that already exists, which is what the tools row below is for.
class LibraryPrimaryActions extends StatelessWidget {
  const LibraryPrimaryActions({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _PrimaryAction(
            icon: Icons.document_scanner_outlined,
            label: 'Scan',
            onPressed: () => context.pushNamed(AppRoutes.scanName),
          ),
        ),
        AppSpacing.gapHorizontalSm,
        Expanded(
          child: _PrimaryAction(
            icon: Icons.photo_library_outlined,
            label: 'Photos',
            onPressed: () => importPhotosAsDocument(context),
          ),
        ),
        AppSpacing.gapHorizontalSm,
        Expanded(
          child: _PrimaryAction(
            icon: Icons.folder_open_outlined,
            label: 'Files',
            onPressed: () => importFileAsDocument(context),
          ),
        ),
        AppSpacing.gapHorizontalSm,
        Expanded(
          child: _PrimaryAction(
            icon: Icons.edit_note_outlined,
            label: 'Write',
            onPressed: () => createAndOpenTextDocument(context),
          ),
        ),
      ],
    );
  }
}

/// One way in: a filled tile, icon over label.
///
/// Icon above label rather than beside it, so four of them fit across the
/// narrowest phone this app supports without any of the labels wrapping or
/// being cut. The label is the shortest true word for the action — "Photos",
/// not "Import photos" — because at this width a longer one would ellipsise
/// into something that says less than the icon does.
class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      child: Material(
        color: theme.colorScheme.primaryContainer,
        borderRadius: AppRadius.card,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  icon,
                  size: 24,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                AppSpacing.gapSm,
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What can be done *with* the documents already in the library.
///
/// Quieter than the row above on purpose — outlined rather than filled, teal
/// rather than indigo. These are not how you start; they are where you go once
/// you have something to work on, and giving them the same weight as Scan would
/// leave a new user with eight equally loud choices and no idea which is first.
class LibraryTools extends ConsumerWidget {
  const LibraryTools({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: <Widget>[
        Expanded(
          child: _Tool(
            icon: Icons.picture_as_pdf_outlined,
            label: 'PDF tools',
            onPressed: () => context.pushNamed(AppRoutes.pdfToolsName),
          ),
        ),
        AppSpacing.gapHorizontalSm,
        Expanded(
          child: _Tool(
            icon: Icons.text_snippet_outlined,
            label: 'Read text',
            onPressed: () => _readText(context),
          ),
        ),
        AppSpacing.gapHorizontalSm,
        Expanded(
          child: _Tool(
            icon: Icons.auto_awesome_outlined,
            label: 'Assistant',
            onPressed: () => context.goNamed(AppRoutes.assistantName),
          ),
        ),
        AppSpacing.gapHorizontalSm,
        Expanded(
          child: _Tool(
            icon: Icons.more_horiz,
            label: 'More',
            onPressed: () => _showMore(context),
          ),
        ),
      ],
    );
  }

  /// The things that did not earn a tile of their own.
  ///
  /// Deliberately *not* another route to "add a document" — that is already the
  /// row above and the button in the corner, and a third one would be the same
  /// offer made three times on one screen.
  void _showMore(BuildContext context) {
    showAppActionSheet(
      context,
      title: 'More',
      actions: <AppSheetAction>[
        AppSheetAction(
          icon: Icons.help_outline,
          label: 'How DocuAI works',
          description: 'A short guide to scanning, writing and asking',
          onSelected: () => context.pushNamed(AppRoutes.helpName),
        ),
        AppSheetAction(
          icon: Icons.search,
          label: 'Search your documents',
          description: 'Find words inside your pages, not just titles',
          onSelected: () => context.goNamed(AppRoutes.searchName),
        ),
        AppSheetAction(
          icon: Icons.settings_outlined,
          label: 'Settings',
          description: 'Appearance and privacy',
          onSelected: () => context.pushNamed(AppRoutes.settingsName),
        ),
      ],
    );
  }

  /// Picks a document and opens its text.
  ///
  /// Restricted to documents that have been read, because opening the reader on
  /// a document with no recognised text lands on an empty state — an offer that
  /// cannot be met is worse than one that is not made.
  Future<void> _readText(BuildContext context) async {
    final document = await pickDocument(
      context,
      title: 'Read which document?',
      emptyMessage:
          'None of your documents have had their text read yet. Open one and '
          'DocuAI will read it.',
      where: (document) => document.hasText,
    );

    if (document == null || !context.mounted) return;

    await context.pushNamed<void>(
      AppRoutes.extractedTextName,
      pathParameters: <String, String>{'id': document.id},
    );
  }
}

/// One secondary tool: outlined, teal, and the same size as its neighbours.
class _Tool extends StatelessWidget {
  const _Tool({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      child: Material(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: AppRadius.card,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: AppRadius.card,
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 22, color: theme.colorScheme.secondary),
                AppSpacing.gapSm,
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
