import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/storage_paths.dart';
import '../../domain/entities/document_page.dart';

/// Renders a page image from its stored relative path.
///
/// Resolution happens here, at the edge, rather than anywhere the path is
/// passed around: `StoragePaths` is the only thing that knows where the sandbox
/// currently lives, and a path that was absolute in storage would already be
/// wrong by the time it reached this widget.
///
/// The [errorBuilder] is not defensive padding — an image file genuinely can go
/// missing when Android reclaims space, and a broken thumbnail must not take
/// the whole library list down with it.
class DocumentThumbnail extends ConsumerWidget {
  const DocumentThumbnail({
    required this.page,
    this.width = 48,
    this.height = 64,
    this.borderRadius = 8,
    super.key,
  });

  final DocumentPage? page;
  final double width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final coverPage = page;

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: coverPage == null
            ? _Fallback(theme: theme)
            : Image.file(
                File(
                  ref
                      .watch(storagePathsProvider)
                      .absolutePath(coverPage.imagePath),
                ),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _Fallback(theme: theme),
              ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.description_outlined,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
