import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../../core/theme/app_spacing.dart';
import '../../../../core/widgets/app_state_view.dart';
import '../../../import/data/datasources/document_text_extractor.dart';
import '../../../import/data/datasources/import_scratch.dart';
import '../../../import/data/datasources/pdf_page_rasterizer.dart';
import '../../domain/entities/archive_entry.dart';

/// What the reader was asked to open.
///
/// Carried as a route `extra` rather than encoded into the path. These are file
/// system paths into the app's own cache, and a URL that contains one is a URL
/// that outlives the file it names — a deep link somebody could restore into an
/// empty screen, or worse, into somebody else's leftovers.
class FileReaderArgs {
  const FileReaderArgs({
    required this.path,
    required this.title,
    required this.kind,
    this.subtitle,
  });

  final String path;

  /// What the file is called, shown in the bar.
  final String title;

  final ArchiveEntryKind kind;

  /// Where it came from — "Invoices 2026.zip", usually. Present so the reader
  /// says which archive the user is inside.
  final String? subtitle;
}

/// Reads one file. Imports nothing.
///
/// **The distinction this screen exists to hold.** Tapping a PDF inside an
/// archive shows it here, and when the user backs out, nothing has changed:
/// their library is what it was, the search index is what it was, and the only
/// trace is a file in a cache directory the next archive will clear. Importing
/// is a separate action with a separate button and a separate confirmation,
/// because "I want to see what this is" and "I want to keep this" are different
/// intentions and an app that cannot tell them apart fills the library with
/// things nobody meant to keep.
///
/// There is deliberately no editing, no rename, no favourite and no delete. All
/// of those act on a document, and this is not one.
class FileReaderScreen extends ConsumerStatefulWidget {
  const FileReaderScreen({required this.args, this.onImport, super.key});

  final FileReaderArgs args;

  /// Offered in the bar when the caller has somewhere to import to. Null when
  /// the file is already in the library's hands — a plain PDF opened through
  /// "Open with" has its own import affordance on the screen below.
  final Future<void> Function()? onImport;

  @override
  ConsumerState<FileReaderScreen> createState() => _FileReaderScreenState();
}

class _FileReaderScreenState extends ConsumerState<FileReaderScreen> {
  @override
  Widget build(BuildContext context) {
    final args = widget.args;

    // Dark, like the page viewer, and for the same reason: a scanned page or a
    // photograph is nearly white, and a bright surround competes with it. Text
    // is the exception — reading a page of words on black is not what anybody
    // wants — so it keeps the app's own theme.
    final isDark = args.kind != ArchiveEntryKind.text;

    final body = switch (args.kind) {
      ArchiveEntryKind.pdf => _PdfReader(path: args.path),
      ArchiveEntryKind.image => _ImageReader(path: args.path),
      ArchiveEntryKind.text => _TextReader(path: args.path),
      _ => const AppStateView.problem(
        icon: Icons.help_outline,
        title: 'DocuAI cannot show this kind of file',
        message: 'Go back and choose "Open with another app".',
      ),
    };

    final scaffold = Scaffold(
      backgroundColor: isDark ? Colors.black : null,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.black.withValues(alpha: .55) : null,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              args.title,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (args.subtitle case final subtitle?)
              Text(
                subtitle,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
          ],
        ),
        actions: <Widget>[
          if (widget.onImport case final import?)
            TextButton.icon(
              onPressed: import,
              icon: const Icon(Icons.library_add_outlined, size: 18),
              // Said as a verb with its object, because the whole point is that
              // reading did not do this.
              label: const Text('Add to library'),
            ),
          AppSpacing.gapHorizontalSm,
        ],
      ),
      body: body,
    );

    return isDark
        ? Theme(data: ThemeData.dark(useMaterial3: true), child: scaffold)
        : scaffold;
  }
}

/// Where rendered PDF pages are written while one is being read.
///
/// Its own folder, for the reason spelled out where it is prepared: the three
/// scratch directories this feature touches must not be able to empty each
/// other.
const String _readerScratch = 'docuai_archive_read';

/// A PDF, rendered page by page as the pages arrive.
///
/// Through `PdfPageRasterizer` — the same renderer an import uses, which is the
/// same renderer Android ships. Nothing is added to the library: the JPEGs land
/// in [_readerScratch], which the next file opened for reading empties.
///
/// Pages appear as they are rendered rather than all at the end. A forty-page
/// statement takes a while in total and almost no time to show its first page,
/// and the difference between those two numbers is the difference between a
/// reader and a loading screen.
class _PdfReader extends StatefulWidget {
  const _PdfReader({required this.path});

  final String path;

  @override
  State<_PdfReader> createState() => _PdfReaderState();
}

class _PdfReaderState extends State<_PdfReader> {
  final PageController _pages = PageController();
  final List<String> _rendered = <String>[];

  bool _busy = true;
  bool _cancelled = false;
  String? _error;
  int _current = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_render());
  }

  @override
  void dispose() {
    // Read by the rasteriser between pages. Without it, backing out of a long
    // PDF leaves it rendering to a screen that has gone.
    _cancelled = true;
    _pages.dispose();
    super.dispose();
  }

  Future<void> _render() async {
    try {
      final bytes = await File(widget.path).readAsBytes();

      // A directory of its own, emptied on entry. Not the importer's, because
      // an import started from the browser would delete the pages of the PDF
      // being read behind it; and not the archive's, because that holds the
      // extracted entry this is rendering *from*.
      final directory = await ImportScratch.prepare(name: _readerScratch);

      final pages = await const PdfPageRasterizer().rasterize(
        bytes: bytes,
        targetDirectory: directory,
        prefix: 'read_${p.basenameWithoutExtension(widget.path)}',
        isCancelled: () => _cancelled,
        onPage: (index, path) {
          if (!mounted || _cancelled) return;
          setState(() {
            _rendered.add(path);
            _total = _rendered.length;
          });
        },
      );

      if (!mounted || _cancelled) return;

      setState(() {
        _busy = false;
        _total = pages.length;
        if (pages.isEmpty) {
          _error =
              'That PDF could not be opened. It may be damaged, or locked '
              'with a password.';
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'That PDF could not be opened.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error case final message?) {
      return AppStateView.problem(
        icon: Icons.picture_as_pdf_outlined,
        title: 'Could not open this PDF',
        message: message,
      );
    }

    if (_rendered.isEmpty) {
      return const AppStateView.busy(
        title: 'Opening the PDF…',
        message: 'The first page appears as soon as it is ready.',
      );
    }

    return Column(
      children: <Widget>[
        Expanded(
          child: PageView.builder(
            controller: _pages,
            itemCount: _rendered.length,
            onPageChanged: (index) => setState(() => _current = index),
            itemBuilder: (context, index) =>
                _ZoomableImage(path: _rendered[index]),
          ),
        ),
        _PageCounter(
          current: _current,
          total: _total,
          // Still arriving. Said plainly rather than shown as a stuck counter:
          // "3 of 5" on a document with forty pages is a lie the user would
          // only find out about by swiping into nothing.
          stillRendering: _busy,
        ),
      ],
    );
  }
}

/// Where in the document, and whether there is more of it coming.
class _PageCounter extends StatelessWidget {
  const _PageCounter({
    required this.current,
    required this.total,
    required this.stillRendering,
  });

  final int current;
  final int total;
  final bool stillRendering;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ColoredBox(
      color: Colors.black.withValues(alpha: .62),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (stillRendering) ...<Widget>[
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                AppSpacing.gapHorizontalSm,
              ],
              Text(
                stillRendering
                    ? 'Page ${current + 1} of $total so far…'
                    : 'Page ${current + 1} of $total',
                style: theme.textTheme.labelLarge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageReader extends StatelessWidget {
  const _ImageReader({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) => _ZoomableImage(path: path);
}

/// Pinch, pan and double-tap to zoom.
///
/// The same behaviour as the page viewer's, which is where the shape of it came
/// from: the first thing anybody does to a small photograph of dense text is
/// tap it, and pinching one-handed rarely works.
class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({required this.path});

  final String path;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  final TransformationController _transform = TransformationController();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

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
      onDoubleTap: () {},
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 6,
        boundaryMargin: const EdgeInsets.all(48),
        child: Center(
          child: Image.file(
            File(widget.path),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) =>
                const AppStateView.problem(
                  icon: Icons.broken_image_outlined,
                  title: 'This picture could not be shown',
                  message:
                      'The file may be damaged, or in a format this device '
                      'saved but cannot read.',
                ),
          ),
        ),
      ),
    );
  }
}

/// Plain text, Markdown or a Word file.
///
/// Read through `DocumentTextExtractor`, which is what an import uses — so a
/// `.docx` opened out of an archive reads exactly as it would once imported,
/// paragraph breaks and all, rather than as a screen of XML.
class _TextReader extends StatefulWidget {
  const _TextReader({required this.path});

  final String path;

  @override
  State<_TextReader> createState() => _TextReaderState();
}

class _TextReaderState extends State<_TextReader> {
  late final Future<String> _text = _read();

  Future<String> _read() async {
    final bytes = await File(widget.path).readAsBytes();
    final extension = p
        .extension(widget.path)
        .replaceFirst('.', '')
        .toLowerCase();

    return extension == 'docx'
        ? DocumentTextExtractor.wordDocument(bytes)
        : DocumentTextExtractor.plainText(bytes);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _text,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const AppStateView.busy(title: 'Reading…');
        }

        if (snapshot.hasError) {
          return const AppStateView.problem(
            icon: Icons.description_outlined,
            title: 'Could not read this file',
          );
        }

        final text = snapshot.data ?? '';
        if (text.trim().isEmpty) {
          return const AppStateView(
            icon: Icons.description_outlined,
            title: 'There is no text in this file',
          );
        }

        // Selectable, because the commonest thing anyone does with a text file
        // they opened to look at is copy a line out of it.
        return SelectionArea(
          child: SingleChildScrollView(
            padding: AppSpacing.screen,
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        );
      },
    );
  }
}
