import 'package:flutter/widgets.dart';

/// How large a page image should actually be *decoded*, for a box that will
/// draw it at [logicalExtent].
///
/// **This exists because of the blank-pages bug.** Every page DocuAI stores is
/// a full-size JPEG — the importer and the scanner both cap the long edge at
/// `ImportedImageNormalizer.maxEdge`, which is 2400 pixels — and `Image.file`
/// decodes a file at its intrinsic size no matter how small the box drawing it
/// is. A 1700×2400 page becomes 1700 × 2400 × 4 bytes ≈ **16 MB of decoded
/// bitmap** whether it is filling the screen or sitting in a 56×72 thumbnail.
///
/// Flutter's `ImageCache` holds 100 MB, so roughly six pages fit in it at once.
/// A library of forty documents, a document of thirty pages, or the page strip
/// of anything long therefore asks for far more than the cache can hold: images
/// are evicted as fast as they are decoded, the decode queue backs up behind
/// dozens of full-size JPEGs, and an `Image` that has nothing to paint yet
/// paints *nothing at all* — there is no placeholder. The user sees blank
/// pages, for many seconds, and worse the more pages there are.
///
/// Decoding at the size actually drawn fixes it at the source. The same
/// thumbnail at 56×72 on a 3× screen needs 168×216 pixels — about 145 KB, a
/// hundredfold less — so every visible page fits in the cache with room to
/// spare and decodes almost instantly.
///
/// **Only ever one dimension.** `Image.file`'s `cacheWidth`/`cacheHeight` build
/// a `ResizeImage` with the default [ResizeImagePolicy.exact], and that policy
/// decodes to *both* given dimensions exactly — stretching the picture, like
/// `BoxFit.fill`, when the box's aspect ratio differs from the page's. Passing
/// a single dimension keeps the original proportions, which is why every call
/// site here passes exactly one and lets the other follow.
///
/// Full-screen viewing and the image editor deliberately do **not** use this:
/// there the pixels are the point — the viewer zooms to 6× and the editor
/// writes the result back — and there is only ever one such image alive.
int pageDecodeExtent(BuildContext context, double logicalExtent) {
  final ratio = MediaQuery.devicePixelRatioOf(context);

  // Rounded up rather than down: a page decoded one pixel short of its box is
  // a page being upscaled, and upscaling a scan of small print is visible.
  return (logicalExtent * ratio).ceil();
}
