import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/document.dart';
import '../../domain/usecases/update_document_tags.dart';
import '../providers/document_providers.dart';

/// Adds, removes and renames a document's tags.
///
/// A sheet rather than a dialog because tags wrap onto several rows and a
/// dialog would fight the keyboard for the space.
///
/// Normalisation is not reimplemented here. [UpdateDocumentTags.normalise] is
/// what will be stored, so it is also what is shown — the field previews the
/// exact string the use case will write, which is why that method is public.
Future<void> showEditTagsSheet(
  BuildContext context,
  WidgetRef ref,
  Document document,
) {
  // Read before the sheet is awaited: by the time it closes this row may be
  // gone, and reaching through a dead context is how a disposed dependency
  // gets touched.
  final update = ref.read(updateDocumentTagsProvider);
  final messenger = ScaffoldMessenger.of(context);

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: _EditTags(
        document: document,
        onSave: (tags) async {
          final result = await update(
            documentId: document.id,
            tags: tags,
          );

          result.fold(
            onSuccess: (_) {},
            onFailure: (failure) =>
                messenger.showSnackBar(SnackBar(content: Text(failure.message))),
          );
        },
      ),
    ),
  );
}

class _EditTags extends StatefulWidget {
  const _EditTags({required this.document, required this.onSave});

  final Document document;
  final Future<void> Function(List<String> tags) onSave;

  @override
  State<_EditTags> createState() => _EditTagsState();
}

/// Owns its controller.
///
/// The same reason the rename dialog does: a controller created beside
/// `showModalBottomSheet` is disposed when that future completes, which is when
/// the dismiss animation *starts* — leaving the sheet mounted around a
/// controller that has already been torn down.
class _EditTagsState extends State<_EditTags> {
  late final List<String> _tags = List<String>.of(widget.document.tags);
  final TextEditingController _input = TextEditingController();
  final FocusNode _focus = FocusNode();

  bool _saving = false;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _isFull => _tags.length >= UpdateDocumentTags.maxTagsPerDocument;

  /// Adds whatever is in the field.
  ///
  /// Normalised through the use case's own rules, so what appears as a chip is
  /// exactly what will be stored — "  Receipts " becomes `receipts`, and
  /// adding it twice does nothing the second time.
  void _add() {
    final candidate = UpdateDocumentTags.normalise(<String>[
      ..._tags,
      ..._input.text.split(','),
    ]);

    setState(() {
      _input.clear();
      if (candidate.length > UpdateDocumentTags.maxTagsPerDocument) return;
      _tags
        ..clear()
        ..addAll(candidate);
    });

    // Kept focused so several tags can be typed in a row without reaching for
    // the field again.
    _focus.requestFocus();
  }

  /// Lifts a tag back into the field.
  ///
  /// How renaming works, without a second editing path to keep in step: the
  /// old chip goes, its text lands in the field, and saving it again is an
  /// ordinary add.
  void _edit(String tag) {
    setState(() {
      _tags.remove(tag);
      _input.text = tag;
      _input.selection = TextSelection.collapsed(offset: tag.length);
    });
    _focus.requestFocus();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final navigator = Navigator.of(context);
    // Anything still in the field counts. Making the user press "add" before
    // "save" would silently discard a tag they had plainly finished typing.
    final tags = UpdateDocumentTags.normalise(<String>[
      ..._tags,
      ..._input.text.split(','),
    ]);

    await widget.onSave(tags);
    if (navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tags', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Tags are searchable. Tap one to rename it.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),

            if (_tags.isEmpty)
              Text(
                'No tags yet.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in _tags)
                    InputChip(
                      label: Text(tag),
                      onPressed: () => _edit(tag),
                      onDeleted: () => setState(() => _tags.remove(tag)),
                      deleteButtonTooltipMessage: 'Remove $tag',
                    ),
                ],
              ),

            const SizedBox(height: 16),
            TextField(
              controller: _input,
              focusNode: _focus,
              enabled: !_isFull,
              autofocus: true,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.none,
              maxLength: UpdateDocumentTags.maxTagLength,
              // Commas separate rather than being typed into a tag, which is
              // what anyone who has used a tag field expects.
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.deny(RegExp(r'\n')),
              ],
              onSubmitted: (_) => _add(),
              decoration: InputDecoration(
                labelText: _isFull ? 'Tag limit reached' : 'Add a tag',
                hintText: 'receipts, 2026',
                helperText: _isFull
                    ? 'Remove one to add another.'
                    : 'Separate several with commas.',
                counterText: '',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  tooltip: 'Add',
                  onPressed: _isFull ? null : _add,
                  icon: const Icon(Icons.add),
                ),
              ),
            ),

            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
