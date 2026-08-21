import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/storage_paths.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/page_image_decoding.dart';
import '../../domain/entities/document_block.dart';
import 'document_block_controller.dart';

/// A page as rows: text you can type in, pictures you can see.
///
/// The change this makes is the whole point of the feature. A picture used to
/// appear in the editor as `![Image](9c2e1f4a.jpg)` — a file name the user
/// never chose, standing in for something they had just inserted, with the
/// actual picture one tap away behind a View button. Here it is the picture.
class DocumentBlockEditor extends StatelessWidget {
  const DocumentBlockEditor({
    required this.controller,
    required this.documentId,
    required this.onEditImage,
    this.hintText = 'Start writing…',
    super.key,
  });

  final DocumentBlockController controller;
  final String documentId;

  /// Opens the picture editor for a block.
  final void Function(ImageBlock block) onEditImage;

  final String hintText;

  @override
  Widget build(BuildContext context) {
    // Deliberately not a `ConsumerWidget` reading `StoragePaths` here. Only a
    // picture needs to know where the sandbox is, and a page of plain text —
    // which is most pages — should not depend on storage having been wired up
    // just to lay out a text field.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final blocks = controller.blocks;

        return ListView.builder(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            // Edge-to-edge: without the inset the last line of a long page sits
            // under the gesture bar.
            AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
          ),
          itemCount: blocks.length,
          itemBuilder: (context, index) {
            final block = blocks[index];

            return switch (block) {
              TextBlock() => _TextRow(
                key: ValueKey<String>(block.id),
                controller: controller.controllerFor(block),
                focusNode: controller.focusNodeFor(block),
                // Only the first field carries the hint. Repeating "Start
                // writing…" under every picture would be the page telling a
                // user who has plainly started writing to start writing.
                hintText: index == 0 ? hintText : null,
              ),
              ImageBlock() => InlineImageBlock(
                key: ValueKey<String>(block.id),
                documentId: documentId,
                imageName: block.imageName,
                onTap: () => onEditImage(block),
              ),
            };
          },
        );
      },
    );
  }
}

/// One run of text.
///
/// An ordinary `TextField` with the markup controller the editor has always
/// used, so bold, headings, lists and quotes behave exactly as before. What
/// changed is that a field never contains a picture reference — which is what
/// makes the span-length invariant safe rather than something to be careful
/// about.
class _TextRow extends StatelessWidget {
  const _TextRow({
    required this.controller,
    required this.focusNode,
    this.hintText,
    super.key,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextField(
      controller: controller,
      focusNode: focusNode,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      textCapitalization: TextCapitalization.sentences,
      style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
      decoration: InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        hintText: hintText,
        hintStyle: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.6,
        ),
      ),
    );
  }
}

/// A picture in the document, at a size that suits a page.
///
/// Bounded rather than freely resizable. A picture in a written note is an
/// illustration: it should fit the column, keep its shape, and never take a
/// whole screen because the phone that took it had a tall sensor. Freeform
/// resizing is a document-layout feature and is deliberately not here.
class InlineImageBlock extends ConsumerWidget {
  const InlineImageBlock({
    required this.documentId,
    required this.imageName,
    required this.onTap,
    super.key,
  });

  final String documentId;

  /// The file's name inside the document's own `inline/` folder — never a path,
  /// and never shown to the user.
  final String imageName;

  final VoidCallback onTap;

  /// Ceiling on how much of the screen one picture may take.
  static const double maxHeight = 320;

  /// Floor, so the row exists before its file has been decoded.
  ///
  /// An `Image.file` reports no intrinsic size until the bytes come back, and a
  /// row with no height is a row that cannot be tapped and a page that jumps
  /// as each picture lands. Reserving space costs a moment of empty card and
  /// buys a layout that does not move under a thumb already reaching for it.
  static const double minHeight = 96;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // Resolved here rather than passed in, so that a page of plain text never
    // touches storage at all.
    final path = ref
        .watch(storagePathsProvider)
        .inlineImagePath(documentId, imageName);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Semantics(
        button: true,
        label: 'Picture in this document. Tap to edit.',
        child: Material(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: AppRadius.card,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Stack(
              children: <Widget>[
                ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: minHeight,
                    maxHeight: maxHeight,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: Image.file(
                      File(path),
                      fit: BoxFit.contain,
                      // Capped at [maxHeight] by the box above it.
                      cacheHeight: pageDecodeExtent(context, maxHeight),
                      // Keyed on the path so that editing a picture — which
                      // writes a new file and points the block at it — is shown
                      // rather than served from the decode cache of the old one.
                      key: ValueKey<String>(path),
                      errorBuilder: (context, error, stackTrace) =>
                          _Missing(theme: theme),
                    ),
                  ),
                ),
                // Says the picture is a thing you can act on. Without it there
                // is nothing to suggest tapping does anything at all.
                Positioned(
                  right: AppSpacing.sm,
                  bottom: AppSpacing.sm,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: .82),
                      borderRadius: AppRadius.chip,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.tune,
                            size: 14,
                            color: theme.colorScheme.onSurface,
                          ),
                          AppSpacing.gapHorizontalXs,
                          Text(
                            'Edit',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
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

/// Shown where a picture's file has gone.
///
/// Said rather than left blank: a picture that renders as nothing looks like a
/// document that lost it, which is the impression this app must never give.
class _Missing extends StatelessWidget {
  const _Missing({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      color: theme.colorScheme.errorContainer,
      child: Row(
        children: <Widget>[
          Icon(
            Icons.broken_image_outlined,
            color: theme.colorScheme.onErrorContainer,
          ),
          AppSpacing.gapHorizontalMd,
          Expanded(
            child: Text(
              'This picture is no longer on this device. Tap to remove it.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
