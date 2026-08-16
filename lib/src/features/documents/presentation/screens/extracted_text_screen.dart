
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_routes.dart';
import '../../../../core/text/markup.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_state_view.dart';
import '../../../assistant/domain/entities/assistant_intent.dart';
import '../../../assistant/presentation/screens/conversations_screen.dart';
import '../../../export/presentation/providers/export_controller.dart';
import '../../../ocr/presentation/providers/ocr_controller.dart';
import '../../domain/entities/document.dart';
import '../../domain/entities/document_page.dart';
import '../providers/document_providers.dart';
import '../providers/reader_providers.dart';
import '../widgets/markup_view.dart';
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
    // What was read, not how it is stored — a paste into a message should not
    // arrive carrying heading hashes and bold asterisks.
    await Clipboard.setData(ClipboardData(text: document.readableText));

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
      loading: () => const Scaffold(
        body: AppStateView.busy(title: 'Opening this document…'),
      ),
      error: (error, stackTrace) => Scaffold(
        appBar: AppBar(),
        body: const AppStateView.problem(
          icon: Icons.error_outline,
          title: 'Could not open this document',
        ),
      ),
      data: (value) => value == null
          ? Scaffold(
              appBar: AppBar(),
              body: const AppStateView(
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
            // Not "Extracted text". Extraction is what the app did; what the
            // user opened is the document's text.
            : const Text('Document text'),
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
          ? _Body(document: document, query: query.text, scroll: scroll)
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
        message:
            'Try a shorter word, or check the spelling as it appears on '
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
          child: _ExplainableSelection(
            document: document,
            child: ListView.builder(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 48),
              itemCount: blocks.length,
              itemBuilder: (context, index) {
                final block = blocks[index];
                final showPage =
                    index == 0 ||
                    blocks[index - 1].pageIndex != block.pageIndex;
                final page = document.pages.firstWhere(
                  (page) => page.index == block.pageIndex,
                );

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showPage)
                      _PageLabel(
                        document: document,
                        page: page,
                        editable: trimmed.isEmpty,
                      ),
                    if (block.imageName case final imageName?)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AppSpacing.sm,
                        ),
                        child: ReaderImage(
                          documentId: document.id,
                          imageName: imageName,
                        ),
                      )
                    else if (block.text.isEmpty)
                      _EmptyPageNote(scale: scale)
                    else
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
      if (!page.hasText) {
        // Shown rather than skipped, so a page recognition found nothing on
        // still gets a heading — and therefore an Edit button to write it by
        // hand. Only when nothing is being searched for: an empty page matches
        // no query and would be noise in a filtered view.
        if (query.isEmpty) {
          blocks.add(_Block(text: '', pageIndex: page.index, matches: 0));
        }
        continue;
      }

      for (final paragraph in _split(page.text)) {
        // A picture is not text and cannot match a search, so it is shown when
        // the page is being read and left out when it is being searched — the
        // same rule the empty-page note follows.
        if (paragraph.imageName != null) {
          if (query.isEmpty) {
            blocks.add(
              _Block(
                text: '',
                pageIndex: page.index,
                matches: 0,
                imageName: paragraph.imageName,
              ),
            );
          }
          continue;
        }

        final text = paragraph.text.trim();
        if (text.isEmpty) continue;

        // Counted against what the reader will *show* rather than against what
        // is stored. A line saved as `**Total** due` is read as "Total due", so
        // a search for "total due" has to match it — and the count under the
        // search field has to agree with the highlights the user can see.
        final shown = Markup.toPlainText(text);
        if (shown.trim().isEmpty) continue;

        if (query.isEmpty) {
          blocks.add(_Block(text: text, pageIndex: page.index, matches: 0));
          continue;
        }

        final matches = _countMatches(shown.toLowerCase(), lower);
        if (matches > 0) {
          blocks.add(
            _Block(text: text, pageIndex: page.index, matches: matches),
          );
        }
      }
    }

    return blocks;
  }

  /// Paragraphs, with any picture standing on its own.
  ///
  /// The reader has always split on blank lines. A picture is a line, and a
  /// line can sit inside a paragraph — so this splits those out rather than
  /// letting one disappear into the middle of a block of prose that then
  /// renders it as nothing.
  static List<({String text, String? imageName})> _split(String pageText) {
    final parts = <({String text, String? imageName})>[];

    for (final paragraph in pageText.split(RegExp(r'\n\s*\n'))) {
      final buffer = <String>[];

      void flush() {
        if (buffer.isEmpty) return;
        parts.add((text: buffer.join('\n'), imageName: null));
        buffer.clear();
      }

      for (final line in paragraph.split('\n')) {
        final name = Markup.imageNameIn(line);
        if (name == null) {
          buffer.add(line);
          continue;
        }
        flush();
        parts.add((text: '', imageName: name));
      }

      flush();
    }

    return parts;
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

/// Stands in for a page recognition found nothing on.
///
/// A heading with nothing under it reads as a rendering fault. Saying so — and
/// leaving the Edit button beside it — turns a dead end into the one place
/// where typing the text by hand is obviously possible.
class _EmptyPageNote extends StatelessWidget {
  const _EmptyPageNote({required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Text(
      'No text was found on this page.',
      style: theme.textTheme.bodyMedium?.copyWith(
        fontSize: (theme.textTheme.bodyMedium?.fontSize ?? 14) * scale,
        color: theme.colorScheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
    );
  }
}

/// Wraps the reader's text so a selection can be explained.
///
/// Stateful only to remember what is currently selected. `SelectionArea` hands
/// the text to `onSelectionChanged` and takes it away again when the toolbar
/// closes, so it has to be caught while it exists — reading it back off the
/// clipboard would work, and would also overwrite whatever the user had
/// copied.
class _ExplainableSelection extends StatefulWidget {
  const _ExplainableSelection({required this.document, required this.child});

  final Document document;
  final Widget child;

  @override
  State<_ExplainableSelection> createState() => _ExplainableSelectionState();
}

class _ExplainableSelectionState extends State<_ExplainableSelection> {
  String _selected = '';

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      onSelectionChanged: (content) =>
          _selected = content?.plainText.trim() ?? '',
      // Explain belongs on the selection itself: the reader is where someone
      // meets a passage they do not follow, and sending them to another screen
      // to paste it in would be asking them to find it twice.
      contextMenuBuilder: (context, state) =>
          AdaptiveTextSelectionToolbar.buttonItems(
            anchors: state.contextMenuAnchors,
            buttonItems: <ContextMenuButtonItem>[
              ...state.contextMenuButtonItems,
              ContextMenuButtonItem(
                label: 'Explain',
                onPressed: () {
                  final selected = _selected;
                  state.hideToolbar();
                  if (selected.isEmpty) return;

                  // The selection *is* the source, so it travels as one. It
                  // used to be pasted into the sentence "Explain: …" and read
                  // back out at the far end, which worked until the thing
                  // selected was short enough to look like a request.
                  openNewConversation(
                    context,
                    documentId: widget.document.id,
                    documentTitle: widget.document.title,
                    intent: ExplainSelection(selected),
                  );
                },
              ),
            ],
          ),
      child: widget.child,
    );
  }
}

class _Block {
  const _Block({
    required this.text,
    required this.pageIndex,
    required this.matches,
    this.imageName,
  });

  final String text;
  final int pageIndex;
  final int matches;

  /// Set when this block is a picture rather than words.
  final String? imageName;
}

/// The header above each page's text.
///
/// Carries the edit action rather than the app bar doing so: a document has one
/// body of text but several pages of it, and an action at the top could only
/// ever guess which one was meant.
class _PageLabel extends StatelessWidget {
  const _PageLabel({
    required this.document,
    required this.page,
    required this.editable,
  });

  final Document document;
  final DocumentPage page;

  /// False while a search is filtering the text — editing a filtered view
  /// would open the whole page and lose the thing being looked at.
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 14),
      child: Row(
        children: [
          Text(
            page.displayLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              letterSpacing: .8,
            ),
          ),
          if (page.hasEditedText) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: 'You corrected this text, so it is not re-read.',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.edit_outlined,
                    size: 12,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Edited',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: .8,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(width: 12),
          Expanded(child: Divider(color: theme.colorScheme.outlineVariant)),
          if (editable)
            TextButton.icon(
              onPressed: () => context.pushNamed(
                AppRoutes.editPageName,
                pathParameters: <String, String>{
                  'id': document.id,
                  'page': page.id,
                },
              ),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
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
        '$matches ${matches == 1 ? 'result' : 'results'} in $paragraphs '
        '${paragraphs == 1 ? 'place' : 'places'}',
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

/// What to offer when there is no text.
///
/// Re-reading is the obvious action and often the wrong one — a blurred scan
/// reads no better the second time. Typing it out is the answer that always
/// works, so it sits beside the retry rather than being buried.
class _NoTextActions extends StatelessWidget {
  const _NoTextActions({
    required this.document,
    required this.onReadAgain,
    this.readAgainLabel = 'Read again',
  });

  final Document document;
  final VoidCallback onReadAgain;
  final String readAgainLabel;

  @override
  Widget build(BuildContext context) {
    final page = document.pages.firstOrNull;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: [
        FilledButton.tonal(onPressed: onReadAgain, child: Text(readAgainLabel)),
        if (page != null)
          TextButton.icon(
            onPressed: () => context.pushNamed(
              AppRoutes.editPageName,
              pathParameters: <String, String>{
                'id': document.id,
                'page': page.id,
              },
            ),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Type it yourself'),
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
    void run({bool force = false}) =>
        ref.read(ocrControllerProvider.notifier).run(document.id, force: force);

    return switch (document.ocrStatus) {
      // Recognition ran and genuinely found nothing — a photograph of a
      // drawing or a blank page has nothing to read.
      OcrStatus.completed => AppEmptyState(
        icon: Icons.text_fields_outlined,
        title: 'No text on these pages',
        message:
            'Recognition finished but found nothing to read. Photos of '
            'drawings or blank pages have no text in them.',
        action: _NoTextActions(
          document: document,
          onReadAgain: () => run(force: true),
        ),
      ),
      OcrStatus.failed => AppEmptyState(
        icon: Icons.error_outline,
        title: 'The pages could not be read',
        message:
            'This usually means the images are too blurred, or were taken at '
            'too steep an angle.',
        action: _NoTextActions(
          document: document,
          onReadAgain: run,
          readAgainLabel: 'Try again',
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
          child: const Text('Read the text'),
        ),
      ),
    };
  }
}
