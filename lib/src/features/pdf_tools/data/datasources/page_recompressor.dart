import 'dart:io';
import 'dart:isolate';

import 'package:image/image.dart' as img;

/// Re-encodes one page image smaller.
///
/// Deliberately the same two operations `ImportedImageNormalizer` performs —
/// bound the long edge, re-encode as JPEG — with the numbers taken from the
/// level the user chose rather than fixed. Compression in this app is not a
/// separate technique; it is the normaliser run again, harder.
///
/// What it does *not* do is touch the source. Every caller writes to a fresh
/// path in a scratch directory, so a failed run leaves the document it was
/// given exactly as it was.
abstract final class PageRecompressor {
  /// Reads [sourcePath] and writes a smaller JPEG to [targetPath].
  ///
  /// Returns null when the bytes cannot be decoded, which the caller reports
  /// against the page rather than aborting the whole document.
  static Future<String?> recompress({
    required String sourcePath,
    required String targetPath,
    required int maxEdge,
    required int quality,
  }) async {
    final bytes = await File(sourcePath).readAsBytes();

    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    final longest = decoded.width > decoded.height
        ? decoded.width
        : decoded.height;

    // Only ever downwards. Enlarging a page that is already smaller than the
    // target would add bytes to a file the user asked to make smaller, which is
    // the one thing this function must not do.
    final sized = longest <= maxEdge
        ? decoded
        : img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? maxEdge : null,
            height: decoded.height > decoded.width ? maxEdge : null,
            interpolation: img.Interpolation.average,
          );

    await File(
      targetPath,
    ).writeAsBytes(img.encodeJpg(sized, quality: quality), flush: true);

    return targetPath;
  }
}

/// How recompression runs. Injected so tests do not pay an isolate spawn per
/// page, the same shape as `ImageNormalizer`.
typedef PageCompressor =
    Future<String?> Function({
      required String sourcePath,
      required String targetPath,
      required int maxEdge,
      required int quality,
    });

/// Decodes and re-encodes on a background isolate.
///
/// A decode, a resize and a JPEG encode is hundreds of milliseconds per page.
/// Compressing a forty-page statement on the UI isolate would freeze the app
/// for most of a minute — and this is precisely the screen showing a progress
/// bar, which cannot advance if the thread that paints it is busy.
Future<String?> recompressInIsolate({
  required String sourcePath,
  required String targetPath,
  required int maxEdge,
  required int quality,
}) => Isolate.run(
  () => PageRecompressor.recompress(
    sourcePath: sourcePath,
    targetPath: targetPath,
    maxEdge: maxEdge,
    quality: quality,
  ),
);
