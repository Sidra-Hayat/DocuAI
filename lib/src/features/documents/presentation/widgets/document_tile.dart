import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/router/app_routes.dart';
import '../../domain/entities/document.dart';
import '../../domain/entities/document_page.dart';
import 'document_actions.dart';
import 'document_thumbnail.dart';

/// One row in the document library.
class DocumentTile extends StatelessWidget {
  const DocumentTile({required this.document, super.key});

  final Document document;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: DocumentThumbnail(page: document.coverPage),
      title: Text(
        document.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        _subtitle(document),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (document.isFavorite)
            Icon(Icons.star, size: 18, color: theme.colorScheme.primary),
          DocumentActionsMenu(document: document),
        ],
      ),
      onTap: () => context.pushNamed(
        AppRoutes.documentDetailName,
        pathParameters: {'id': document.id},
      ),
    );
  }

  /// "3 pages · 4 Aug 2026 · Text pending" — the OCR part only appears while
  /// there is something outstanding, so a finished document reads cleanly.
  static String _subtitle(Document document) {
    final parts = <String>[
      '${document.pageCount} ${document.pageCount == 1 ? 'page' : 'pages'}',
      DateFormat.yMMMd().format(document.updatedAt),
    ];

    final status = switch (document.ocrStatus) {
      OcrStatus.pending => 'Text pending',
      OcrStatus.running => 'Reading text…',
      OcrStatus.failed => 'Text incomplete',
      OcrStatus.completed => null,
    };
    if (status != null) parts.add(status);

    return parts.join(' · ');
  }
}
