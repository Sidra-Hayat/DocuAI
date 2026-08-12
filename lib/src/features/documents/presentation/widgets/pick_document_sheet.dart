import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../domain/entities/document.dart';
import '../providers/document_providers.dart';
import 'document_thumbnail.dart';

/// Asks which document a library-level tool should act on.
///
/// The tools on the library — export a PDF, read a document's text — are the
/// same actions the detail screen offers, reached from a screen that is not
/// about any one document. They need a subject, and the alternative to asking
/// for one is what the assistant used to do: tell the user to go and open a
/// document first, which is a screen refusing to carry out a request it could
/// have carried out.
///
/// Returns the chosen document, or null if the sheet was dismissed.
Future<Document?> pickDocument(
  BuildContext context, {
  required String title,
  required String emptyMessage,
  bool Function(Document document)? where,
}) {
  return showModalBottomSheet<Document>(
    context: context,
    isScrollControlled: true,
    builder: (context) => _PickDocumentSheet(
      title: title,
      emptyMessage: emptyMessage,
      where: where,
    ),
  );
}

class _PickDocumentSheet extends ConsumerWidget {
  const _PickDocumentSheet({
    required this.title,
    required this.emptyMessage,
    this.where,
  });

  final String title;
  final String emptyMessage;
  final bool Function(Document document)? where;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final all = ref.watch(documentsProvider).value ?? const <Document>[];
    final documents = where == null
        ? all
        : all.where(where!).toList(growable: false);

    return SafeArea(
      child: ConstrainedBox(
        // Bounded so a library of two hundred documents does not produce a
        // sheet the height of the screen with no way to see what is under it.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (documents.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.xl,
                ),
                child: Text(
                  emptyMessage,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                  itemCount: documents.length,
                  itemBuilder: (context, index) {
                    final document = documents[index];

                    return ListTile(
                      leading: DocumentThumbnail(
                        page: document.coverPage,
                        width: 36,
                        height: 46,
                        borderRadius: AppRadius.xs,
                      ),
                      title: Text(
                        document.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${document.pageCount} '
                        '${document.pageCount == 1 ? 'page' : 'pages'} · '
                        '${DateFormat.yMMMd().format(document.updatedAt)}',
                      ),
                      onTap: () => Navigator.of(context).pop(document),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
