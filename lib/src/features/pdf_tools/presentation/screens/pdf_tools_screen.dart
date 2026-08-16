import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';

/// The three things this app can do to a PDF, on one screen.
///
/// A hub rather than three entries scattered around the library, because these
/// are the same kind of job — take documents you already have and produce a
/// file — and someone looking for one of them is looking for all three.
class PdfToolsScreen extends ConsumerWidget {
  const PdfToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('PDF tools')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          // Edge-to-edge: the scroll view has to add the system inset itself or
          // its last row sits under the gesture bar.
          AppSpacing.xxl + MediaQuery.paddingOf(context).bottom,
        ),
        children: <Widget>[
          Text(
            'Work with PDF files — including ones that are not in DocuAI yet. '
            'Everything runs on your phone, nothing is uploaded, and the files '
            'you choose are never changed.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          AppSpacing.gapXl,
          _Tool(
            icon: Icons.merge_outlined,
            title: 'Merge PDFs',
            description:
                'Join several PDFs into one document, in the order you choose.',
            onPressed: () => context.pushNamed(AppRoutes.mergePdfsName),
          ),
          AppSpacing.gapMd,
          _Tool(
            icon: Icons.compress_outlined,
            title: 'Compress a PDF',
            description:
                'Make a smaller copy, for email or an upload with a size '
                'limit. Works on any PDF on this phone.',
            onPressed: () => context.pushNamed(AppRoutes.compressPdfName),
          ),
          AppSpacing.gapXl,
          // Sharing used to be a third tile here, which picked a document from
          // the library and opened the same sheet the document screen already
          // offers — the same action, in two places, one of which made you
          // choose the document twice. It is gone, and this says where it
          // went rather than leaving a user to wonder whether it was removed.
          //
          // The line the two screens are divided on: PDF Tools works on
          // *files*, the document screen works on the document you have open.
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHigh,
              borderRadius: AppRadius.card,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.ios_share,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                AppSpacing.gapHorizontalMd,
                Expanded(
                  child: Text(
                    'Looking for Share as PDF or Word? Open the document you '
                    'want and use Share there — it already knows which '
                    'document you mean.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.45,
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

class _Tool extends StatelessWidget {
  const _Tool({
    required this.icon,
    required this.title,
    required this.description,
    required this.onPressed,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: AppRadius.surface,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: AppRadius.surface,
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: AppRadius.card,
                ),
                child: Icon(
                  icon,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              AppSpacing.gapHorizontalMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    AppSpacing.gapXs,
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
