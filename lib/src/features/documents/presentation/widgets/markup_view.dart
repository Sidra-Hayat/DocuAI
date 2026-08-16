import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/storage_paths.dart';
import '../../../../core/text/markup.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// A page of markup, drawn.
///
/// **The gap this fills.** `Markup.parse` has always existed, the editor styled
/// its own text with it and the PDF composer drew from it, but nothing in
/// Flutter turned a `MarkupBlock` into a widget — so every screen that showed a
/// saved page handed the raw string to `Text` and the user read
///
/// ```
/// ## My heading
/// Some **bold** text
/// ![Image](1cb23234f061.jpg)
/// ```
///
/// This is that missing renderer, and it is deliberately the *only* one: the
/// reader, the full-screen page viewer and the document preview all come
/// through here, so there is one answer to "what does a quote look like"
/// rather than three that drift.
///
/// Nothing here parses. `Markup.parse` does that, exactly as it does for the
/// exporter — a second markup implementation is the thing this file exists to
/// avoid.
class MarkupView extends StatelessWidget {
  const MarkupView({
    required this.text,
    required this.documentId,
    this.query = '',
    this.scale = 1,
    this.maxBlocks,
    this.imageMaxHeight = ReaderImage.defaultMaxHeight,
    super.key,
  });

  /// The page's stored text, in the format every other part of the app reads.
  final String text;

  /// Which document's `inline/` folder a picture belongs to.
  final String documentId;

  /// Highlighted where it occurs. Empty when nothing is being searched for.
  final String query;

  /// The reader's own font scale, on top of whatever the system asked for.
  final double scale;

  /// Stops after this many blocks — for a preview that has to fit a card.
  final int? maxBlocks;

  /// How tall a picture may be drawn here.
  ///
  /// A surface with less room asks for less; it never asks for the picture to
  /// be left out. A document that contains a photograph has to *look* like one
  /// everywhere it is shown, and a caption saying a picture is here reads as a
  /// picture that has gone missing.
  final double imageMaxHeight;

  @override
  Widget build(BuildContext context) {
    final blocks = Markup.parse(text);
    final visible = maxBlocks == null
        ? blocks
        : blocks.take(maxBlocks!).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final block in visible)
          MarkupBlockView(
            block: block,
            documentId: documentId,
            query: query,
            scale: scale,
            imageMaxHeight: imageMaxHeight,
          ),
      ],
    );
  }
}

/// One block: a heading, a paragraph, a list item, a quotation, or a picture.
///
/// Mirrors `pdf_composer._blockWidget` deliberately — the same six shapes, the
/// same decisions about what each looks like — so that what a document is on
/// screen and what it is in an exported PDF are the same document.
class MarkupBlockView extends StatelessWidget {
  const MarkupBlockView({
    required this.block,
    required this.documentId,
    this.query = '',
    this.scale = 1,
    this.imageMaxHeight = ReaderImage.defaultMaxHeight,
    super.key,
  });

  final MarkupBlock block;
  final String documentId;
  final String query;
  final double scale;
  final double imageMaxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (block.kind == MarkupBlockKind.image) {
      final name = block.imageName;
      if (name == null) return const SizedBox.shrink();

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: ReaderImage(
          documentId: documentId,
          imageName: name,
          maxHeight: imageMaxHeight,
        ),
      );
    }

    final size = AppTypography.sizeFor(block.kind) * scale;
    final heading = AppTypography.isHeading(block.kind);

    final base = theme.textTheme.bodyLarge!.copyWith(
      fontSize: size,
      height: heading
          ? AppTypography.headingHeight
          : AppTypography.bodyHeight,
      fontWeight: heading ? FontWeight.w700 : null,
      color: block.kind == MarkupBlockKind.quote
          ? theme.colorScheme.onSurfaceVariant
          : null,
      fontStyle: block.kind == MarkupBlockKind.quote
          ? FontStyle.italic
          : null,
    );

    final content = _RichBlock(
      spans: block.spans,
      base: base,
      query: query,
      theme: theme,
    );

    return switch (block.kind) {
      MarkupBlockKind.bullet => _ListItem(marker: '•', base: base, child: content),
      MarkupBlockKind.numbered => _ListItem(
        marker: '${block.number ?? 1}.',
        base: base,
        child: content,
      ),
      MarkupBlockKind.quote => Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.only(left: AppSpacing.md),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: theme.colorScheme.outlineVariant, width: 3),
          ),
        ),
        child: content,
      ),
      _ => Padding(
        // Headings get air above them; a heading pressed against the paragraph
        // before it belongs to that paragraph rather than to what follows.
        padding: EdgeInsets.only(
          top: heading ? AppSpacing.md * scale : 0,
          bottom: AppSpacing.sm * scale,
        ),
        child: content,
      ),
    };
  }
}

/// The spans of one block, with any search match emphasised.
///
/// Renders a plain `Text` when the block is one unstyled run and nothing is
/// being searched for. That is not an optimisation for its own sake: a `Text`
/// with `data` is what `find.text` matches, what a screen reader reads as one
/// string, and what selection treats as a single run.
class _RichBlock extends StatelessWidget {
  const _RichBlock({
    required this.spans,
    required this.base,
    required this.query,
    required this.theme,
  });

  final List<MarkupSpan> spans;
  final TextStyle base;
  final String query;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    if (spans.isEmpty) return const SizedBox.shrink();

    if (query.isEmpty && spans.length == 1 && spans.single.isPlain) {
      return Text(spans.single.text, style: base);
    }

    final highlight = base.copyWith(
      backgroundColor: theme.colorScheme.primaryContainer,
      color: theme.colorScheme.onPrimaryContainer,
      fontWeight: FontWeight.w600,
    );

    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          for (final span in spans)
            ..._highlighted(
              span.text,
              base.copyWith(
                fontWeight: span.bold ? FontWeight.w700 : base.fontWeight,
                fontStyle: span.italic ? FontStyle.italic : base.fontStyle,
              ),
              highlight.copyWith(
                fontWeight: span.bold ? FontWeight.w700 : highlight.fontWeight,
                fontStyle: span.italic ? FontStyle.italic : highlight.fontStyle,
              ),
            ),
        ],
      ),
      style: base,
    );
  }

  /// Splits one run on every case-insensitive occurrence of the query.
  ///
  /// Offsets come from a lower-cased copy but every slice is taken from the
  /// original, so the text rendered is exactly the text stored — matching must
  /// never alter what the user sees.
  List<InlineSpan> _highlighted(
    String text,
    TextStyle normal,
    TextStyle emphasised,
  ) {
    if (query.isEmpty) return <InlineSpan>[TextSpan(text: text, style: normal)];

    final spans = <InlineSpan>[];
    final haystack = text.toLowerCase();
    final needle = query.toLowerCase();

    var start = 0;
    var index = haystack.indexOf(needle);

    while (index >= 0) {
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index), style: normal));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + needle.length),
          style: emphasised,
        ),
      );
      start = index + needle.length;
      index = haystack.indexOf(needle, start);
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: normal));
    }

    return spans;
  }
}

/// A bullet or a number, hung beside its item.
class _ListItem extends StatelessWidget {
  const _ListItem({
    required this.marker,
    required this.base,
    required this.child,
  });

  final String marker;
  final TextStyle base;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.sm,
        bottom: AppSpacing.xs,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            // Wide enough for "10." at the reader's largest size, so a long
            // list does not step sideways as it passes nine.
            width: 28 * (base.fontSize ?? AppTypography.body) / AppTypography.body,
            child: Text(marker, style: base),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// A picture in a document, read-only.
///
/// The reading counterpart of the editor's `InlineImageBlock`: the same file,
/// the same folder, without the tap target or the Edit badge. Neither shows the
/// file's name — the picture is the content, and the name is an implementation
/// detail the user never chose.
class ReaderImage extends ConsumerWidget {
  const ReaderImage({
    required this.documentId,
    required this.imageName,
    this.maxHeight = defaultMaxHeight,
    super.key,
  });

  /// As tall as a picture gets on a full page. Named because the preview asks
  /// for a smaller one, and two surfaces disagreeing about the default is how
  /// a picture ends up a different size in each of them.
  static const double defaultMaxHeight = 360;

  final String documentId;
  final String imageName;
  final double maxHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final path = ref
        .watch(storagePathsProvider)
        .inlineImagePath(documentId, imageName);

    return ClipRRect(
      borderRadius: AppRadius.card,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SizedBox(
          width: double.infinity,
          child: Image.file(
            File(path),
            fit: BoxFit.contain,
            key: ValueKey<String>(path),
            // Said rather than left blank. A picture that silently renders as
            // nothing looks like a document that lost it, which is exactly the
            // impression this app must never give.
            errorBuilder: (context, error, stackTrace) => Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: AppRadius.card,
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    Icons.broken_image_outlined,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  AppSpacing.gapHorizontalMd,
                  Expanded(
                    child: Text(
                      'This picture is no longer on this device.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
