import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/storage/storage_paths.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../domain/entities/document.dart';
import '../../domain/entities/document_page.dart';
import '../providers/document_providers.dart';
import '../widgets/page_edit_actions.dart';

/// A document's pages, full screen.
///
/// Deliberately dark regardless of theme: a scanned page is nearly white, and
/// judging whether a capture is straight and legible is easier without a bright
/// surround competing with it. This is the one screen in the app that does not
/// follow the colour scheme, for the same reason a photo viewer does not.
class PageViewerScreen extends ConsumerStatefulWidget {
  const PageViewerScreen({
    required this.documentId,
    this.initialPage = 0,
    super.key,
  });

  final String documentId;
  final int initialPage;

  @override
  ConsumerState<PageViewerScreen> createState() => _PageViewerScreenState();
}

class _PageViewerScreenState extends ConsumerState<PageViewerScreen> {
  late final PageController _pages = PageController(
    initialPage: widget.initialPage,
  );
  late int _current = widget.initialPage;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final document = ref.watch(documentProvider(widget.documentId));

    return Theme(
      data: ThemeData.dark(useMaterial3: true),
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.black.withValues(alpha: .55),
          elevation: 0,
          title: document.value == null
              ? null
              : Text('Page ${_current + 1} of ${document.value!.pageCount}'),
          actions: [
            if (document.value != null && document.value!.hasPages)
              PageEditActions(
                document: document.value!,
                pageIndex: _current.clamp(0, document.value!.pageCount - 1),
              ),
          ],
        ),
        body: document.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => const AppEmptyState(
            icon: Icons.error_outline,
            title: 'Could not open this document',
          ),
          data: (value) => value == null || !value.hasPages
              ? const AppEmptyState(
                  icon: Icons.image_not_supported_outlined,
                  title: 'There are no pages to show',
                )
              : _Pages(
                  document: value,
                  controller: _pages,
                  onPageChanged: (index) => setState(() => _current = index),
                ),
        ),
      ),
    );
  }
}

class _Pages extends ConsumerWidget {
  const _Pages({
    required this.document,
    required this.controller,
    required this.onPageChanged,
  });

  final Document document;
  final PageController controller;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paths = ref.watch(storagePathsProvider);

    return PageView.builder(
      controller: controller,
      onPageChanged: onPageChanged,
      itemCount: document.pageCount,
      itemBuilder: (context, index) => _ZoomablePage(
        page: document.pages[index],
        absolutePath: paths.absolutePath(document.pages[index].imagePath),
      ),
    );
  }
}

class _ZoomablePage extends StatefulWidget {
  const _ZoomablePage({required this.page, required this.absolutePath});

  final DocumentPage page;
  final String absolutePath;

  @override
  State<_ZoomablePage> createState() => _ZoomablePageState();
}

class _ZoomablePageState extends State<_ZoomablePage> {
  final TransformationController _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  /// Double tap zooms in on the point tapped, and again to reset.
  ///
  /// Pinching works, but on a phone held one-handed it rarely does — and the
  /// first thing anyone does to a small photo of dense text is tap it.
  void _toggleZoom(TapDownDetails details) {
    if (_transform.value != Matrix4.identity()) {
      setState(() => _transform.value = Matrix4.identity());
      return;
    }

    const scale = 2.5;
    final position = details.localPosition;
    setState(() {
      _transform.value = Matrix4.identity()
        ..translateByDouble(
          -position.dx * (scale - 1),
          -position.dy * (scale - 1),
          0,
          1,
        )
        ..scaleByDouble(scale, scale, scale, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: _toggleZoom,
      // The handler lives on onDoubleTap so the details from onDoubleTapDown
      // are already recorded when it fires.
      onDoubleTap: () {},
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 6,
        // Panning past the edge is what lets a zoomed page be dragged around
        // rather than snapping back at the boundary.
        boundaryMargin: const EdgeInsets.all(48),
        child: Center(
          child: Image.file(
            File(widget.absolutePath),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const AppEmptyState(
              icon: Icons.broken_image_outlined,
              title: 'This page image is missing',
              message:
                  'The file was removed from storage. Replace the page to '
                  'capture it again.',
            ),
          ),
        ),
      ),
    );
  }
}
