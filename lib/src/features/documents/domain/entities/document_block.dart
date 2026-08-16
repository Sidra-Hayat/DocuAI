import '../../../../core/text/markup.dart';
import '../../../../core/text/markup_editing.dart';

/// One editable piece of a page: a run of text, or a picture.
///
/// **This is a view over `DocumentPage.text`, not a new way of storing it.**
/// A page is still one string in exactly the format it has always been, and
/// [parse] and [serialize] are the only things that know how to move between
/// that string and the list an editor can lay out. Nothing downstream changes
/// as a result: the Markup parser, the search index, the assistant, the PDF
/// composer and the Hive models all keep reading the same text they always did,
/// and a document written before this existed round-trips through here
/// unchanged.
///
/// That is the whole reason the editor could stop being a single `TextField`
/// without a migration. A picture cannot be drawn *inside* a text field — a
/// `WidgetSpan` occupies exactly one character while `![Image](a.jpg)` occupies
/// seventeen, and a span list whose length disagrees with the controller's text
/// desynchronises the caret from what is painted. Splitting the page into
/// blocks sidesteps that entirely: each run of text gets its own field, each
/// picture is an ordinary widget between them, and no field ever contains a
/// picture reference to mis-measure.
sealed class DocumentBlock {
  const DocumentBlock({required this.id});

  /// Stable for the lifetime of one editing session.
  ///
  /// Used as the widget key and to look up the controller that belongs to a
  /// block. Deliberately *not* persisted: it identifies a row on screen, and
  /// the page's text is the only thing that outlives the screen.
  final String id;
}

/// A run of ordinary text, in the page's own markup.
final class TextBlock extends DocumentBlock {
  const TextBlock({required super.id, required this.text});

  final String text;

  TextBlock withText(String value) => TextBlock(id: id, text: value);

  bool get isEmpty => text.isEmpty;
}

/// A picture, named by its file inside the document's own `inline/` folder.
final class ImageBlock extends DocumentBlock {
  const ImageBlock({required super.id, required this.imageName});

  /// The file's name, never a path — see `MarkupBlock.imageName`.
  final String imageName;

  ImageBlock withImage(String value) => ImageBlock(id: id, imageName: value);
}

/// Turns a page's text into blocks and back again.
abstract final class DocumentBlocks {
  /// Splits [pageText] into the rows an editor lays out.
  ///
  /// Consecutive non-picture lines become one [TextBlock], blank lines and all:
  /// a blank line separates paragraphs for the reader and for the passage
  /// extractor, so collapsing them here would change what the assistant quotes.
  ///
  /// A [TextBlock] is guaranteed before the first picture, after the last, and
  /// between any two — including empty ones. Without that there is nowhere to
  /// put the caret to type above an image that starts a page, and no way to get
  /// between two adjacent pictures. Empty ones are dropped again by
  /// [serialize], so they cost nothing in the stored text.
  static List<DocumentBlock> parse(String pageText, {required String Function() newId}) {
    final blocks = <DocumentBlock>[];
    final buffer = <String>[];

    void flushText() {
      blocks.add(TextBlock(id: newId(), text: buffer.join('\n')));
      buffer.clear();
    }

    for (final line in pageText.split('\n')) {
      final imageName = Markup.imageNameIn(line);

      if (imageName == null) {
        buffer.add(line);
        continue;
      }

      // A text block always precedes a picture, so there is somewhere to type.
      flushText();
      blocks.add(ImageBlock(id: newId(), imageName: imageName));
    }

    flushText();

    return List<DocumentBlock>.unmodifiable(blocks);
  }

  /// Joins blocks back into the one string a page stores.
  ///
  /// Empty text blocks disappear. They exist so the editor has a caret position
  /// beside every picture; writing them out would add a blank line to the page
  /// each time it was opened and closed, and a document that grows a line per
  /// visit is a document that drifts.
  ///
  /// The result is byte-identical to what [parse] was given, for any text that
  /// came out of this editor or out of any version of the app before it.
  static String serialize(List<DocumentBlock> blocks) {
    final parts = <String>[];

    for (final block in blocks) {
      switch (block) {
        case TextBlock(:final text):
          if (text.isEmpty) continue;
          parts.add(text);
        case ImageBlock(:final imageName):
          parts.add('![${MarkupEditing.imageLabel}]($imageName)');
      }
    }

    return parts.join('\n');
  }

  /// Every picture the blocks refer to, in order.
  static List<String> imageNames(List<DocumentBlock> blocks) => <String>[
    for (final block in blocks)
      if (block case ImageBlock(:final imageName)) imageName,
  ];
}
