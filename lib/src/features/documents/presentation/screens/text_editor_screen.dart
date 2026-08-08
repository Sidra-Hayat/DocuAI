import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/result.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../domain/entities/document.dart';
import '../../domain/entities/document_page.dart';
import '../providers/document_providers.dart';

/// Writes one page of a document.
///
/// The same screen whether the page was typed from nothing or scanned and then
/// corrected — they are the same field, and treating them as two editors would
/// be two places for the same bug.
class TextEditorScreen extends ConsumerStatefulWidget {
  const TextEditorScreen({
    required this.documentId,
    required this.pageId,
    super.key,
  });

  final String documentId;
  final String pageId;

  @override
  ConsumerState<TextEditorScreen> createState() => _TextEditorScreenState();
}

class _TextEditorScreenState extends ConsumerState<TextEditorScreen> {
  final TextEditingController _editor = TextEditingController();
  final FocusNode _focus = FocusNode();

  /// Set once the page's stored text has been put into the field.
  ///
  /// Without it the document stream would overwrite what is being typed on
  /// every rebuild — including the rebuild caused by saving.
  bool _loaded = false;

  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _editor.addListener(_onChanged);
  }

  @override
  void dispose() {
    _editor
      ..removeListener(_onChanged)
      ..dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!_loaded || _dirty) return;
    setState(() => _dirty = true);
  }

  void _load(DocumentPage page) {
    if (_loaded) return;

    // Assign *before* marking loaded. Setting `text` notifies listeners
    // synchronously, and this runs from `build`: with the flag already set,
    // `_onChanged` would treat the page's own stored text as an unsaved edit
    // and call `setState` mid-build.
    _editor.text = page.text;
    _loaded = true;

    // An empty page is one the user came here to write on, so put the caret in
    // it rather than making them tap first.
    if (page.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  /// Returns true when the text is safely stored.
  Future<bool> _save() async {
    if (!_dirty || _saving) return true;

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);

    final result = await ref.read(editPageTextProvider)(
      documentId: widget.documentId,
      pageId: widget.pageId,
      text: _editor.text,
    );

    if (!mounted) return result is Success<Document>;

    setState(() {
      _saving = false;
      _dirty = result is! Success<Document>;
    });

    if (result case Failed(:final failure)) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
      return false;
    }

    return true;
  }

  /// Saves before leaving rather than asking whether to.
  ///
  /// A note-taking screen that greets you with "discard changes?" on the way
  /// out has got the default wrong: the work is the point, and it is already
  /// safe to write. Leaving is only blocked when the save actually failed,
  /// because that is the one case where going back would lose something.
  Future<void> _leave(bool didPop) async {
    if (didPop) return;

    final navigator = Navigator.of(context);
    final saved = await _save();
    if (saved && mounted && navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final document = ref.watch(documentProvider(widget.documentId));

    return document.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(),
        body: const AppEmptyState(
          icon: Icons.error_outline,
          title: 'Could not open this page',
        ),
      ),
      data: (value) {
        final page = value?.pages
            .where((page) => page.id == widget.pageId)
            .firstOrNull;

        if (value == null || page == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const AppEmptyState(
              icon: Icons.delete_outline,
              title: 'This page is no longer here',
            ),
          );
        }

        _load(page);
        return _buildEditor(context, value, page);
      },
    );
  }

  Widget _buildEditor(BuildContext context, Document document, DocumentPage page) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) => _leave(didPop),
      child: Scaffold(
        appBar: AppBar(
          title: Text(document.title, overflow: TextOverflow.ellipsis),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              TextButton.icon(
                onPressed: _dirty ? _save : null,
                icon: const Icon(Icons.check, size: 18),
                label: Text(_dirty ? 'Save' : 'Saved'),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (document.pageCount > 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text(
                    page.displayLabel,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: TextField(
                    controller: _editor,
                    focusNode: _focus,
                    // Unbounded: this is a page of a document, and a fixed
                    // number of lines would put a scrollbar inside a scrollbar.
                    maxLines: null,
                    expands: true,
                    textAlignVertical: TextAlignVertical.top,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    style: theme.textTheme.bodyLarge?.copyWith(height: 1.55),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Start writing…',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
