import 'dart:io';
import 'dart:typed_data';

import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/import/data/datasources/import_scratch.dart';
import 'package:docuai/src/features/import/data/datasources/pdf_page_rasterizer.dart';
import 'package:docuai/src/features/pdf_tools/data/repositories/pdf_tools_repository_impl.dart';
import 'package:docuai/src/features/pdf_tools/domain/entities/pdf_tool_models.dart';
import 'package:docuai/src/features/pdf_tools/domain/usecases/compress_document.dart';
import 'package:docuai/src/features/pdf_tools/domain/usecases/merge_pdfs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';

/// Merging and compressing PDFs, offline.
///
/// The platform edges are stood in for and everything else is real: the
/// repository, the use cases, the document store and the file system all run as
/// they do in the app. The two things faked are the two that need Android —
/// the file picker, and the PDF renderer that would otherwise need a real
/// `PdfRenderer` and a real PDF.
///
/// The rule these tests exist to hold: **nothing the user chose is modified.**
/// A merge reads files belonging to other apps and a compression is offered on
/// a document the user may have only one copy of, so every case below checks
/// the inputs afterwards as well as the output.
void main() {
  late Directory tempDir;
  late Directory sourceDir;
  late FakeDocumentRepository documents;
  late StoragePaths paths;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_pdf_tools');
    sourceDir = Directory(p.join(tempDir.path, 'sources'))
      ..createSync(recursive: true);
    documents = FakeDocumentRepository();
    paths = StoragePaths(tempDir);
  });

  tearDown(() async {
    documents.dispose();
    if (tempDir.existsSync()) {
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        // Windows may still hold a handle; the OS reclaims it.
      }
    }
  });

  Future<Directory> scratch() async => tempDir;

  /// Writes a stand-in PDF and returns its path.
  ///
  /// The bytes are never parsed — the renderer is faked — so what matters is
  /// that the file exists, has a size, and can be checked for modification
  /// afterwards.
  File writePdf(String name, {int pages = 1}) {
    final file = File(p.join(sourceDir.path, '$name.pdf'));
    // The page count and the name are encoded in the bytes so the fake renderer
    // can read them back. The name is what lets a test prove which *source* a
    // merged page came from, rather than trusting the order it arrived in —
    // which is the very thing the ordering tests are checking.
    file.writeAsBytesSync(
      Uint8List.fromList(<int>[pages, ...name.codeUnits]),
    );
    return file;
  }

  PdfSource sourceFor(File file) => PdfSource(
    id: file.path,
    path: file.path,
    name: p.basenameWithoutExtension(file.path),
    sizeBytes: file.lengthSync(),
  );

  /// A renderer that produces one JPEG per page without needing Android.
  ///
  /// Honours [PdfPageRasterizer.pageLimit], because the page budget a merge
  /// spends across several files is a real behaviour and a fake that ignored it
  /// would let the truncation test pass while the product silently rendered
  /// everything.
  PdfPageRasterizer fakeRasterizer({int pageLimit = 200, bool fails = false}) =>
      _FakeRasterizer(pageLimit: pageLimit, fails: fails);

  PdfToolsRepositoryImpl repositoryWith({
    PdfPageRasterizer? rasterizer,
    PageCompressorStub? compressor,
    Future<String?> Function()? picker,
  }) => PdfToolsRepositoryImpl(
    documents: documents,
    paths: paths,
    picker: picker ?? () async => null,
    rasterizer: rasterizer ?? fakeRasterizer(),
    compressor: (compressor ?? PageCompressorStub()).call,
    temporaryDirectory: scratch,
  );

  group('merging', () {
    test('joins two PDFs into one document', () async {
      final a = writePdf('statement', pages: 2);
      final b = writePdf('receipt', pages: 1);

      final merge = MergePdfs(repositoryWith());
      final result = await merge(
        sources: <PdfSource>[sourceFor(a), sourceFor(b)],
        title: 'Everything',
      );

      final outcome = (result as Success<MergeOutcome>).value;

      expect(outcome.pageCount, 3);
      expect(outcome.sourceCount, 2);
      expect(outcome.document.title, 'Everything');
      expect(outcome.document.pages, hasLength(3));
      expect(outcome.truncated, isFalse);
    });

    test('joins many PDFs, not just two', () async {
      // The brief is explicit that there is no arbitrary low ceiling. Seven is
      // past any number somebody might have hard-coded as "enough".
      final sources = <PdfSource>[
        for (var i = 0; i < 7; i++) sourceFor(writePdf('file_$i', pages: 2)),
      ];

      final result = await MergePdfs(repositoryWith())(
        sources: sources,
        title: 'Seven',
      );

      final outcome = (result as Success<MergeOutcome>).value;

      expect(outcome.sourceCount, 7);
      expect(outcome.pageCount, 14);
    });

    test('keeps page order across files, and within them', () async {
      final first = writePdf('first', pages: 2);
      final second = writePdf('second', pages: 2);

      final result = await MergePdfs(repositoryWith())(
        sources: <PdfSource>[sourceFor(first), sourceFor(second)],
        title: 'Ordered',
      );

      final document = (result as Success<MergeOutcome>).value.document;

      // The fake names each rendered page after the file and page it came
      // from, and the store copies them in the order it was given — so the
      // recorded source order is the merge order.
      expect(
        documents.lastSourceImagePaths!.map(p.basenameWithoutExtension),
        <String>[
          'merge_000_0',
          'merge_000_1',
          'merge_001_0',
          'merge_001_1',
        ],
      );
      expect(
        document.pages.map((page) => page.index),
        <int>[0, 1, 2, 3],
        reason: 'pages are renumbered contiguously from their position',
      );
    });

    test('the order of the list is the order of the result', () async {
      final a = writePdf('a', pages: 1);
      final b = writePdf('b', pages: 1);

      // Reordered before merging — b first — which is what the reorderable
      // list on the screen produces.
      final result = await MergePdfs(repositoryWith())(
        sources: <PdfSource>[sourceFor(b), sourceFor(a)],
        title: 'Reordered',
      );

      expect(result, isA<Success<MergeOutcome>>());
      expect(
        documents.lastSourceImagePaths!.first,
        contains('merge_000'),
        reason: 'whichever file is first in the list is rendered first',
      );
      // Proven by content rather than by position alone: the first rendered
      // page must have come from "b".
      expect(File(documents.lastSourceImagePaths!.first).readAsStringSync(),
          startsWith('b#0'));
    });

    test('a file removed from the list contributes nothing', () async {
      final keep = writePdf('keep', pages: 1);
      final drop = writePdf('drop', pages: 1);

      final chosen = <PdfSource>[sourceFor(keep), sourceFor(drop)]
        ..removeWhere((source) => source.name == 'drop');

      final result = await MergePdfs(repositoryWith())(
        sources: <PdfSource>[...chosen, sourceFor(writePdf('other'))],
        title: 'Without drop',
      );

      final outcome = (result as Success<MergeOutcome>).value;

      expect(outcome.pageCount, 2);
      for (final path in documents.lastSourceImagePaths!) {
        expect(File(path).readAsStringSync(), isNot(contains('drop')));
      }
    });

    test('leaves the original PDFs exactly as they were', () async {
      final a = writePdf('original_a', pages: 3);
      final b = writePdf('original_b', pages: 2);

      final before = <String, ({int length, DateTime modified})>{
        for (final file in <File>[a, b])
          file.path: (
            length: file.lengthSync(),
            modified: file.lastModifiedSync(),
          ),
      };

      await MergePdfs(repositoryWith())(
        sources: <PdfSource>[sourceFor(a), sourceFor(b)],
        title: 'Merged',
      );

      for (final file in <File>[a, b]) {
        expect(file.existsSync(), isTrue, reason: 'a source was deleted');
        expect(file.lengthSync(), before[file.path]!.length);
        expect(file.lastModifiedSync(), before[file.path]!.modified);
      }
    });

    test('refuses a single file, because that is a copy', () async {
      final result = await MergePdfs(repositoryWith())(
        sources: <PdfSource>[sourceFor(writePdf('alone'))],
        title: 'Alone',
      );

      expect(result, isA<Failed<MergeOutcome>>());
      expect((result as Failed).failure, isA<ValidationFailure>());
    });

    test('names the file when a PDF cannot be opened', () async {
      final good = writePdf('good');
      final bad = writePdf('damaged');

      final result = await MergePdfs(
        repositoryWith(rasterizer: fakeRasterizer(fails: true)),
      )(sources: <PdfSource>[sourceFor(good), sourceFor(bad)], title: 'Merged');

      final failure = (result as Failed<MergeOutcome>).failure;

      expect(
        failure.message,
        contains('good'),
        reason: 'a user cannot act on "a file could not be read"',
      );
      expect(failure.message.toLowerCase(), contains('damaged'));
    });

    test('says so when a chosen file has since disappeared', () async {
      final gone = writePdf('vanished');
      final source = sourceFor(gone);
      gone.deleteSync();

      final result = await MergePdfs(repositoryWith())(
        sources: <PdfSource>[source, sourceFor(writePdf('present'))],
        title: 'Merged',
      );

      expect(
        (result as Failed<MergeOutcome>).failure.message,
        contains('vanished'),
      );
    });

    test('a very long merge stops at the budget and says it did', () async {
      // Two files of 150 pages each: the first fits, the second is cut off at
      // the 200-page cap. Truncating silently would hand back a document the
      // user believes is complete.
      final sources = <PdfSource>[
        sourceFor(writePdf('long_a', pages: 150)),
        sourceFor(writePdf('long_b', pages: 150)),
      ];

      final result = await MergePdfs(repositoryWith())(
        sources: sources,
        title: 'Very long',
      );

      final outcome = (result as Success<MergeOutcome>).value;

      expect(outcome.pageCount, PdfToolsRepositoryImpl.maxMergedPages);
      expect(
        outcome.truncated,
        isTrue,
        reason: 'a merge that quietly drops pages is worse than one that says',
      );
    });

    test('falls back to a dated title rather than refusing a blank one', () {
      expect(
        MergePdfs.defaultTitle(DateTime(2026, 8, 11)),
        'Merged 11/08/2026',
      );
    });
  });

  group('picking', () {
    test('a dismissed picker is silent, not an error', () async {
      final result = await repositoryWith(picker: () async => null).pickPdf();

      final failure = (result as Failed<PdfSource>).failure;
      expect(failure, isA<ImportFailure>());
      expect((failure as ImportFailure).cancelled, isTrue);
    });

    test('a file that is not a PDF is refused', () async {
      final notPdf = File(p.join(sourceDir.path, 'photo.jpg'))
        ..writeAsBytesSync(<int>[1, 2, 3]);

      final result = await repositoryWith(
        picker: () async => notPdf.path,
      ).pickPdf();

      expect(
        (result as Failed<PdfSource>).failure.message,
        contains('not a PDF'),
      );
    });

    test('a chosen PDF carries its name and size', () async {
      final file = writePdf('bank statement');

      final result = await repositoryWith(
        picker: () async => file.path,
      ).pickPdf();

      final source = (result as Success<PdfSource>).value;
      expect(source.name, 'bank statement');
      expect(source.sizeBytes, file.lengthSync());
    });
  });

  group('compressing', () {
    /// A document whose pages are real files on disk, so sizes are real.
    Future<Document> documentWithPages({
      required String id,
      required List<int> pageBytes,
    }) async {
      final dir = await paths.documentDir(id);
      final pages = <DocumentPage>[];

      for (var i = 0; i < pageBytes.length; i++) {
        final file = File(p.join(dir.path, 'page_$i.jpg'))
          ..writeAsBytesSync(List<int>.filled(pageBytes[i], 7));

        pages.add(
          buildPage(
            id: '$id-p$i',
            index: i,
            imagePath: paths.relativePath(file.path),
            ocrStatus: OcrStatus.completed,
            text: 'page $i',
          ),
        );
      }

      final document = buildDocument(id: id, title: 'Scan', pages: pages);
      documents.seed(document);
      return document;
    }

    test('produces a smaller copy and reports both sizes', () async {
      final document = await documentWithPages(
        id: 'big',
        pageBytes: <int>[4000, 4000],
      );

      // A stub that writes a quarter of what it was given, which is the shape
      // of a real recompression without depending on the JPEG encoder.
      final result = await CompressDocument(
        repositoryWith(compressor: PageCompressorStub(ratio: 0.25)),
      )(document: document, level: CompressionLevel.balanced);

      final outcome = (result as Success<CompressionOutcome>).value;

      expect(outcome.originalBytes, 8000);
      expect(outcome.compressedBytes, 2000);
      expect(outcome.reduced, isTrue);
      expect(outcome.savedBytes, 6000);
      expect((outcome.savedFraction * 100).round(), 75);
      expect(outcome.document, isNotNull);
    });

    test('saves the copy as a new document and leaves the original alone',
        () async {
      final document = await documentWithPages(
        id: 'keep',
        pageBytes: <int>[2000],
      );
      final originalPageSize = File(
        paths.absolutePath(document.pages.single.imagePath!),
      ).lengthSync();

      final result = await CompressDocument(
        repositoryWith(compressor: PageCompressorStub(ratio: 0.5)),
      )(document: document, level: CompressionLevel.smallerSize);

      final outcome = (result as Success<CompressionOutcome>).value;

      expect(outcome.document.id, isNot(document.id));
      expect(outcome.document.title, 'Scan (compressed)');

      // The document the user chose is untouched: still in the store, still
      // the same pages, still the same bytes on disk.
      final stored = documents.store[document.id]!;
      expect(stored.pages, hasLength(1));
      expect(
        File(paths.absolutePath(stored.pages.single.imagePath!)).lengthSync(),
        originalPageSize,
      );
    });

    test('an already-compressed document reports honestly and keeps the copy',
        () async {
      final document = await documentWithPages(
        id: 'tight',
        pageBytes: <int>[1000],
      );
      final before = documents.store.length;

      // The stub gives back a *larger* file, which is what re-encoding an
      // already-small JPEG really does.
      final result = await CompressDocument(
        repositoryWith(compressor: PageCompressorStub(ratio: 1.4)),
      )(document: document, level: CompressionLevel.highQuality);

      final outcome = (result as Success<CompressionOutcome>).value;

      expect(outcome.reduced, isFalse);
      expect(outcome.originalBytes, 1000);
      expect(outcome.compressedBytes, 1400);
      expect(outcome.savedBytes, 0);

      // The copy is kept and the sizes are stated. Discarding it was the old
      // behaviour and it left a user who had waited for the work with nothing
      // to show for it — and a page bounded to the level's pixel limit can be
      // the thing they needed even where the byte count went the wrong way.
      expect(documents.store.length, before + 1);
      expect(outcome.document.title, 'Scan (compressed)');
      expect(
        documents.store[document.id]!.pages,
        hasLength(1),
        reason: 'the original is untouched whatever the copy came out at',
      );
    });

    test('a written document has nothing to compress, and says so', () async {
      final document = buildDocument(
        id: 'written',
        pages: <DocumentPage>[buildTextPage(text: 'Typed by hand.')],
      );
      documents.seed(document);

      final result = await CompressDocument(repositoryWith())(
        document: document,
        level: CompressionLevel.balanced,
      );

      final failure = (result as Failed<CompressionOutcome>).failure;
      expect(failure, isA<ValidationFailure>());
      expect(failure.message, contains('written text'));
    });

    test('an unreadable page is reported rather than silently dropped',
        () async {
      final document = await documentWithPages(
        id: 'broken',
        pageBytes: <int>[500],
      );

      final result = await CompressDocument(
        repositoryWith(compressor: PageCompressorStub(undecodable: true)),
      )(document: document, level: CompressionLevel.balanced);

      expect(result, isA<Failed<CompressionOutcome>>());
    });

    test('a page missing from storage is reported', () async {
      final document = await documentWithPages(
        id: 'missing',
        pageBytes: <int>[500],
      );
      File(paths.absolutePath(document.pages.single.imagePath!)).deleteSync();

      final result = await CompressDocument(repositoryWith())(
        document: document,
        level: CompressionLevel.balanced,
      );

      expect(
        (result as Failed<CompressionOutcome>).failure.message,
        contains('missing from storage'),
      );
    });

    test('a long document reports progress as it goes', () async {
      final document = await documentWithPages(
        id: 'long',
        pageBytes: List<int>.filled(30, 1000),
      );

      final seen = <ToolProgress>[];
      await CompressDocument(
        repositoryWith(compressor: PageCompressorStub(ratio: 0.5)),
      )(
        document: document,
        level: CompressionLevel.balanced,
        onProgress: seen.add,
      );

      expect(seen, isNotEmpty);
      expect(seen.first.total, 30);
      expect(seen.last.fraction, 1.0);
      expect(
        seen.map((progress) => progress.done).toList(),
        orderedEquals(<int>[for (var i = 0; i < 30; i++) i, 30]),
        reason: 'a bar that jumps or goes backwards is worse than none',
      );
    });

    test('every level asks for fewer pixels and less quality than the last',
        () {
      // The levels only mean anything if they are ordered. A "smaller size"
      // that encoded at higher quality than "balanced" would be a setting that
      // does the opposite of its name.
      const levels = CompressionLevel.values;

      for (var i = 1; i < levels.length; i++) {
        expect(levels[i].maxEdge, lessThan(levels[i - 1].maxEdge));
        expect(levels[i].jpegQuality, lessThan(levels[i - 1].jpegQuality));
      }
    });
  });

  /// Compression is not restricted to documents DocuAI made.
  ///
  /// The tool was only offered a library picker, which made it useless for the
  /// case people actually have: a PDF somebody sent them that is too big to
  /// send on.
  group('compressing a PDF from device storage', () {
    test('renders an external PDF and saves a smaller copy', () async {
      final file = writePdf('bank statement', pages: 3);

      final result = await CompressPdfFile(
        repositoryWith(compressor: PageCompressorStub(ratio: 0.25)),
      )(source: sourceFor(file), level: CompressionLevel.balanced);

      final outcome = (result as Success<CompressionOutcome>).value;

      expect(outcome.document.title, 'bank statement (compressed)');
      expect(outcome.document.pages, hasLength(3));
      expect(outcome.sourceLabel, 'bank statement');
    });

    test('compares against the file\'s own size on disk', () async {
      final file = writePdf('statement', pages: 2);

      final result = await CompressPdfFile(
        repositoryWith(compressor: PageCompressorStub(ratio: 0.25)),
      )(source: sourceFor(file), level: CompressionLevel.balanced);

      final outcome = (result as Success<CompressionOutcome>).value;

      // What the user recognises as "how big this PDF is" is the file, not the
      // pages DocuAI rendered out of it.
      expect(outcome.originalBytes, file.lengthSync());
    });

    test('never modifies the PDF it was given', () async {
      final file = writePdf('untouched', pages: 2);
      final before = (
        length: file.lengthSync(),
        modified: file.lastModifiedSync(),
      );

      await CompressPdfFile(
        repositoryWith(compressor: PageCompressorStub(ratio: 0.5)),
      )(source: sourceFor(file), level: CompressionLevel.smallerSize);

      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), before.length);
      expect(file.lastModifiedSync(), before.modified);
    });

    test('reports a PDF that cannot be opened by name', () async {
      final result = await CompressPdfFile(
        repositoryWith(rasterizer: fakeRasterizer(fails: true)),
      )(source: sourceFor(writePdf('locked')), level: CompressionLevel.balanced);

      expect(
        (result as Failed<CompressionOutcome>).failure.message,
        contains('locked'),
      );
    });

    test('says so when the chosen file has since disappeared', () async {
      final gone = writePdf('vanished');
      final source = sourceFor(gone);
      gone.deleteSync();

      final result = await CompressPdfFile(repositoryWith())(
        source: source,
        level: CompressionLevel.balanced,
      );

      expect(
        (result as Failed<CompressionOutcome>).failure.message,
        contains('vanished'),
      );
    });

    test('progress covers rendering as well as the pages', () async {
      final seen = <ToolProgress>[];

      await CompressPdfFile(
        repositoryWith(compressor: PageCompressorStub(ratio: 0.5)),
      )(
        source: sourceFor(writePdf('long', pages: 4)),
        level: CompressionLevel.balanced,
        onProgress: seen.add,
      );

      expect(seen.first.done, 0);
      expect(seen.last.fraction, 1.0);
      // Rendering is the first step, so the bar must not restart at zero when
      // the pages begin.
      expect(
        seen.map((progress) => progress.done).toList(),
        orderedEquals(<int>[0, 1, 2, 3, 4, 5]),
      );
    });
  });

  group('the existing PDF path is unchanged', () {
    test('a rasterizer built the old way still caps one import at 60 pages',
        () {
      // The page cap became a field so a merge could spend one budget across
      // several files. Every existing caller constructs the rasterizer without
      // it, and for them nothing may have changed — a lower default here would
      // silently truncate imported PDFs.
      expect(const PdfPageRasterizer().pageLimit, PdfPageRasterizer.maxPages);
      expect(PdfPageRasterizer.maxPages, 60);
      expect(const PdfPageRasterizer().dpi, 150);
    });

    test('the tools keep their scratch space apart from the importer', () {
      // `ImportScratch.prepare` empties the folder it is handed, so sharing one
      // would mean an import started mid-merge deleting the pages the merge had
      // rendered so far.
      expect(
        PdfToolsRepositoryImpl.scratchDirectory,
        isNot(ImportScratch.directoryName),
      );
    });
  });

  group('sizes are reported the way a person says them', () {
    test('bytes, kilobytes and megabytes', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(2048), '2.0 KB');
      expect(formatBytes(5 * 1024 * 1024), '5.0 MB');
      // Past ten the decimal stops earning its place.
      expect(formatBytes(47 * 1024 * 1024), '47 MB');
    });
  });
}

/// Renders one JPEG per page without Android.
///
/// Writes the file it came from and the page number into the bytes, so a test
/// can prove which source a merged page came from rather than trusting the
/// order it was handed back in.
class _FakeRasterizer extends PdfPageRasterizer {
  const _FakeRasterizer({required super.pageLimit, required this.fails});

  final bool fails;

  @override
  Future<List<String>> rasterize({
    required Uint8List bytes,
    required Directory targetDirectory,
    required String prefix,
  }) async {
    if (fails) return const <String>[];

    // The helper encodes the page count in the first byte and the source name
    // in the rest.
    final pages = bytes.isEmpty ? 1 : bytes.first;
    final name = String.fromCharCodes(bytes.skip(1));
    final written = <String>[];

    for (var i = 0; i < pages && i < pageLimit; i++) {
      final file = File(p.join(targetDirectory.path, '${prefix}_$i.jpg'));
      // Names the source it came from, so provenance is checkable.
      await file.writeAsString('$name#$i');
      written.add(file.path);
    }

    return written;
  }
}

/// Stands in for the JPEG re-encoder.
///
/// Real recompression is the `image` package doing a decode, a resize and an
/// encode — none of which these tests are about. What they are about is what
/// the repository does with the result, so the stub simply produces a file of a
/// chosen size relative to its input.
class PageCompressorStub {
  PageCompressorStub({this.ratio = 0.5, this.undecodable = false});

  /// Output size as a fraction of the input. Above 1 models a page that cannot
  /// be squeezed any further.
  final double ratio;

  /// Models bytes the decoder refuses.
  final bool undecodable;

  Future<String?> call({
    required String sourcePath,
    required String targetPath,
    required int maxEdge,
    required int quality,
  }) async {
    if (undecodable) return null;

    final source = await File(sourcePath).length();
    await File(
      targetPath,
    ).writeAsBytes(List<int>.filled((source * ratio).round(), 3), flush: true);

    return targetPath;
  }
}
