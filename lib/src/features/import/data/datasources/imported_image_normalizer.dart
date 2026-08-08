import 'dart:io';
import 'dart:isolate';

import 'package:image/image.dart' as img;

/// Turns a photo from the gallery into something the rest of the app can treat
/// exactly like a scan.
///
/// A scanner hands over a corrected, modestly-sized JPEG. A gallery photo does
/// not, and three of the differences cause real defects rather than untidiness:
///
///  * **Orientation.** A phone photo records its rotation in EXIF rather than
///    in the pixels. Left as-is it renders sideways in the viewer *and* in the
///    exported PDF, because neither reads EXIF.
///  * **Size.** A 12 MP photo is 4–8 MB. Twenty of them is a document larger
///    than the rest of the library, on a device with no way to reclaim it.
///  * **Format and metadata.** Re-encoding guarantees the JPEG that
///    `AppConstants.pageFileNameFor` already assumes and `pw.MemoryImage`
///    needs — and drops the EXIF GPS tag, which a scanner never produces and
///    an offline app has no business keeping.
abstract final class ImportedImageNormalizer {
  /// Longest edge kept, in pixels.
  ///
  /// Comfortably above what text recognition needs — ML Kit asks for a good
  /// deal less — while bounding a page at a few hundred kilobytes.
  static const int maxEdge = 2400;

  static const int jpegQuality = 88;

  /// Reads [sourcePath], normalises it, and writes a JPEG to [targetPath].
  ///
  /// Returns null when the bytes cannot be decoded. That is not an error to
  /// abort the batch with: the caller names the file and imports the rest.
  /// HEIC is the common case — Android hands it over happily and the `image`
  /// package cannot read it.
  static Future<String?> normalize({
    required String sourcePath,
    required String targetPath,
  }) async {
    final bytes = await File(sourcePath).readAsBytes();

    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    // Orientation first: resizing a sideways image would keep it sideways and
    // pick the wrong edge to measure.
    final upright = img.bakeOrientation(decoded);
    final longest = upright.width > upright.height
        ? upright.width
        : upright.height;

    final sized = longest <= maxEdge
        ? upright
        : img.copyResize(
            upright,
            width: upright.width >= upright.height ? maxEdge : null,
            height: upright.height > upright.width ? maxEdge : null,
            interpolation: img.Interpolation.average,
          );

    await File(
      targetPath,
    ).writeAsBytes(img.encodeJpg(sized, quality: jpegQuality), flush: true);

    return targetPath;
  }
}

/// How normalisation runs. Injected so tests do not pay an isolate spawn per
/// image, the same shape as `PdfRenderer`.
typedef ImageNormalizer =
    Future<String?> Function({
      required String sourcePath,
      required String targetPath,
    });

/// Decodes and re-encodes on a background isolate.
///
/// A 12 MP decode plus a resize plus a JPEG encode is hundreds of milliseconds
/// of CPU per image. On the UI isolate a ten-photo import would freeze the app
/// for several seconds; the work is pure Dart, so moving it costs only the hop.
Future<String?> normalizeInIsolate({
  required String sourcePath,
  required String targetPath,
}) => Isolate.run(
  () => ImportedImageNormalizer.normalize(
    sourcePath: sourcePath,
    targetPath: targetPath,
  ),
);
