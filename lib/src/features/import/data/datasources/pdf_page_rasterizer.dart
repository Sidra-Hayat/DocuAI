import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';

import 'imported_image_normalizer.dart';

/// Turns a PDF into page images.
///
/// DocuAI has exactly one kind of page — an image with text read off it — and
/// the whole library, search index, assistant and both exports are built on
/// that. Rendering a PDF into page images therefore costs nothing downstream: a
/// bank statement imported as a PDF becomes searchable, quotable and shareable
/// through the code that already existed, rather than through a second path
/// that would have to be kept in step with the first.
///
/// Rendering runs through the platform's own PDF renderer — Android's
/// `PdfRenderer`, which every device has — so nothing is uploaded and no PDF
/// engine is bundled into the APK.
class PdfPageRasterizer {
  const PdfPageRasterizer({
    ImageNormalizer normalizer = normalizeInIsolate,
    this.dpi = 150,
    this.pageLimit = maxPages,
  }) : _normalize = normalizer;

  final ImageNormalizer _normalize;

  /// How many pages *this* rasterizer will read.
  ///
  /// Defaults to [maxPages], which is what a single import has always allowed.
  /// Merging needs to spend one budget across several files — a hundred-page
  /// PDF followed by a two-page one must not each get their own sixty — so the
  /// cap became a field the caller can lower per call.
  final int pageLimit;

  /// Rendering resolution.
  ///
  /// 150 is comfortably above what text recognition needs for body text and
  /// well under what a phone spends real time on. Higher mostly buys larger
  /// files: the normaliser caps the long edge afterwards regardless.
  final int dpi;

  /// A cap on one import.
  ///
  /// Not a technical limit. A three-hundred-page PDF rendered page by page is
  /// a wait with no obvious end, and a library entry nobody meant to create.
  static const int maxPages = 60;

  /// Renders [bytes] into JPEGs under [targetDirectory], in page order.
  ///
  /// Returns an empty list when the file has no pages the renderer can read,
  /// which the caller reports as a file it could not open — deliberately not an
  /// exception, because "this PDF is an image-only scan the renderer refused"
  /// is a fact about the file, not a fault in the app.
  ///
  /// [onPageLimitReached] fires once if the file turned out to have more pages
  /// than [pageLimit] allows. A callback rather than a richer return type
  /// because the PDF tools call this too and neither of them needs the signal:
  /// merging counts its own budget across several files, and compressing a
  /// single PDF is bounded by the same limit its source already was.
  ///
  /// [onPage] fires as each page lands, before the rest have been rendered.
  /// Every caller that *converts* a PDF ignores it — a half-imported document
  /// is not a document — but the reader that opens a PDF out of an archive
  /// lives on it: rendering forty pages before showing the first one is a wait
  /// with nothing on screen, and page one is ready in a fraction of the time
  /// the whole file takes.
  ///
  /// [isCancelled] is polled between pages, which is what lets the reader be
  /// backed out of without leaving a rasterisation running behind it. It cannot
  /// interrupt a page already being rendered; nothing here can.
  Future<List<String>> rasterize({
    required Uint8List bytes,
    required Directory targetDirectory,
    required String prefix,
    void Function()? onPageLimitReached,
    void Function(int index, String path)? onPage,
    bool Function()? isCancelled,
  }) async {
    final pages = <String>[];
    var index = 0;

    if (pageLimit <= 0) return pages;

    await for (final raster in Printing.raster(bytes, dpi: dpi.toDouble())) {
      // Checked before the work rather than after it, so a cancelled reader
      // stops at the page it is on instead of one page later.
      if (isCancelled?.call() ?? false) break;

      if (index >= pageLimit) {
        // Reached only by receiving a page past the limit, so this is proof
        // there were more rather than a guess from a full-looking result. A
        // file of exactly [pageLimit] pages lost nothing and must not be told
        // it did.
        onPageLimitReached?.call();
        break;
      }

      // Rendered as PNG, stored as JPEG. Every page in the app is a JPEG —
      // `AppConstants.pageFileNameFor` says so, the PDF export assumes it, and
      // a lone PNG wearing a .jpg name would be a trap for whichever of them
      // stopped sniffing the bytes first.
      final png = File(p.join(targetDirectory.path, '${prefix}_$index.png'));
      await png.writeAsBytes(await raster.toPng(), flush: true);

      final jpeg = await _normalize(
        sourcePath: png.path,
        targetPath: p.join(targetDirectory.path, '${prefix}_$index.jpg'),
      );

      // The intermediate is of no interest to anyone once converted, and a
      // temp directory that only ever grows is a bug on a device with a full
      // disk.
      if (png.existsSync()) await png.delete();

      if (jpeg != null) {
        pages.add(jpeg);
        onPage?.call(pages.length - 1, jpeg);
      }
      index++;
    }

    return pages;
  }
}
