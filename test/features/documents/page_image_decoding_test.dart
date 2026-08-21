import 'dart:io';

import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/core/widgets/page_image_decoding.dart';
import 'package:docuai/src/features/documents/presentation/widgets/document_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';

/// Page images must be decoded at the size they are drawn.
///
/// The blank-pages bug: every stored page is a full-size JPEG — up to 2400
/// pixels on its long edge — and `Image.file` decodes a file at its intrinsic
/// size however small the box is. One page is about 16 MB of bitmap, Flutter's
/// image cache holds 100 MB, and a library list asks for dozens at once. The
/// cache thrashes, the decode queue backs up, and an `Image` with nothing to
/// paint yet paints nothing at all — blank boxes where the pages should be.
///
/// These tests hold the fix in place at the two things that can silently
/// regress: the arithmetic, and whether the widgets actually ask for it.
void main() {
  group('pageDecodeExtent', () {
    testWidgets('scales the box by the display density', (tester) async {
      late int forThumbnail;
      late int forStrip;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 3),
          child: Builder(
            builder: (context) {
              forThumbnail = pageDecodeExtent(context, 72);
              forStrip = pageDecodeExtent(context, 340);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(forThumbnail, 216);
      expect(forStrip, 1020);
    });

    testWidgets('rounds up, so a page is never upscaled by a fraction', (
      tester,
    ) async {
      late int extent;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 2.75),
          child: Builder(
            builder: (context) {
              extent = pageDecodeExtent(context, 54);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // 54 × 2.75 = 148.5. Rounding down would leave the box half a pixel
      // short and `cover` would stretch to fill it.
      expect(extent, 149);
    });

    testWidgets('stays far below a full-size page', (tester) async {
      late int extent;

      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(devicePixelRatio: 3),
          child: Builder(
            builder: (context) {
              extent = pageDecodeExtent(context, 72);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // The number that matters: a stored page is 2400 on its long edge, and
      // decoding is quadratic in it. 216 against 2400 is roughly a hundredth
      // of the memory, which is the difference between six pages fitting in
      // the cache and all of them fitting.
      expect(extent, lessThan(2400 ~/ 10));
    });
  });

  group('DocumentThumbnail', () {
    late Directory workspace;
    late StoragePaths paths;

    setUp(() async {
      workspace = await Directory.systemTemp.createTemp('docuai_thumb');
      paths = StoragePaths(workspace);

      // A real JPEG on disk, larger than the box, so the decode path is the
      // one the app actually runs.
      final dir = Directory(p.join(workspace.path, 'documents', 'doc-1'))
        ..createSync(recursive: true);
      File(p.join(dir.path, 'page_000.jpg')).writeAsBytesSync(
        img.encodeJpg(img.Image(width: 900, height: 1200), quality: 80),
      );
    });

    tearDown(() async {
      if (workspace.existsSync()) await workspace.delete(recursive: true);
    });

    Future<void> pump(WidgetTester tester, {required double devicePixelRatio}) {
      return tester.pumpWidget(
        ProviderScope(
          overrides: [storagePathsProvider.overrideWithValue(paths)],
          child: MediaQuery(
            data: MediaQueryData(devicePixelRatio: devicePixelRatio),
            child: const Directionality(
              textDirection: TextDirection.ltr,
              child: DocumentThumbnail(
                page: null,
                width: 56,
                height: 72,
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('asks for a thumbnail-sized decode, not a page-sized one', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [storagePathsProvider.overrideWithValue(paths)],
          child: MediaQuery(
            data: const MediaQueryData(devicePixelRatio: 3),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: DocumentThumbnail(
                page: buildPage(imagePath: 'documents/doc-1/page_000.jpg'),
                width: 56,
                height: 72,
              ),
            ),
          ),
        ),
      );

      final image = tester.widget<Image>(find.byType(Image));
      final provider = image.image as ResizeImage;

      // The longer side of the box, because the fit is `cover`.
      expect(provider.width, 216);

      // And only one dimension: `ResizeImage` defaults to
      // `ResizeImagePolicy.exact`, which stretches the picture to both when
      // both are given.
      expect(provider.height, isNull);
    });

    testWidgets('a page with no image still renders its fallback', (
      tester,
    ) async {
      await pump(tester, devicePixelRatio: 3);

      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    });
  });
}
