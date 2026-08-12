import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/storage/storage_paths.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_state_view.dart';
import '../../domain/entities/document.dart';
import '../../domain/entities/document_block.dart';
import '../../domain/entities/document_page.dart';
import '../providers/document_providers.dart';
import '../widgets/document_actions.dart';
import '../widgets/document_block_controller.dart';
import '../widgets/document_block_editor.dart';
import '../widgets/markup_toolbar.dart';
import 'image_editor_screen.dart';

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
  /// The page as rows: text fields with pictures between them.
  ///
  /// It used to be a single [MarkupEditingController] over the whole page,
  /// which is why a picture could only be shown as its own reference — a
  /// `WidgetSpan` measures one character and `![Image](a.jpg)` measures
  /// seventeen, and a span list that disagrees with its text desynchronises the
  /// caret from what is painted. The stored format is unchanged; only the
  /// editor's view of it is.
  final DocumentBlockController _editor = DocumentBlockController();

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
    super.dispose();
  }

  void _onChanged() {
    if (!_loaded) return;

    // The controller notifies on selection changes too, which the toolbar needs
    // for its active-format readout but which are not edits. Only a genuine
    // change arms the autosave.
    if (!_editor.isDirty) {
      setState(() {});
      return;
    }

    _autosave?.cancel();
    _autosave = Timer(_autosaveDelay, () {
      if (mounted) _save();
    });

    if (_dirty) return;
    setState(() => _dirty = true);
  }

  void _load(DocumentPage page) {
    if (_loaded) return;

    // Loaded *before* the flag is set. `load` notifies listeners synchronously
    // and this runs from `build`: with the flag already set, `_onChanged` would
    // treat the page's own stored text as an unsaved edit and call `setState`
    // mid-build.
    _editor.load(page.text);
    _loaded = true;

    // An empty page is one the user came here to write on, so put the caret in
    // it rather than making them tap first.
    if (page.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final first = _editor.blocks.whereType<TextBlock>().firstOrNull;
        if (first != null) _editor.focusNodeFor(first).requestFocus();
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
      // The blocks joined back into the one string a page has always stored.
      text: _editor.serialize(),
    );

    if (!mounted) return result is Success<Document>;

    if (result is Success<Document>) _editor.markSaved();

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

  /// Picks a picture, copies it into the document, and puts it at the caret.
  ///
  /// The copy happens before the reference is written, so the text never names
  /// a file that is not there yet. If the user backs out, nothing was written
  /// and the sweep on the next save removes the copy.
  Future<void> _insertImage() async {
    final messenger = ScaffoldMessenger.of(context);

    final result = await ref.read(insertInlineImageProvider)(
      documentId: widget.documentId,
    );

    switch (result) {
      case Success(:final value):
        // Splits the block the caret is in and puts the picture between the
        // halves, leaving the caret in the text underneath so writing carries
        // on where it left off.
        _editor.insertImageAtCaret(value);
      case Failed(:final failure):
        // Dismissing the picker is not a failure worth reporting — the user
        // knows they backed out.
        if (failure is ImportFailure && failure.cancelled) return;
        messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  /// Opens the picture editor for a block, and applies whatever comes back.
  ///
  /// The picture is the control: tapping it is how it is edited, which is the
  /// gesture people already have from every other app that puts pictures in
  /// documents. There is no separate selection step and no action bar.
  Future<void> _editImage(ImageBlock block) async {
    final messenger = ScaffoldMessenger.of(context);
    final paths = ref.read(storagePathsProvider);
    final path = paths.inlineImagePath(widget.documentId, block.imageName);

    if (!File(path).existsSync()) {
      // A picture whose file has gone cannot be edited, but it can be taken
      // out — which is the only useful thing left to do with it.
      _editor.removeImage(block.id);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'That picture was no longer on this device, so it has been removed '
            'from the page.',
          ),
        ),
      );
      return;
    }

    final outcome = await Navigator.of(context).push<ImageEditorResult>(
      MaterialPageRoute<ImageEditorResult>(
        builder: (context) => ImageEditorScreen(imagePath: path),
      ),
    );

    if (outcome == null || !mounted) return;

    switch (outcome) {
      case ImageEditDeleted():
        _editor.removeImage(block.id);

      case ImageEditApplied(:final edit):
        // Nothing to do, and nothing to re-encode for.
        if (edit.isIdentity) return;

        final edited = await ref.read(editInlineImageProvider)(
          documentId: widget.documentId,
          imageName: block.imageName,
          edit: edit,
        );

        if (!mounted) return;

        switch (edited) {
          case Success(:final value):
            // A new file rather than an overwrite — see [EditInlineImage].
            // Pointing the block at it is what makes the change appear, and
            // the next save sweeps the file it replaced.
            _editor.replaceImage(blockId: block.id, imageName: value);
          case Failed(:final failure):
            messenger.showSnackBar(SnackBar(content: Text(failure.message)));
        }
    }
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
                    child: DocumentBlockEditor(
                      controller: _editor,
                      documentId: widget.documentId,
                      onEditImage: _editImage,
                    ),
                  ),
                ),
              ),
              // The action bar that used to sit here is gone with the thing it
              // existed for. A picture was a line of text the caret could land
              // on but no tap could reach, so View and Remove had to live in a
              // bar above the toolbar; now the picture is a widget and tapping
              // it opens the editor, which is where both of those actions are.
              //
              // Below the fields and above the keyboard, which is where a
              // formatting bar is reached from without covering what is being
              // formatted.
              _Toolbar(controller: _editor, onInsertImage: _insertImage),
            ],
          ),
        ),
      ),
    );
  }
}

/// The formatting bar, pointed at whichever field the caret is in.
///
/// The toolbar itself is unchanged — every button is still a toggle over an
/// ordinary `MarkupEditingController`. What the block editor changed is that
/// there is now more than one such controller on screen, so this rebuilds as
/// focus moves and hands the toolbar the active one.
class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller, required this.onInsertImage});

  final DocumentBlockController controller;
  final Future<void> Function() onInsertImage;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final active = controller.activeController;

        // A page always parses to at least one text block, so this is
        // defensive rather than expected — and an absent toolbar is a better
        // failure than one whose buttons write into nothing.
        if (active == null) return const SizedBox.shrink();

        return MarkupToolbar(
          controller: active,
          onInsertImage: onInsertImage,
        );
      },
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

    // Saved is the resting state and should read as reassurance rather than as
    // a notice: it gets the quiet muted treatment. Unsaved is the one worth
    // catching an eye, so it takes a tinted ground — and "Saving…" sits between
    // them, because it is on its way to being fine.
    final (icon, label, foreground, background) = switch ((saving, dirty)) {
      (true, _) => (
        null,
        'Saving…',
        theme.colorScheme.onSurfaceVariant,
        Colors.transparent,
      ),
      (false, true) => (
        Icons.edit_outlined,
        'Unsaved',
        theme.colorScheme.onTertiaryContainer,
        theme.colorScheme.tertiaryContainer,
      ),
      (false, false) => (
        Icons.check_circle_outline,
        'Saved',
        theme.colorScheme.onSurfaceVariant,
        Colors.transparent,
      ),
    };

    return Semantics(
      liveRegion: true,
      label: label,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 3,
        ),
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadius.chip,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon == null)
              SizedBox.square(
                dimension: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            else
              Icon(icon, size: 14, color: foreground),
            AppSpacing.gapHorizontalXs,
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
