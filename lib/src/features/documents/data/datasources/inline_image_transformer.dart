import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show Rect;

import 'package:image/image.dart' as img;

/// What the image editor asks for: a quarter-turn count and a crop window.
///
/// Plain data with no Flutter in it beyond [Rect], so the whole transform can
/// be described, compared and tested without a widget.
class InlineImageEdit {
  const InlineImageEdit({this.quarterTurns = 0, this.crop});

  /// Clockwise 90° steps. Normalised to 0–3 by [isIdentity] and the transformer.
  final int quarterTurns;

  /// The kept region, in fractions of the **rotated** image, or null to keep
  /// all of it.
  ///
  /// Fractions rather than pixels because the crop is chosen on a preview
  /// scaled to fit a phone screen, and the same gesture has to mean the same
  /// thing whatever that preview happened to measure.
  ///
  /// Of the rotated image specifically: the user turns the picture and then
  /// draws a box on what they can see, so the box is in the coordinates of what
  /// they were looking at.
  final Rect? crop;

  bool get isIdentity {
    if (quarterTurns % 4 != 0) return false;
    final window = crop;
    if (window == null) return true;

    // A crop that keeps essentially the whole frame is not a crop. Re-encoding
    // for it would cost the user a generation of JPEG quality for nothing.
    const tolerance = 0.001;
    return window.left <= tolerance &&
        window.top <= tolerance &&
        window.right >= 1 - tolerance &&
        window.bottom >= 1 - tolerance;
  }
}

/// Rotates and crops a page picture, offline.
///
/// Uses the `image` package, which is already a dependency — it is what
/// normalises every imported photo and every rasterised PDF page. No native
/// cropper is added: `image_cropper` would bring uCrop, an extra activity in
/// the manifest and a second way of writing JPEGs into a release that already
/// has one.
abstract final class InlineImageTransformer {
  /// Quality the edited page is re-encoded at.
  ///
  /// Matches `ImportedImageNormalizer.jpegQuality`, so a picture that is
  /// rotated and never touched again is the same quality as one that was only
  /// ever imported.
  static const int jpegQuality = 88;

  /// Reads [sourcePath], applies [edit], and writes a JPEG to [targetPath].
  ///
  /// Returns null when the bytes cannot be decoded, which the caller reports
  /// against the picture rather than crashing the editor.
  ///
  /// **Rotate first, then crop.** The crop window is expressed against what the
  /// user was looking at, and what they were looking at was already rotated;
  /// cropping first would apply their box to a frame in a different orientation.
  static Future<String?> apply({
    required String sourcePath,
    required String targetPath,
    required InlineImageEdit edit,
  }) async {
    final bytes = await File(sourcePath).readAsBytes();

    // `decodeImage` is documented as returning null for bytes it cannot read,
    // and for some inputs it throws instead: it sniffs the format by asking
    // each decoder in turn, and the PSD one reads past the end of a buffer
    // only a few bytes long. A truncated page image would take the editor down
    // with it, so both outcomes are treated as the same answer — no picture.
    final img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      return null;
    }

    if (decoded == null) return null;

    var working = decoded;

    final turns = edit.quarterTurns % 4;
    if (turns != 0) {
      working = img.copyRotate(working, angle: turns * 90);
    }

    final window = edit.crop;
    if (window != null) {
      final x = (window.left * working.width).round().clamp(
        0,
        working.width - 1,
      );
      final y = (window.top * working.height).round().clamp(
        0,
        working.height - 1,
      );
      // At least one pixel in each direction: a crop dragged to nothing would
      // otherwise ask the encoder for a zero-width image and throw.
      final width = (window.width * working.width).round().clamp(
        1,
        working.width - x,
      );
      final height = (window.height * working.height).round().clamp(
        1,
        working.height - y,
      );

      working = img.copyCrop(
        working,
        x: x,
        y: y,
        width: width,
        height: height,
      );
    }

    await File(
      targetPath,
    ).writeAsBytes(img.encodeJpg(working, quality: jpegQuality), flush: true);

    return targetPath;
  }
}

/// How the transform runs. Injected so tests do not pay an isolate spawn, the
/// same shape as `ImageNormalizer` and `PageCompressor`.
typedef InlineImageEditor =
    Future<String?> Function({
      required String sourcePath,
      required String targetPath,
      required InlineImageEdit edit,
    });

/// Decodes, transforms and re-encodes on a background isolate.
///
/// A decode plus a rotate plus an encode on a 2400px page is several hundred
/// milliseconds. On the UI isolate that is the Save button appearing to hang,
/// on the one screen where the user is watching a picture waiting for it to
/// change.
Future<String?> transformInIsolate({
  required String sourcePath,
  required String targetPath,
  required InlineImageEdit edit,
}) => Isolate.run(
  () => InlineImageTransformer.apply(
    sourcePath: sourcePath,
    targetPath: targetPath,
    edit: edit,
  ),
);
