import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/text/markup_editing.dart';
import '../../domain/entities/document_block.dart';
import 'markup_editing_controller.dart';

/// Owns a page while it is being edited: its rows, their text controllers, and
/// which one the caret is in.
///
/// The editor is a list of blocks rather than one text field, because a picture
/// cannot be painted inside a `TextField` without breaking the invariant that a
/// span list measures the same as the text behind it. What it is *not* is a new
/// storage format — [load] and [serialize] move between this list and the
/// single string a page has always held, and a page with no pictures in it is
/// one text block that behaves exactly as the old editor did.
///
/// A `ChangeNotifier` rather than a widget's `State` so that the screen can ask
/// it for the serialised page on an autosave timer, and the toolbar can act on
/// whichever field the caret is in, without either of them reaching through a
/// widget tree.
class DocumentBlockController extends ChangeNotifier {
  DocumentBlockController({Uuid uuid = const Uuid()}) : _uuid = uuid;

  final Uuid _uuid;

  List<DocumentBlock> _blocks = const <DocumentBlock>[];

  /// One controller and one focus node per text block, keyed by block id.
  final Map<String, MarkupEditingController> _controllers =
      <String, MarkupEditingController>{};
  final Map<String, FocusNode> _focusNodes = <String, FocusNode>{};

  String? _focusedBlockId;

  /// Set while [load] is populating controllers, so their own change
  /// notifications are not mistaken for the user typing.
  bool _loading = false;

  /// True once anything has been edited since the last [markSaved].
  bool _dirty = false;

  List<DocumentBlock> get blocks => _blocks;

  bool get isDirty => _dirty;

  /// The block the caret is in, if any.
  String? get focusedBlockId => _focusedBlockId;

  /// The field the toolbar acts on — the focused one, or the last one focused.
  ///
  /// Falls back to the first text block so that pressing Bold on a freshly
  /// opened page does something rather than nothing.
  MarkupEditingController? get activeController {
    final id = _focusedBlockId ?? _firstTextBlockId;
    return id == null ? null : _controllers[id];
  }

  String? get _firstTextBlockId {
    for (final block in _blocks) {
      if (block is TextBlock) return block.id;
    }
    return null;
  }

  MarkupEditingController controllerFor(TextBlock block) =>
      _controllers[block.id]!;

  FocusNode focusNodeFor(TextBlock block) => _focusNodes[block.id]!;

  /// Replaces the whole document with the blocks [pageText] parses into.
  ///
  /// Called once when the page arrives. Calling it again on every rebuild would
  /// overwrite what is being typed, which is the reason the screen guards it
  /// with a loaded flag exactly as the single-field editor did.
  void load(String pageText) {
    _loading = true;

    _blocks = DocumentBlocks.parse(pageText, newId: _uuid.v4);
    _syncControllers();

    _loading = false;
    _dirty = false;
    notifyListeners();
  }

  /// The page as one string, in the format every other part of the app reads.
  String serialize() => DocumentBlocks.serialize(_readBack());

  void markSaved() {
    _dirty = false;
    notifyListeners();
  }

  /// Puts a picture where the caret is, splitting the text around it.
  ///
  /// The block the caret is in becomes up to three: what was before the caret,
  /// the picture, and what was after. That is the block-list equivalent of the
  /// old inserter's "put it on a line of its own", and it leaves the caret in
  /// the text *after* the picture so writing carries on where it left off.
  void insertImageAtCaret(String imageName) {
    final blocks = _readBack();

    // The block the toolbar would act on, which is the focused one or — before
    // anything has been tapped — the first. Using the same rule for both means
    // Bold and Image cannot disagree about which field the user is working in.
    final targetId = _focusedBlockId ?? _firstTextBlockId;

    final index = targetId == null
        ? -1
        : blocks.indexWhere((block) => block.id == targetId);

    if (index < 0) {
      // Nothing focused — a picture inserted straight after opening the page.
      // It goes at the end, with somewhere to type underneath it.
      _blocks = List<DocumentBlock>.unmodifiable(<DocumentBlock>[
        ...blocks,
        ImageBlock(id: _uuid.v4(), imageName: imageName),
        TextBlock(id: _uuid.v4(), text: ''),
      ]);
      _afterStructuralChange(focusLast: true);
      return;
    }

    final target = blocks[index] as TextBlock;
    final caret = _controllers[target.id]?.selection.baseOffset ?? -1;
    final at = caret < 0 ? target.text.length : caret.clamp(0, target.text.length);

    final before = target.text.substring(0, at);
    final after = target.text.substring(at);

    final tail = TextBlock(id: _uuid.v4(), text: after);

    _blocks = List<DocumentBlock>.unmodifiable(<DocumentBlock>[
      ...blocks.take(index),
      target.withText(before),
      ImageBlock(id: _uuid.v4(), imageName: imageName),
      tail,
      ...blocks.skip(index + 1),
    ]);

    _afterStructuralChange(focusBlockId: tail.id);
  }

  /// Swaps one picture for another — what an edit produces, since editing
  /// writes a new file rather than overwriting the old one.
  void replaceImage({required String blockId, required String imageName}) {
    _blocks = List<DocumentBlock>.unmodifiable(<DocumentBlock>[
      for (final block in _readBack())
        if (block.id == blockId && block is ImageBlock)
          block.withImage(imageName)
        else
          block,
    ]);

    _dirty = true;
    notifyListeners();
  }

  /// Removes a picture, and joins the text that was on either side of it.
  ///
  /// Merging matters: without it, deleting a picture from the middle of a
  /// paragraph leaves two fields where there was one, and the sentence that was
  /// split around it can never be made whole again.
  void removeImage(String blockId) {
    final blocks = _readBack();
    final index = blocks.indexWhere((block) => block.id == blockId);
    if (index < 0) return;

    final before = index > 0 ? blocks[index - 1] : null;
    final after = index + 1 < blocks.length ? blocks[index + 1] : null;

    final merged = <DocumentBlock>[];

    if (before is TextBlock && after is TextBlock) {
      merged
        ..addAll(blocks.take(index - 1))
        ..add(
          before.withText(
            // A newline only where both sides have something, so removing a
            // picture between two paragraphs does not fuse them into one line
            // and removing one from an empty page does not leave a stray break.
            before.text.isEmpty || after.text.isEmpty
                ? '${before.text}${after.text}'
                : '${before.text}\n${after.text}',
          ),
        )
        ..addAll(blocks.skip(index + 2));
    } else {
      merged
        ..addAll(blocks.take(index))
        ..addAll(blocks.skip(index + 1));
    }

    _blocks = List<DocumentBlock>.unmodifiable(
      merged.isEmpty
          ? <DocumentBlock>[TextBlock(id: _uuid.v4(), text: '')]
          : merged,
    );

    _afterStructuralChange(
      focusBlockId: before is TextBlock ? before.id : null,
    );
  }

  /// Applies a toolbar operation to the field the caret is in.
  ///
  /// Every formatting button still works on ordinary text in an ordinary
  /// controller — the block split changed which field is being edited, not what
  /// editing a field means.
  void applyToActive(TextEdit Function(TextEdit edit) operation) {
    activeController?.apply(operation);
  }

  // ---- internals ------------------------------------------------------------

  /// The blocks with each text block's current field contents folded back in.
  ///
  /// The controllers are the source of truth for text while the screen is open;
  /// `_blocks` carries the structure. Reading back before any structural change
  /// is what stops an insert or a delete reverting whatever was typed since the
  /// last one.
  List<DocumentBlock> _readBack() => <DocumentBlock>[
    for (final block in _blocks)
      if (block case final TextBlock text)
        text.withText(_controllers[text.id]?.text ?? text.text)
      else
        block,
  ];

  void _afterStructuralChange({String? focusBlockId, bool focusLast = false}) {
    _syncControllers();
    _dirty = true;
    notifyListeners();

    final target =
        focusBlockId ??
        (focusLast
            ? _blocks.whereType<TextBlock>().lastOrNull?.id
            : null);
    if (target == null) return;

    // After the frame that builds the new field: a focus node cannot take focus
    // until the widget owning it exists.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final node = _focusNodes[target];
      final controller = _controllers[target];
      if (node == null || controller == null || !node.hasListeners) return;

      controller.selection = TextSelection.collapsed(
        offset: controller.text.length,
      );
      node.requestFocus();
    });
  }

  /// Creates controllers for new text blocks and disposes those whose block has
  /// gone.
  void _syncControllers() {
    final live = <String>{
      for (final block in _blocks)
        if (block is TextBlock) block.id,
    };

    for (final id in _controllers.keys.toList()) {
      if (live.contains(id)) continue;
      _controllers.remove(id)?.dispose();
      _focusNodes.remove(id)?.dispose();
    }

    for (final block in _blocks) {
      if (block is! TextBlock) continue;

      final existing = _controllers[block.id];
      if (existing != null) {
        if (existing.text != block.text) existing.text = block.text;
        continue;
      }

      final controller = MarkupEditingController(text: block.text)
        ..addListener(_onTextChanged);
      final node = FocusNode()
        ..addListener(() => _onFocusChanged(block.id));

      _controllers[block.id] = controller;
      _focusNodes[block.id] = node;
    }
  }

  void _onTextChanged() {
    if (_loading) return;

    // The selection moving is not an edit, but the toolbar's active-format
    // readout depends on it, so listeners are told either way and only the
    // dirty flag distinguishes the two.
    if (!_dirty) _dirty = true;
    notifyListeners();
  }

  void _onFocusChanged(String blockId) {
    final node = _focusNodes[blockId];
    if (node == null) return;

    if (node.hasFocus) {
      _focusedBlockId = blockId;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller
        ..removeListener(_onTextChanged)
        ..dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _controllers.clear();
    _focusNodes.clear();
    super.dispose();
  }
}
