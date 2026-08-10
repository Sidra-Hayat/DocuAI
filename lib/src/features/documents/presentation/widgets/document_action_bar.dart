import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../export/presentation/providers/export_controller.dart';
import '../../../export/presentation/widgets/share_sheet.dart';
import '../../domain/entities/document.dart';
import 'document_edit_sheet.dart';

/// The three things you can do with a document.
///
/// Read, Edit, Share — the view / edit / export distinction, made a shape
/// rather than a sentence. This replaces four full-width rows with chevrons, an
/// export button and a summarise button, all of which used to sit on the detail
/// screen simultaneously: a document that offers eight equally weighted actions
/// at rest is a menu, and the reason the screen read as technical.
///
/// Everything secondary lives one tap deeper, behind Edit and Share.
class DocumentActionBar extends ConsumerWidget {
  const DocumentActionBar({
    required this.document,
    required this.pageIndex,
    super.key,
  });

  final Document document;

  /// The page the user is currently looking at.
  ///
  /// Passed in so Edit can act on *that* page. The old "Edit text" row opened
  /// whichever page happened to be the document's first written one, which on a
  /// scanned document of twelve pages was a guess.
  final int pageIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final export = ref.watch(exportControllerProvider);
    final sharing = export is ExportRunning && export.documentId == document.id;

    return Row(
      children: <Widget>[
        Expanded(
          child: _Action(
            icon: Icons.menu_book_outlined,
            label: 'Read',
            onPressed: () => context.pushNamed(
              AppRoutes.extractedTextName,
              pathParameters: <String, String>{'id': document.id},
            ),
          ),
        ),
        AppSpacing.gapHorizontalSm,
        Expanded(
          child: _Action(
            icon: Icons.edit_outlined,
            label: 'Edit',
            onPressed: () =>
                showDocumentEditSheet(context, ref, document, pageIndex),
          ),
        ),
        AppSpacing.gapHorizontalSm,
        Expanded(
          child: _Action(
            icon: Icons.ios_share,
            label: 'Share',
            busy: sharing,
            onPressed: document.hasPages
                ? () => showShareSheet(context, ref, document)
                : null,
          ),
        ),
      ],
    );
  }
}

/// One of the three. Icon over label, so all three stay side by side at the
/// largest text size the app allows rather than wrapping into a column.
class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null && !busy;

    final foreground = enabled
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: .5);

    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: AppRadius.card,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox.square(
                dimension: 22,
                child: busy
                    ? const CircularProgressIndicator(strokeWidth: 2)
                    : Icon(icon, size: 22, color: foreground),
              ),
              AppSpacing.gapXs,
              Text(
                busy ? 'Preparing…' : label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
