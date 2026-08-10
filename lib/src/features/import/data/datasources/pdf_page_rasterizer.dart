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
  }) : _normalize = normalizer;

  final ImageNormalizer _normalize;

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
  Future<List<String>> rasterize({
    required Uint8List bytes,
    required Directory targetDirectory,
    required String prefix,
  }) async {
    final pages = <String>[];
    var index = 0;

    await for (final raster in Printing.raster(bytes, dpi: dpi.toDouble())) {
      if (index >= maxPages) break;

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

      if (jpeg != null) pages.add(jpeg);
      index++;
    }

    return pages;
  }
}
