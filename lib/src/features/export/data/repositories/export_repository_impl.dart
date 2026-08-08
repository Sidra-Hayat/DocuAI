import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/storage/storage_paths.dart';
import '../../../documents/domain/entities/document.dart';
import '../../domain/repositories/export_repository.dart';
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
    ShareLauncher launcher = _launchSystemShare,
  }) : _paths = paths,
       _render = renderer,
       _share = launcher;

  final StoragePaths _paths;
  final PdfRenderer _render;
  final ShareLauncher _share;

  @override
  FutureResult<String> buildPdf(Document document) async {
    try {
      final imagePaths = <String>[];
      for (final page in document.pages) {
        // Pages with no image are skipped rather than failed. Drawing them is
        // the composer's job and it cannot do it yet, so until then a mixed
        // document exports the pages that can be drawn.
        final relative = page.imagePath;
        if (relative == null) continue;

        final absolute = _paths.absolutePath(relative);
        // Checked up front so a document with a missing page fails in
        // milliseconds instead of after rendering everything before it.
        if (!File(absolute).existsSync()) {
          return Failed(
            ExportFailure(
              'The image for ${page.displayLabel} is missing, so this document '
              'cannot be exported.',
            ),
          );
        }
        imagePaths.add(absolute);
      }

      // A PDF with no pages is not a document. Refusing says what happened;
      // writing an empty file would only be discovered after it was shared.
      if (imagePaths.isEmpty) {
        return const Failed(
          ExportFailure(
            'This document has no scanned pages to export as a PDF yet.',
          ),
        );
      }

      final bytes = await _render(
        PdfJob(imagePaths: imagePaths, title: document.title),
      );

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
  /// nothing.
  ///
  /// Kept to characters that are safe on the filesystems an Android share can
  /// land on, including FAT-formatted SD cards and Windows machines at the
  /// other end of an email.
  static String _fileNameFor(String title) {
    final cleaned = title
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (cleaned.isEmpty) return 'document.pdf';

    final truncated = cleaned.length > 60 ? cleaned.substring(0, 60) : cleaned;
    return '${truncated.trim()}.pdf';
  }
}
