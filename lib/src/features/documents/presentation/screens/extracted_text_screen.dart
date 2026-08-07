import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/app_empty_state.dart';
import '../../../export/presentation/providers/export_controller.dart';
import '../../../ocr/presentation/providers/ocr_controller.dart';
import '../../domain/entities/document.dart';
import '../../domain/entities/document_page.dart';
import '../providers/document_providers.dart';
import '../providers/reader_providers.dart';
import '../widgets/reader_paragraph.dart';

/// A document's recognised text, on its own.
///
/// Split out of the detail screen because reading and reviewing are different
/// tasks: the detail screen is about the document as an object — its pages,
/// its title, its export — while this is about its contents. Giving the text a
/// route of its own also means it can own a reading width, a font size and a
/// search without any of that intruding on the page carousel.
///
/// This screen owns the whole text lifecycle, not just the finished state.
/// A "View Extracted Text" button that opened an empty screen while
/// recognition was still running would be worse than no button.
class ExtractedTextScreen extends ConsumerStatefulWidget {
  const ExtractedTextScreen({required this.documentId, super.key});

  final String documentId;

  @override
  ConsumerState<ExtractedTextScreen> createState() =>
      _ExtractedTextScreenState();
}

class _ExtractedTextScreenState extends ConsumerState<ExtractedTextScreen> {
  final TextEditingController _query = TextEditingController();
  final ScrollController _scroll = ScrollController();

  bool _searching = false;

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) _query.clear();
    });
  }

  Future<void> _copy(Document document) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: document.extractedText));

    messenger.showSnackBar(
      const SnackBar(content: Text('Text copied to the clipboard.')),
    );
  }

  Future<void> _share(Document document) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(shareExtractedTextProvider)(document);

    result.fold(
      onSuccess: (_) {},
      onFailure: (failure) =>
          messenger.showSnackBar(SnackBar(content: Text(failure.message))),
    );
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
          title: 'Could not open this document',
        ),
      ),
      data: (value) => value == null
          ? Scaffold(
              appBar: AppBar(),
              body: const AppEmptyState(
                icon: Icons.delete_outline,
                title: 'This document is no longer here',
              ),
            )
          : _Reader(
              document: value,
              query: _query,
              scroll: _scroll,
              searching: _searching,
              onToggleSearch: _toggleSearch,
              onQueryChanged: () => setState(() {}),
              onCopy: () => _copy(value),
              onShare: () => _share(value),
            ),
    );
  }
}

class _Reader extends ConsumerWidget {
  const _Reader({
    required this.document,
    required this.query,
    required this.scroll,
    required this.searching,
    required this.onToggleSearch,
    required this.onQueryChanged,
    required this.onCopy,
    required this.onShare,
  });

  final Document document;
  final TextEditingController query;
  final ScrollController scroll;
  final bool searching;
  final VoidCallback onToggleSearch;
  final VoidCallback onQueryChanged;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ocr = ref.watch(ocrControllerProvider);
    final running = ocr is OcrRunning && ocr.documentId == document.id;
    final hasText = document.hasText;

    return Scaffold(
      appBar: AppBar(
        title: searching
            ? TextField(
                controller: query,
                autofocus: true,
                onChanged: (_) => onQueryChanged(),
                decoration: const InputDecoration(
                  hintText: 'Search this text',
                  border: InputBorder.none,
                ),
              )
            : const Text('Extracted text'),
        actions: [
          if (hasText)
            IconButton(
              tooltip: searching ? 'Close search' : 'Search this text',
              onPressed: onToggleSearch,
              icon: Icon(searching ? Icons.close : Icons.search),
            ),
          if (hasText && !searching) ...[
            const _TextSizeButton(),
            IconButton(
              tooltip: 'Copy all text',
              onPressed: onCopy,
              icon: const Icon(Icons.copy_all_outlined),
            ),
            IconButton(
              tooltip: 'Share text',
              onPressed: onShare,
              icon: const Icon(Icons.ios_share),
            ),
          ],
        ],
      ),
      body: running
          ? _Recognising(state: ocr)
          : hasText
          ? _Body(
              document: document,
              query: query.text,
              scroll: scroll,
            )
          : _NothingToRead(document: document),
    );
  }
}

/// The document, paragraph by paragraph.
class _Body extends ConsumerWidget {
  const _Body({
    required this.document,
    required this.query,
    required this.scroll,
  });

  final Document document;
  final String query;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = ref.watch(readerTextScaleProvider);
    final trimmed = query.trim();
    final blocks = _blocks(document, trimmed);

    if (trimmed.isNotEmpty && blocks.isEmpty) {
      return AppEmptyState(
        icon: Icons.search_off_outlined,
        title: 'No matches for "$trimmed"',
        message: 'Try a shorter word, or check the spelling as it appears on '
            'the page.',
      );
    }

    final matchCount = blocks.fold<int>(0, (sum, block) => sum + block.matches);

    return Column(
      children: [
        if (trimmed.isNotEmpty)
          _MatchBar(matches: matchCount, paragraphs: blocks.length),
        Expanded(
          // Selection spans the whole document even though the list builds
          // lazily, which a per-paragraph SelectableText could not do.
          child: SelectionArea(
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
              itemCount: blocks.length,
              itemBuilder: (context, index) {
                final block = blocks[index];
                final showPage =
                    index == 0 || blocks[index - 1].pageIndex != block.pageIndex;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showPage) _PageLabel(pageIndex: block.pageIndex),
                    ReaderParagraph(
                      text: block.text,
                      query: trimmed,
                      scale: scale,
                    ),
                    SizedBox(height: 14 * scale),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  /// Splits the document into paragraphs, keeping the page each came from.
  ///
  /// When a query is present this also filters. Filtering rather than
  /// scrolling to matches is deliberate: jumping needs a resolved position for
  /// every paragraph, which a lazily-built list does not have, and a filtered
  /// view of a long document is easier to work through than a cursor stepping
  /// through it.
  static List<_Block> _blocks(Document document, String query) {
    final lower = query.toLowerCase();
    final blocks = <_Block>[];

    for (final page in document.pages) {
      if (!page.hasText) continue;

      for (final paragraph in page.text.split(RegExp(r'\n\s*\n'))) {
        final text = paragraph.trim();
        if (text.isEmpty) continue;

        if (query.isEmpty) {
          blocks.add(_Block(text: text, pageIndex: page.index, matches: 0));
          continue;
        }

        final matches = _countMatches(text.toLowerCase(), lower);
        if (matches > 0) {
          blocks.add(
            _Block(text: text, pageIndex: page.index, matches: matches),
          );
        }
      }
    }

    return blocks;
  }

  static int _countMatches(String haystack, String needle) {
    if (needle.isEmpty) return 0;

    var count = 0;
    var index = haystack.indexOf(needle);
    while (index >= 0) {
      count++;
      index = haystack.indexOf(needle, index + needle.length);
    }
    return count;
  }
}

class _Block {
  const _Block({
    required this.text,
    required this.pageIndex,
    required this.matches,
  });

  final String text;
  final int pageIndex;
  final int matches;
}

class _PageLabel extends StatelessWidget {
  const _PageLabel({required this.pageIndex});

  final int pageIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 14),
      child: Row(
        children: [
          Text(
            'Page ${pageIndex + 1}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              letterSpacing: .8,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
        ],
      ),
    );
  }
}

class _MatchBar extends StatelessWidget {
  const _MatchBar({required this.matches, required this.paragraphs});

  final int matches;
  final int paragraphs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Text(
        '$matches ${matches == 1 ? 'match' : 'matches'} in $paragraphs '
        '${paragraphs == 1 ? 'paragraph' : 'paragraphs'}',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TextSizeButton extends ConsumerWidget {
  const _TextSizeButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(readerTextScaleProvider.notifier);
    ref.watch(readerTextScaleProvider);

    return PopupMenuButton<void>(
      tooltip: 'Text size',
      icon: const Icon(Icons.format_size),
      itemBuilder: (context) => <PopupMenuEntry<void>>[
        PopupMenuItem<void>(
          enabled: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: 'Smaller',
                onPressed: controller.canReduce ? controller.reduce : null,
                icon: const Icon(Icons.remove),
              ),
              TextButton(
                onPressed: controller.reset,
                child: const Text('Reset'),
              ),
              IconButton(
                tooltip: 'Larger',
                onPressed: controller.canEnlarge ? controller.enlarge : null,
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Recognising extends StatelessWidget {
  const _Recognising({required this.state});

  final OcrRunning state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          LinearProgressIndicator(value: state.fraction),
          const SizedBox(height: 16),
          Text(
            state.total == 0
                ? 'Preparing…'
                : 'Reading page ${state.done} of ${state.total}…',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Every state in which there is nothing to read, each saying which one it is.
class _NothingToRead extends ConsumerWidget {
  const _NothingToRead({required this.document});

  final Document document;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void run({bool force = false}) => ref
        .read(ocrControllerProvider.notifier)
        .run(document.id, force: force);

    return switch (document.ocrStatus) {
      // Recognition ran and genuinely found nothing — a photograph of a
      // drawing or a blank page has nothing to read.
      OcrStatus.completed => AppEmptyState(
        icon: Icons.text_fields_outlined,
        title: 'No text on these pages',
        message:
            'Recognition finished but found nothing to read. Photos of '
            'drawings or blank pages have no text in them.',
        action: FilledButton.tonal(
          onPressed: () => run(force: true),
          child: const Text('Read again'),
        ),
      ),
      OcrStatus.failed => AppEmptyState(
        icon: Icons.error_outline,
        title: 'The pages could not be read',
        message:
            'This usually means the images are too blurred, or were taken at '
            'too steep an angle.',
        action: FilledButton.tonal(
          onPressed: run,
          child: const Text('Try again'),
        ),
      ),
      OcrStatus.pending || OcrStatus.running => AppEmptyState(
        icon: Icons.text_snippet_outlined,
        title: 'Not read yet',
        message:
            'Reading the text makes this document searchable and lets the '
            'assistant answer questions about it.',
        action: FilledButton(
          onPressed: run,
          child: const Text('Recognise text'),
        ),
      ),
    };
  }
}
