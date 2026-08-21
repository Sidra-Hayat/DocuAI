import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_state_view.dart';
import '../../../documents/domain/entities/document.dart';
import '../../../documents/presentation/providers/document_providers.dart';
import '../../domain/entities/zip_build.dart';

/// Chooses documents from the library to put in an archive.
///
/// A sheet rather than a screen, and multi-select rather than one at a time.
/// Merge picks one PDF per trip because the platform picker it uses returns one
/// path; this reads the library directly, where the whole list is already in
/// memory, and making somebody open a picker eight times to archive eight
/// documents would be a limitation invented rather than inherited.
///
/// Documents already in the list are shown ticked and inert. Hiding them would
/// be worse: a user looking for "Invoice March" and not finding it has no way
/// to tell whether it is already added or whether the app has lost it.
Future<List<ZipSource>?> showPickDocumentsSheet(
  BuildContext context, {
  required Set<String> alreadyChosen,
}) {
  return showModalBottomSheet<List<ZipSource>>(
    context: context,
    showDragHandle: true,
    // Without this the sheet is capped at nine sixteenths of the screen, which
    // for a list is most of the list being unreachable.
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _PickDocumentsSheet(alreadyChosen: alreadyChosen),
  );
}

class _PickDocumentsSheet extends ConsumerStatefulWidget {
  const _PickDocumentsSheet({required this.alreadyChosen});

  /// Document ids already in the archive being built.
  final Set<String> alreadyChosen;

  @override
  ConsumerState<_PickDocumentsSheet> createState() =>
      _PickDocumentsSheetState();
}

class _PickDocumentsSheetState extends ConsumerState<_PickDocumentsSheet> {
  final Set<String> _selected = <String>{};

  void _toggle(Document document) {
    setState(() {
      if (!_selected.remove(document.id)) _selected.add(document.id);
    });
  }

  void _confirm(List<Document> documents) {
    final chosen = documents
        .where((document) => _selected.contains(document.id))
        .map(
          (document) => ZipSource.document(
            documentId: document.id,
            title: document.title,
            pageCount: document.pageCount,
          ),
        )
        .toList();

    Navigator.of(context).pop(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final documents = ref.watch(documentsProvider);

    // Held once rather than reached for twice. The list and the button below it
    // must agree on what "selected" refers to, and a second read of the
    // provider could in principle answer from a later emission — a document
    // deleted on another screen while this sheet is open.
    final loaded = documents.asData?.value ?? const <Document>[];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Add from your library',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_selected.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(_selected.clear),
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ),
          Expanded(
            child: documents.when(
              loading: () => const AppStateView.busy(title: 'Loading…'),
              error: (error, stackTrace) => const AppStateView.problem(
                title: 'Your library could not be read',
                icon: Icons.error_outline,
                message:
                    'The documents could not be loaded just now. Close this '
                    'and try again.',
              ),
              data: (all) {
                if (all.isEmpty) {
                  return const AppStateView(
                    icon: Icons.folder_open_outlined,
                    title: 'Nothing in your library yet',
                    message:
                        'Scan or import a document first, or add files from '
                        'this phone instead.',
                  );
                }

                return ListView.builder(
                  controller: controller,
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.fabClearance +
                        MediaQuery.paddingOf(context).bottom,
                  ),
                  itemCount: all.length,
                  itemBuilder: (context, index) {
                    final document = all[index];
                    final added = widget.alreadyChosen.contains(document.id);

                    return _DocumentRow(
                      document: document,
                      alreadyAdded: added,
                      selected: added || _selected.contains(document.id),
                      onTap: added ? null : () => _toggle(document),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selected.isEmpty ? null : () => _confirm(loaded),
                  child: Text(
                    _selected.isEmpty
                        ? 'Choose documents'
                        : 'Add ${_selected.length} '
                              '${_selected.length == 1 ? 'document' : 'documents'}',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.document,
    required this.alreadyAdded,
    required this.selected,
    required this.onTap,
  });

  final Document document;
  final bool alreadyAdded;
  final bool selected;
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
          child: Container(
            decoration: BoxDecoration(
              borderRadius: AppRadius.card,
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: <Widget>[
                Checkbox(
                  value: selected,
                  // Null disables it, which is what "already in the archive"
                  // should feel like: visibly accounted for, not available.
                  onChanged: onTap == null ? null : (_) => onTap!(),
                ),
                AppSpacing.gapHorizontalSm,
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        document.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        alreadyAdded
                            ? 'Already added'
                            : '${document.pageCount} '
                                  '${document.pageCount == 1 ? 'page' : 'pages'}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
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
