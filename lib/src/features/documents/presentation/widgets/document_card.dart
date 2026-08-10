import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/document.dart';
import '../../domain/entities/document_page.dart';
import 'document_actions.dart';
import 'document_thumbnail.dart';

/// One document in the library.
///
/// A card rather than the list row this used to be. A row of the same tone as
/// the page behind it, separated by a hairline, is a database listing; a
/// document is an object, and the library is a shelf of them. The card also
/// buys the room the row never had — for where the document came from, whether
/// its text is readable yet, and whether it is a favourite — without any of it
/// being crushed into one truncated subtitle.
class DocumentCard extends ConsumerWidget {
  const DocumentCard({required this.document, super.key});

  final Document document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final status = _StatusLabel.of(document);

    return Card(
      child: InkWell(
        onTap: () => context.pushNamed(
          AppRoutes.documentDetailName,
          pathParameters: <String, String>{'id': document.id},
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DocumentThumbnail(
                page: document.coverPage,
                width: 56,
                height: 72,
                borderRadius: AppRadius.sm,
              ),
              AppSpacing.gapHorizontalMd,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      document.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        height: 1.25,
                      ),
                    ),
                    AppSpacing.gapXs,
                    _Meta(document: document),
                    if (status != null) ...<Widget>[AppSpacing.gapSm, status],
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  DocumentActionsButton(document: document),
                  // The one place gold appears in a list. A favourite is a mark
                  // the user made, not a state the app computed, and the brand
                  // accent is the right weight for it — loud enough to find by
                  // eye down a long library, quiet enough not to read as a
                  // warning.
                  if (document.isFavorite)
                    Icon(
                      Icons.star,
                      size: 18,
                      color: theme.colorScheme.tertiary,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where it came from, how big it is, when it last changed.
class _Meta extends StatelessWidget {
  const _Meta({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final (icon, origin) = switch (document.source) {
      DocumentSource.scanned => (Icons.document_scanner_outlined, 'Scanned'),
      DocumentSource.imported => (Icons.photo_library_outlined, 'Imported'),
      DocumentSource.created => (Icons.edit_note_outlined, 'Written'),
    };

    final pages =
        '${document.pageCount} ${document.pageCount == 1 ? 'page' : 'pages'}';

    return Row(
      children: <Widget>[
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        AppSpacing.gapHorizontalXs,
        Expanded(
          child: Text(
            '$origin · $pages · '
            '${DateFormat.yMMMd().format(document.updatedAt)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Shown only while something is outstanding.
///
/// A finished document says nothing about its text, because there is nothing to
/// say — a permanent "Text ready" badge on every row would be forty badges
/// reporting that nothing is wrong.
class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.label, required this.tone});

  final String label;
  final _StatusTone tone;

  static Widget? of(Document document) {
    return switch (document.ocrStatus) {
      OcrStatus.completed => null,
      OcrStatus.running => const _StatusLabel(
        label: 'Reading the text…',
        tone: _StatusTone.working,
      ),
      OcrStatus.pending => const _StatusLabel(
        label: 'Text not read yet',
        tone: _StatusTone.waiting,
      ),
      OcrStatus.failed => const _StatusLabel(
        label: 'Some text is missing',
        tone: _StatusTone.problem,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;

    final (background, foreground) = switch (tone) {
      _StatusTone.working => (
        colours.primaryContainer,
        colours.onPrimaryContainer,
      ),
      _StatusTone.waiting => (
        colours.surfaceContainerHighest,
        colours.onSurfaceVariant,
      ),
      _StatusTone.problem => (colours.errorContainer, colours.onErrorContainer),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.chip,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

enum _StatusTone { working, waiting, problem }
