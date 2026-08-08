import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
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
              : Text(document.value!.title, overflow: TextOverflow.ellipsis),
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
        bottomNavigationBar: document.value == null || !document.value!.hasPages
            ? null
            : _PageNavigator(
                current: _current.clamp(0, document.value!.pageCount - 1),
                total: document.value!.pageCount,
                onGo: _goToPage,
              ),
      ),
    );
  }

  /// Animated rather than jumped, so the direction of travel is visible — the
  /// only cue that a tap moved a page rather than replacing the whole view.
  void _goToPage(int index) {
    if (!_pages.hasClients) return;
    _pages.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }
}

/// Previous, next, and where you are.
///
/// Swiping already works and is what most people will use. These exist because
/// swiping a page that is zoomed in does not — the gesture pans the image
/// instead — and because a document of thirty pages needs something that says
/// how far through it you are.
class _PageNavigator extends StatelessWidget {
  const _PageNavigator({
    required this.current,
    required this.total,
    required this.onGo,
  });

  final int current;
  final int total;
  final ValueChanged<int> onGo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ColoredBox(
      color: Colors.black.withValues(alpha: .55),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                tooltip: 'Previous page',
                onPressed: current > 0 ? () => onGo(current - 1) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                'Page ${current + 1} of $total',
                style: theme.textTheme.labelLarge,
              ),
              IconButton(
                tooltip: 'Next page',
                onPressed: current < total - 1 ? () => onGo(current + 1) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
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
      itemBuilder: (context, index) {
        final page = document.pages[index];
        final relative = page.imagePath;

        // A written page has nothing to zoom into. Pinch and pan exist to
        // inspect a photograph of small print; text reflows, so the reader's
        // own font size is the control that means anything for it.
        if (relative == null) {
          return _WrittenPage(document: document, page: page);
        }

        return _ZoomablePage(
          page: page,
          absolutePath: paths.absolutePath(relative),
        );
      },
    );
  }
}

/// A page that was written rather than captured.
///
/// Kept inside the viewer's dark surround rather than breaking out to the app
/// theme: this is one screen showing one document, and a written page that lit
/// up white between two scans would read as a different screen entirely.
class _WrittenPage extends StatelessWidget {
  const _WrittenPage({required this.document, required this.page});

  final Document document;
  final DocumentPage page;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!page.hasText) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.edit_note_outlined,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'This page is blank',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: () => _edit(context),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Write on it'),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SelectionArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 88, 24, 24),
                child: Text(
                  page.text,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.6),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 88),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _edit(context),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('Edit this page'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _edit(BuildContext context) => context.pushNamed(
    AppRoutes.editPageName,
    pathParameters: <String, String>{'id': document.id, 'page': page.id},
  );
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
    final path = widget.absolutePath;

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
            File(path),
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
