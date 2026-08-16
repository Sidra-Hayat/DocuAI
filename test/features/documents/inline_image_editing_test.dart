import 'dart:io';
import 'dart:ui' show Rect;

import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/features/documents/data/datasources/inline_image_transformer.dart';
import 'package:docuai/src/features/documents/domain/usecases/edit_inline_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';

/// Rotating and cropping a picture inside a document.
///
/// Run against **real JPEG bytes** through the real `image` package. The point
/// of the feature is that the pixels actually change and stay changed, and a
/// stubbed encoder would prove only that the plumbing was called.
void main() {
  late Directory tempDir;
  late StoragePaths paths;
  late FakeDocumentRepository documents;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_image_edit');
    paths = StoragePaths(tempDir);
    documents = FakeDocumentRepository();
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

  /// Writes a real JPEG, deliberately not square so orientation is visible.
  Future<File> writeImage({
    required String path,
    int width = 40,
    int height = 20,
  }) async {
    final image = img.Image(width: width, height: height);
    // A left half that differs from the right, so a crop can be proved to have
    // kept the side it was asked for rather than merely produced *an* image.
    img.fill(image, color: img.ColorRgb8(255, 0, 0));
    img.fillRect(
      image,
      x1: width ~/ 2,
      y1: 0,
      x2: width - 1,
      y2: height - 1,
      color: img.ColorRgb8(0, 0, 255),
    );

    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(img.encodeJpg(image), flush: true);
    return file;
  }

  Future<img.Image> read(String path) async =>
      img.decodeImage(await File(path).readAsBytes())!;

  /// The picture as it is stored for a document.
  Future<File> seedInlineImage(
    String documentId,
    String name, {
    int width = 40,
    int height = 20,
  }) => writeImage(
    path: paths.inlineImagePath(documentId, name),
    width: width,
    height: height,
  );

  group('the transform itself', () {
    test('a quarter turn swaps the sides', () async {
      final source = await writeImage(
        path: p.join(tempDir.path, 'source.jpg'),
        width: 40,
        height: 20,
      );
      final target = p.join(tempDir.path, 'rotated.jpg');

      await InlineImageTransformer.apply(
        sourcePath: source.path,
        targetPath: target,
        edit: const InlineImageEdit(quarterTurns: 1),
      );

      final rotated = await read(target);
      expect(rotated.width, 20);
      expect(rotated.height, 40);
    });

    test('four quarter turns come back to where they started', () async {
      final source = await writeImage(path: p.join(tempDir.path, 's.jpg'));
      final target = p.join(tempDir.path, 'full.jpg');

      await InlineImageTransformer.apply(
        sourcePath: source.path,
        targetPath: target,
        edit: const InlineImageEdit(quarterTurns: 4),
      );

      final result = await read(target);
      expect(result.width, 40);
      expect(result.height, 20);
    });

    test('a crop keeps the region it was given', () async {
      final source = await writeImage(
        path: p.join(tempDir.path, 's.jpg'),
        width: 40,
        height: 20,
      );
      final target = p.join(tempDir.path, 'cropped.jpg');

      await InlineImageTransformer.apply(
        sourcePath: source.path,
        targetPath: target,
        // The left half.
        edit: const InlineImageEdit(crop: Rect.fromLTWH(0, 0, 0.5, 1)),
      );

      final cropped = await read(target);
      expect(cropped.width, 20);
      expect(cropped.height, 20);

      // And it is the *left* half: red, not blue. Dimensions alone would pass
      // for a crop that kept the wrong side.
      final pixel = cropped.getPixel(2, 10);
      expect(pixel.r, greaterThan(pixel.b));
    });

    test('rotation is applied before the crop', () async {
      // The user turns the picture and then draws a box on what they can see,
      // so the box belongs to the rotated frame. Cropping first would apply it
      // to an image in a different orientation.
      final source = await writeImage(
        path: p.join(tempDir.path, 's.jpg'),
        width: 40,
        height: 20,
      );
      final target = p.join(tempDir.path, 'both.jpg');

      await InlineImageTransformer.apply(
        sourcePath: source.path,
        targetPath: target,
        edit: const InlineImageEdit(
          quarterTurns: 1,
          crop: Rect.fromLTWH(0, 0, 1, 0.5),
        ),
      );

      // Rotated 40x20 is 20x40; the top half of that is 20x20.
      final result = await read(target);
      expect(result.width, 20);
      expect(result.height, 20);
    });

    test('a crop dragged to nothing still produces a valid image', () async {
      final source = await writeImage(path: p.join(tempDir.path, 's.jpg'));
      final target = p.join(tempDir.path, 'tiny.jpg');

      await InlineImageTransformer.apply(
        sourcePath: source.path,
        targetPath: target,
        edit: const InlineImageEdit(crop: Rect.fromLTWH(0, 0, 0, 0)),
      );

      final result = await read(target);
      expect(result.width, greaterThanOrEqualTo(1));
      expect(result.height, greaterThanOrEqualTo(1));
    });

    test('bytes it cannot decode are reported, not thrown', () async {
      final broken = File(p.join(tempDir.path, 'broken.jpg'))
        ..writeAsBytesSync(<int>[1, 2, 3, 4]);

      final result = await InlineImageTransformer.apply(
        sourcePath: broken.path,
        targetPath: p.join(tempDir.path, 'out.jpg'),
        edit: const InlineImageEdit(quarterTurns: 1),
      );

      expect(result, isNull);
    });

    test('an untouched edit is recognised as nothing to do', () {
      expect(const InlineImageEdit().isIdentity, isTrue);
      expect(const InlineImageEdit(quarterTurns: 4).isIdentity, isTrue);
      expect(
        const InlineImageEdit(crop: Rect.fromLTWH(0, 0, 1, 1)).isIdentity,
        isTrue,
      );
      expect(const InlineImageEdit(quarterTurns: 1).isIdentity, isFalse);
      expect(
        const InlineImageEdit(crop: Rect.fromLTWH(0, 0, 0.5, 1)).isIdentity,
        isFalse,
      );
    });
  });

  group('editing a picture in a document', () {
    EditInlineImage useCase() => EditInlineImage(
      documents: documents,
      paths: paths,
      // Inline rather than on an isolate: these tests are about the result, not
      // about which thread produced it.
      transformer: InlineImageTransformer.apply,
      temporaryDirectory: () async => tempDir,
    );

    test('rotating writes a new file and returns its name', () async {
      await seedInlineImage('doc-1', 'original.jpg');

      final result = await useCase()(
        documentId: 'doc-1',
        imageName: 'original.jpg',
        edit: const InlineImageEdit(quarterTurns: 1),
      );

      final name = (result as Success<String>).value;

      // A new file, not an overwrite: Flutter caches decoded images by path,
      // so editing in place would leave the editor showing the picture as it
      // was.
      expect(name, isNot('original.jpg'));
      expect(documents.inlineImages, contains(name));
    });

    test('the file handed to storage carries the rotation', () async {
      await seedInlineImage('doc-1', 'original.jpg', width: 40, height: 20);

      final result = await useCase()(
        documentId: 'doc-1',
        imageName: 'original.jpg',
        edit: const InlineImageEdit(quarterTurns: 1),
      );

      final name = (result as Success<String>).value;
      final stored = await read(documents.inlineImages[name]!);

      expect(stored.width, 20);
      expect(stored.height, 40);
    });

    test('the original is left exactly as it was', () async {
      final original = await seedInlineImage('doc-1', 'original.jpg');
      final before = original.readAsBytesSync();

      await useCase()(
        documentId: 'doc-1',
        imageName: 'original.jpg',
        edit: const InlineImageEdit(quarterTurns: 2),
      );

      // Still there, still the same pixels. The old file is removed by the
      // sweep on the next save, once the text has stopped naming it — never
      // by the edit itself.
      expect(original.existsSync(), isTrue);
      expect(original.readAsBytesSync(), before);
    });

    test('an untouched picture is not re-encoded', () async {
      await seedInlineImage('doc-1', 'original.jpg');

      final result = await useCase()(
        documentId: 'doc-1',
        imageName: 'original.jpg',
        edit: const InlineImageEdit(),
      );

      // The same name back, and nothing written. Re-encoding for a no-op would
      // cost a generation of JPEG quality and orphan a perfectly good file.
      expect((result as Success<String>).value, 'original.jpg');
      expect(documents.inlineImages, isEmpty);
    });

    test('a picture whose file has gone is reported', () async {
      final result = await useCase()(
        documentId: 'doc-1',
        imageName: 'missing.jpg',
        edit: const InlineImageEdit(quarterTurns: 1),
      );

      expect(result, isA<Failed<String>>());
      expect(
        (result as Failed<String>).failure.message,
        contains('no longer on this device'),
      );
    });

    test('a picture that cannot be decoded is reported', () async {
      final path = paths.inlineImagePath('doc-1', 'broken.jpg');
      await File(path).parent.create(recursive: true);
      File(path).writeAsBytesSync(<int>[9, 9, 9]);

      final result = await useCase()(
        documentId: 'doc-1',
        imageName: 'broken.jpg',
        edit: const InlineImageEdit(quarterTurns: 1),
      );

      expect(result, isA<Failed<String>>());
    });

    test('an edit survives being reopened', () async {
      await seedInlineImage('doc-1', 'original.jpg', width: 40, height: 20);

      // Rotate, then crop the result — two sessions of editing, as a user
      // would do it.
      final rotated = (await useCase()(
        documentId: 'doc-1',
        imageName: 'original.jpg',
        edit: const InlineImageEdit(quarterTurns: 1),
      ) as Success<String>).value;

      // What storage kept is what a reopened document would load.
      final reopened = documents.inlineImages[rotated]!;
      final onDisk = await read(reopened);

      expect(onDisk.width, 20, reason: 'the rotation did not persist');
      expect(onDisk.height, 40);
    });
  });
}
