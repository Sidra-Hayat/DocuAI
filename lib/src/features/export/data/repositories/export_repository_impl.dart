import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/storage/storage_paths.dart';
import '../../../../core/text/markup.dart';
import '../../../documents/domain/entities/document.dart';
import '../../domain/repositories/export_repository.dart';
import '../datasources/docx_composer.dart';
import '../datasources/pdf_composer.dart';

/// How the share sheet is opened. Injected so tests do not need a platform.
typedef ShareLauncher = Future<ShareResult> Function(ShareParams params);

Future<ShareResult> _launchSystemShare(ShareParams params) =>
    SharePlus.instance.share(params);

/// Composes PDFs into the document's own folder and hands them to the system
/// share sheet.
class ExportRepositoryImpl implements ExportRepository {
  const ExportRepositoryImpl({
    required StoragePaths paths,
    PdfRenderer renderer = renderPdfInIsolate,
    DocxWriter docxWriter = writeDocxInIsolate,
    ShareLauncher launcher = _launchSystemShare,
  }) : _paths = paths,
       _render = renderer,
       _writeDocx = docxWriter,
       _share = launcher;

  final StoragePaths _paths;
  final PdfRenderer _render;
  final DocxWriter _writeDocx;
  final ShareLauncher _share;

  @override
  FutureResult<String> buildPdf(Document document) async {
    try {
      // Built in page order, so a document mixing scans and written pages
      // exports as the thing the user is looking at rather than as its images
      // followed by its text.
      final pages = <PdfPageJob>[];
      for (final page in document.pages) {
        final relative = page.imagePath;

        if (relative != null) {
          final absolute = _paths.absolutePath(relative);
          // Checked up front so a document with a missing page fails in
          // milliseconds instead of after rendering everything before it.
          if (!File(absolute).existsSync()) {
            return Failed(
              ExportFailure(
                'The image for ${page.displayLabel} is missing, so this '
                'document cannot be exported.',
              ),
            );
          }
          pages.add(PdfImagePage(absolute));
        } else if (page.hasText) {
          // The text names its pictures by filename; only this layer knows
          // which folder that means. Resolved here, and checked here for the
          // same reason the page images above are: a document that cannot be
          // exported should say so before anything is rendered.
          final images = <String, String>{};
          for (final name in Markup.imageNames(page.text)) {
            final path = _paths.inlineImagePath(document.id, name);
            if (!File(path).existsSync()) {
              return Failed(
                ExportFailure(
                  'A picture in ${page.displayLabel} is missing, so this '
                  'document cannot be exported. Remove it from the page and '
                  'try again.',
                ),
              );
            }
            images[name] = path;
          }

          pages.add(PdfTextPage(page.text, images: images));
        }
      }

      // A PDF with no pages is not a document. Refusing says what happened;
      // writing an empty file would only be discovered after it was shared.
      if (pages.isEmpty) {
        return const Failed(
          ExportFailure(
            'There is nothing in this document to export yet. Write something '
            'or add a page first.',
          ),
        );
      }

      final bytes = await _render(PdfJob(pages: pages, title: document.title));

      final directory = await _paths.documentDir(document.id);
      final file = File(p.join(directory.path, _fileNameFor(document.title)));
      await file.writeAsBytes(bytes, flush: true);

      return Success(_paths.relativePath(file.path));
    } catch (error, stackTrace) {
      return Failed(
        ExportFailure(
          'The PDF could not be created.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  FutureResult<String> buildDocx(Document document) async {
    // Said here, where there is a document to name it against, rather than let
    // through to a composer that would only be able to throw. Word export
    // cannot carry pictures yet, and a file quietly missing them is worse than
    // one that was never written.
    if (document.pages.any((page) => Markup.hasImages(page.text))) {
      return const Failed(
        ExportFailure(
          'This document has a picture in it, and Word files cannot include '
          'pictures yet. Share it as a PDF to keep the pictures.',
        ),
      );
    }

    try {
      // Every page's text, scanned and written alike. A Word file is wanted
      // because it can be edited, and recognised text is the part of a scan
      // that anyone would want to edit.
      final pages = <DocxPage>[
        for (final page in document.pages)
          if (page.hasText) DocxPage(page.text),
      ];

      // Refused, not written empty. A Word file that opens to a blank page
      // looks exactly like an export that worked, and the user would only
      // find out after sending it.
      if (pages.isEmpty) {
        return Failed(
          ExportFailure(
            document.hasImagePages
                ? 'There is no text in this document yet. Recognise the text '
                      'first, or export it as a PDF to send the pages '
                      'themselves.'
                : 'There is nothing written in this document yet.',
          ),
        );
      }

      final bytes = await _writeDocx(
        DocxJob(pages: pages, title: document.title),
      );

      final directory = await _paths.documentDir(document.id);
      final file = File(
        p.join(directory.path, _fileNameFor(document.title, 'docx')),
      );
      await file.writeAsBytes(bytes, flush: true);

      return Success(_paths.relativePath(file.path));
    } catch (error, stackTrace) {
      return Failed(
        ExportFailure(
          'The Word file could not be created.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  FutureResult<void> shareFile(String relativePath, {String? subject}) async {
    final absolute = _paths.absolutePath(relativePath);

    if (!File(absolute).existsSync()) {
      return const Failed(
        ExportFailure(
          'The exported PDF is no longer on this device. Export it again.',
        ),
      );
    }

    try {
      final result = await _share(
        ShareParams(files: <XFile>[XFile(absolute)], subject: subject),
      );

      // Dismissing the sheet is a success. Android reports "dismissed" both for
      // a user who changed their mind and for one who completed a share the
      // system declined to describe, so treating it as an error would show a
      // failure message after a share that actually worked.
      return switch (result.status) {
        ShareResultStatus.unavailable => const Failed(
          ExportFailure('No app on this device can receive the PDF.'),
        ),
        ShareResultStatus.success ||
        ShareResultStatus.dismissed => const Success<void>(null),
      };
    } catch (error, stackTrace) {
      return Failed(
        ExportFailure(
          'The PDF could not be shared.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  FutureResult<void> shareText(String text, {String? subject}) async {
    try {
      final result = await _share(ShareParams(text: text, subject: subject));

      return switch (result.status) {
        ShareResultStatus.unavailable => const Failed(
          ExportFailure('No app on this device can receive text.'),
        ),
        ShareResultStatus.success ||
        ShareResultStatus.dismissed => const Success<void>(null),
      };
    } catch (error, stackTrace) {
      return Failed(
        ExportFailure(
          'The text could not be shared.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Names the file after the document, because the title is what the share
  /// sheet and the receiving app display — `document.pdf` tells the recipient
  /// nothing. The extension decides which export it names.
  ///
  /// Kept to characters that are safe on the filesystems an Android share can
  /// land on, including FAT-formatted SD cards and Windows machines at the
  /// other end of an email.
  static String _fileNameFor(String title, [String extension = 'pdf']) {
    final cleaned = title
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (cleaned.isEmpty) return 'document.$extension';

    final truncated = cleaned.length > 60 ? cleaned.substring(0, 60) : cleaned;
    return '${truncated.trim()}.$extension';
  }
}
