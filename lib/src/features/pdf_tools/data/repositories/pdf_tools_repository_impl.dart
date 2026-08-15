import 'dart:io';

import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path/path.dart' as p;

import '../../../../core/error/failure.dart';
import '../../../../core/error/result.dart';
import '../../../../core/storage/storage_paths.dart';
import '../../../documents/domain/entities/document.dart';
import '../../../documents/domain/entities/document_page.dart';
import '../../../documents/domain/repositories/document_repository.dart';
import '../../../import/data/datasources/import_scratch.dart';
import '../../../import/data/datasources/pdf_page_rasterizer.dart';
import '../../../import/data/repositories/file_import_repository_impl.dart';
import '../../domain/entities/pdf_tool_models.dart';
import '../../domain/repositories/pdf_tools_repository.dart';
import '../datasources/page_recompressor.dart';

/// Opens the system picker for a single PDF.
Future<String?> _pickPdfWithSystemPicker() => FlutterFileDialog.pickFile(
  params: const OpenFileDialogParams(
    dialogType: OpenFileDialogType.document,
    mimeTypesFilter: <String>['application/pdf'],
    copyFileToCacheDir: true,
  ),
);

/// Merging and compressing, built on the renderer the app already uses.
///
/// **The architecture here is a deliberate reuse rather than a new one.** A PDF
/// in DocuAI has always been a set of page images: importing one renders it
/// through Android's own `PdfRenderer`, and exporting one composes those images
/// back into a PDF. So merging is rendering several files into one page list,
/// and compressing is re-encoding that list — both of which land in the same
/// `Document` the library, search, assistant and export already understand.
///
/// The alternative would be a true object-level PDF merge, which preserves
/// selectable text. It is not available here: `PdfDocumentParserBase` in the
/// `pdf` package is abstract with no implementation shipped, and a document can
/// carry only one `prev` — an incremental-update mechanism, not an N-way merge.
/// Reaching it would mean adding a large commercially-licensed PDF engine to an
/// offline app that currently bundles none. The cost of the approach taken is
/// stated plainly in the UI: merged and compressed output is page images.
class PdfToolsRepositoryImpl implements PdfToolsRepository {
  const PdfToolsRepositoryImpl({
    required DocumentRepository documents,
    required StoragePaths paths,
    FilePickerCall picker = _pickPdfWithSystemPicker,
    PdfPageRasterizer? rasterizer,
    PageCompressor compressor = recompressInIsolate,
    Future<Directory> Function()? temporaryDirectory,
  }) : _documents = documents,
       _paths = paths,
       _pick = picker,
       _rasterizer = rasterizer,
       _compress = compressor,
       _tempDir = temporaryDirectory;

  final DocumentRepository _documents;

  /// Turns a stored page path into one that can be opened.
  ///
  /// Injected like everywhere else in the app: pages are persisted relative to
  /// the app documents directory, and only `StoragePaths` knows where that is
  /// on this install.
  final StoragePaths _paths;

  final FilePickerCall _pick;
  final PdfPageRasterizer? _rasterizer;
  final PageCompressor _compress;
  final Future<Directory> Function()? _tempDir;

  /// Scratch space of the tools' own, kept apart from the importer's.
  ///
  /// `ImportScratch.prepare` empties the folder it is given, so sharing one
  /// with the importer would mean an import started mid-merge deleting the
  /// pages the merge had rendered so far.
  static const String scratchDirectory = 'docuai_pdf_tools';

  /// The most pages one merge will render.
  ///
  /// Not arbitrary caution: each page is decoded, resized and re-encoded, and
  /// the result is held on disk until the document is written. Two hundred
  /// A4 pages at this app's resolution is roughly 60–80 MB of JPEG, which is
  /// already more than most users mean to create in one go — and well short of
  /// where a mid-range phone starts refusing allocations.
  ///
  /// Reaching it does not fail the merge. The pages rendered up to that point
  /// are kept and the outcome says it was truncated, because a merge that threw
  /// away twenty minutes of rendering to report a limit would be worse than one
  /// that says what it managed.
  static const int maxMergedPages = 200;

  @override
  FutureResult<PdfSource> pickPdf() async {
    try {
      final path = await _pick();

      if (path == null) {
        return const Failed(
          ImportFailure('No PDF was chosen.', cancelled: true),
        );
      }

      // A chooser can be talked past — some file managers ignore the type
      // filter — so what actually arrived is checked rather than assumed.
      if (p.extension(path).toLowerCase() != '.pdf') {
        return const Failed(
          ImportFailure('That file is not a PDF, so it cannot be merged.'),
        );
      }

      final file = File(path);
      if (!file.existsSync()) {
        return const Failed(
          ImportFailure('That file could no longer be read from this device.'),
        );
      }

      return Success(
        PdfSource(
          // The path is unique per pick — the picker copies into the cache
          // under its own name — and is what tells two copies of the same
          // statement apart in the list.
          id: path,
          path: path,
          name: p.basenameWithoutExtension(path),
          sizeBytes: await file.length(),
        ),
      );
    } catch (error, stackTrace) {
      return Failed(
        ImportFailure(
          'That PDF could not be opened.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  FutureResult<MergeOutcome> merge({
    required List<PdfSource> sources,
    required String title,
    ToolProgressCallback? onProgress,
  }) async {
    if (sources.length < 2) {
      return const Failed(
        ValidationFailure('Choose at least two PDFs to merge.'),
      );
    }

    try {
      final scratch = await ImportScratch.prepare(
        temporaryDirectory: _tempDir,
        name: scratchDirectory,
      );

      final pages = <String>[];
      var truncated = false;

      for (var i = 0; i < sources.length; i++) {
        final source = sources[i];

        onProgress?.call(
          ToolProgress(done: i, total: sources.length, label: source.name),
        );

        final file = File(source.path);
        if (!file.existsSync()) {
          return Failed(
            ImportFailure(
              '"${source.name}" is no longer on this device. Remove it from '
              'the list and try again.',
            ),
          );
        }

        final remaining = maxMergedPages - pages.length;
        if (remaining <= 0) {
          truncated = true;
          break;
        }

        // A fresh rasterizer per file so the page budget is this file's share
        // of what is left, rather than the sixty a single import allows.
        final rasterizer =
            _rasterizer ?? PdfPageRasterizer(pageLimit: remaining);

        final rendered = await rasterizer.rasterize(
          bytes: await file.readAsBytes(),
          targetDirectory: scratch,
          // Ordered prefix. The pages of file 2 must sort and land after those
          // of file 1, and the index is the only thing that guarantees it when
          // two files share a name.
          prefix: 'merge_${i.toString().padLeft(3, '0')}',
        );

        if (rendered.isEmpty) {
          return Failed(
            ImportFailure(
              '"${source.name}" could not be opened. It may be damaged, or '
              'locked with a password. Remove it from the list and try again.',
            ),
          );
        }

        // The budget is enforced here rather than left to the rasterizer.
        // Passing `pageLimit` above is what stops the work being *done*; this
        // is what stops it being *counted* — and it holds whatever renderer is
        // in place, which a limit living only in the renderer would not.
        if (rendered.length >= remaining) {
          pages.addAll(rendered.take(remaining));
          truncated = true;
          break;
        }

        pages.addAll(rendered);
      }

      onProgress?.call(
        ToolProgress(
          done: sources.length,
          total: sources.length,
          label: 'Saving',
        ),
      );

      if (pages.isEmpty) {
        return const Failed(
          ImportFailure('None of those PDFs had any pages that could be read.'),
        );
      }

      // Copied into the document store here. The sources are only ever read,
      // so whatever the user picked is left exactly as it was.
      final created = await _documents.createFromImages(
        title: title,
        sourceImagePaths: pages,
        source: DocumentSource.imported,
        pageKind: PageKind.imported,
      );

      return switch (created) {
        Failed(:final failure) => Failed(failure),
        Success(:final value) => Success(
          MergeOutcome(
            document: value,
            pageCount: pages.length,
            sourceCount: sources.length,
            truncated: truncated,
          ),
        ),
      };
    } catch (error, stackTrace) {
      return Failed(
        ImportFailure(
          'Those PDFs could not be merged. If one of them is very large, try '
          'merging fewer at a time.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  FutureResult<CompressionOutcome> compress({
    required Document document,
    required CompressionLevel level,
    ToolProgressCallback? onProgress,
  }) async {
    final pages = document.pages
        .where((page) => page.hasImage)
        .toList(growable: false);

    if (pages.isEmpty) {
      return const Failed(
        ValidationFailure(
          'This document is written text rather than scanned pages, so there '
          'is nothing to compress.',
        ),
      );
    }

    try {
      final scratch = await ImportScratch.prepare(
        temporaryDirectory: _tempDir,
        name: scratchDirectory,
      );

      final sourcePaths = <String>[];
      var originalBytes = 0;

      for (final page in pages) {
        final file = File(_absolute(page.imagePath!));
        if (!file.existsSync()) {
          return const Failed(
            ImportFailure(
              'One of this document\'s pages is missing from storage, so it '
              'cannot be compressed.',
            ),
          );
        }
        originalBytes += await file.length();
        sourcePaths.add(file.path);
      }

      return _compressPages(
        sourcePaths: sourcePaths,
        scratch: scratch,
        originalBytes: originalBytes,
        title: CompressionOutcome.titleFor(document.title),
        sourceLabel: document.title,
        level: level,
        onProgress: onProgress,
      );
    } catch (error, stackTrace) {
      return Failed(
        ImportFailure(
          'This document could not be compressed. If it is very long, it may '
          'be too large to process on this device.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  @override
  FutureResult<CompressionOutcome> compressPdfFile({
    required PdfSource source,
    required CompressionLevel level,
    ToolProgressCallback? onProgress,
  }) async {
    try {
      final file = File(source.path);
      if (!file.existsSync()) {
        return Failed(
          ImportFailure(
            '"${source.name}" is no longer on this device. Choose it again.',
          ),
        );
      }

      final scratch = await ImportScratch.prepare(
        temporaryDirectory: _tempDir,
        name: scratchDirectory,
      );

      onProgress?.call(
        ToolProgress(done: 0, total: 2, label: 'Reading ${source.name}'),
      );

      // Rendered through the same path an imported PDF takes. A PDF the user
      // picked and a PDF already in the library become the same thing — page
      // images — before anything is compressed, so there is one compressor
      // rather than one per kind of input.
      final rasterizer = _rasterizer ?? const PdfPageRasterizer();
      final rendered = await rasterizer.rasterize(
        bytes: await file.readAsBytes(),
        targetDirectory: scratch,
        prefix: 'source',
      );

      if (rendered.isEmpty) {
        return Failed(
          ImportFailure(
            '"${source.name}" could not be opened. It may be damaged, or '
            'locked with a password.',
          ),
        );
      }

      return _compressPages(
        sourcePaths: rendered,
        scratch: scratch,
        // The file's own size on disk, which is what the user recognises as
        // "how big this PDF is" — not the size of the pages we rendered from
        // it, which is an implementation detail of how DocuAI reads a PDF.
        originalBytes: source.sizeBytes,
        title: CompressionOutcome.titleFor(source.name),
        sourceLabel: source.name,
        level: level,
        onProgress: onProgress,
        // Rendering was the first half of the job; the pages are the second.
        pageOffset: 1,
      );
    } catch (error, stackTrace) {
      return Failed(
        ImportFailure(
          'That PDF could not be compressed. If it is very large, it may be '
          'too big to process on this device.',
          cause: error,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Re-encodes a list of page images and saves them as a new document.
  ///
  /// The one compressor. Both entry points reduce to a list of JPEGs on disk
  /// and a number to compare the result against, which is why neither of them
  /// carries any re-encoding logic of its own.
  ///
  /// [pageOffset] shifts the progress reporting for a job that had a step
  /// before this one, so the bar does not restart at zero halfway through.
  Future<Result<CompressionOutcome>> _compressPages({
    required List<String> sourcePaths,
    required Directory scratch,
    required int originalBytes,
    required String title,
    required String sourceLabel,
    required CompressionLevel level,
    required ToolProgressCallback? onProgress,
    int pageOffset = 0,
  }) async {
    final total = sourcePaths.length + pageOffset;
    final compressed = <String>[];

    for (var i = 0; i < sourcePaths.length; i++) {
      onProgress?.call(
        ToolProgress(
          done: i + pageOffset,
          total: total,
          label: 'Page ${i + 1} of ${sourcePaths.length}',
        ),
      );

      final target = await _compress(
        sourcePath: sourcePaths[i],
        targetPath: p.join(
          scratch.path,
          'compressed_${i.toString().padLeft(3, '0')}.jpg',
        ),
        maxEdge: level.maxEdge,
        quality: level.jpegQuality,
      );

      if (target == null) {
        return const Failed(
          ImportFailure(
            'One of the pages could not be read, so it was not compressed.',
          ),
        );
      }

      compressed.add(target);
    }

    var compressedBytes = 0;
    for (final path in compressed) {
      compressedBytes += await File(path).length();
    }

    // Nothing is written when the copy came out no smaller. The re-encoded
    // pages stay in the scratch directory, which is cleared on the next run —
    // so a document the user already compressed once cannot fill their library
    // with larger duplicates of itself.
    final willSave = compressedBytes < originalBytes;

    // The bar reaches the end either way. A job that stops at nine tenths reads
    // as one that broke, whatever the screen after it goes on to say.
    onProgress?.call(
      ToolProgress(
        done: total,
        total: total,
        label: willSave ? 'Saving' : 'Comparing sizes',
      ),
    );

    if (!willSave) {
      return Success(
        CompressionOutcome(
          originalBytes: originalBytes,
          compressedBytes: compressedBytes,
          level: level,
          document: null,
          sourceLabel: sourceLabel,
        ),
      );
    }

    final created = await _documents.createFromImages(
      title: title,
      sourceImagePaths: compressed,
      // As far as the library is concerned a compressed copy has the same
      // origin as what it was made from: something that came in from outside
      // rather than something written here.
      source: DocumentSource.imported,
      pageKind: PageKind.imported,
    );

    return switch (created) {
      Failed(:final failure) => Failed(failure),
      Success(:final value) => Success(
        CompressionOutcome(
          originalBytes: originalBytes,
          compressedBytes: compressedBytes,
          level: level,
          document: value,
          sourceLabel: sourceLabel,
        ),
      ),
    };
  }

  String _absolute(String relativePath) => _paths.absolutePath(relativePath);
}
