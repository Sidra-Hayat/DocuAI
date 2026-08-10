import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/result.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_state_view.dart';
import '../../domain/entities/document.dart';
import '../../domain/entities/document_page.dart';
import '../providers/document_providers.dart';
import '../widgets/document_actions.dart';
import '../widgets/markup_editing_controller.dart';
import '../widgets/markup_toolbar.dart';

/// Writes one page of a document.
///
/// The same screen whether the page was typed from nothing or scanned and then
/// corrected — they are the same field, and treating them as two editors would
/// be two places for the same bug.
///
/// Three things make it read as a document editor rather than as a form. The
/// page says which page it is, always, instead of only on documents with more
/// than one. The title is here and can be changed from here, because renaming
/// the thing you are writing should not require going back to find it in a
/// list. And the text saves itself, so the button in the corner says Done —
/// what the user wants — rather than Save, which is a thing the user should not
/// have had to remember.
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
  final MarkupEditingController _editor = MarkupEditingController();
  final FocusNode _focus = FocusNode();

  /// How long the typing has to stop before the text is written.
  ///
  /// Every save re-indexes the page for search, which is what makes an edit
  /// findable straight away. A second of stillness turns a paragraph of typing
  /// into one index write instead of two hundred.
  static const Duration _autosaveDelay = Duration(seconds: 1);

  Timer? _autosave;

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
    // Cancelled, not left to fire: the notifier it would write through belongs
    // to a widget that is going away.
    _autosave?.cancel();
    _editor
      ..removeListener(_onChanged)
      ..dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (!_loaded) return;

    _autosave?.cancel();
    _autosave = Timer(_autosaveDelay, () {
      if (mounted) _save();
    });

    if (_dirty) return;
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
    _autosave?.cancel();
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

  Future<void> _done() async {
    final navigator = Navigator.of(context);
    final saved = await _save();
    if (saved && mounted && navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final document = ref.watch(documentProvider(widget.documentId));

    return document.when(
      loading: () =>
          const Scaffold(body: AppStateView.busy(title: 'Opening this page…')),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(),
        body: const AppStateView.problem(
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
            body: const AppStateView(
              icon: Icons.delete_outline,
              title: 'This page is no longer here',
              message: 'It was deleted while you had it open.',
            ),
          );
        }

        _load(page);
        return _buildEditor(context, value, page);
      },
    );
  }

  Widget _buildEditor(
    BuildContext context,
    Document document,
    DocumentPage page,
  ) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) => _leave(didPop),
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          // Tapping the title renames the document. The name of the thing you
          // are writing belongs on the screen where you are writing it, and
          // going back to a list to change it is a trip nobody should make.
          title: InkWell(
            borderRadius: AppRadius.small,
            onTap: () => showRenameDocumentDialog(context, ref, document),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    document.title,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    page.displayLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: <Widget>[
            _SaveStatus(saving: _saving, dirty: _dirty),
            AppSpacing.gapHorizontalSm,
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: FilledButton(
                onPressed: _saving ? null : _done,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(
                    72,
                    AppAccessibility.minTouchTarget - 8,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                ),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    // A writing column rather than the full width of a tablet.
                    // Long lines are hard to write in for the same reason they
                    // are hard to read.
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                        vertical: AppSpacing.md,
                      ),
                      child: TextField(
                        controller: _editor,
                        focusNode: _focus,
                        // Unbounded: this is a page of a document, and a fixed
                        // number of lines would put a scrollbar inside a
                        // scrollbar.
                        maxLines: null,
                        expands: true,
                        textAlignVertical: TextAlignVertical.top,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.zero,
                          hintText: 'Start writing…',
                          hintStyle: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.6,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Below the field and above the keyboard, which is where a
              // formatting bar is reached from without covering what is being
              // formatted.
              MarkupToolbar(controller: _editor),
            ],
          ),
        ),
      ),
    );
  }
}

/// Whether the work is safe, in as few words as that can be said.
///
/// Present at all times rather than only when something is wrong: the whole
/// promise of an editor that saves itself is that you can stop wondering, and a
/// promise kept silently is a promise nobody believes.
class _SaveStatus extends StatelessWidget {
  const _SaveStatus({required this.saving, required this.dirty});

  final bool saving;
  final bool dirty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = theme.colorScheme.onSurfaceVariant;

    final (icon, label) = switch ((saving, dirty)) {
      (true, _) => (null, 'Saving…'),
      (false, true) => (Icons.edit_outlined, 'Unsaved'),
      (false, false) => (Icons.check, 'Saved'),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon == null)
          SizedBox.square(
            dimension: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: colour),
          )
        else
          Icon(icon, size: 14, color: colour),
        AppSpacing.gapHorizontalXs,
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: colour)),
      ],
    );
  }
}
