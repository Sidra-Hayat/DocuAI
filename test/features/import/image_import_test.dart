import 'dart:io';

import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/import/data/datasources/imported_image_normalizer.dart';
import 'package:docuai/src/features/import/data/repositories/image_import_repository_impl.dart';
import 'package:docuai/src/features/import/domain/repositories/image_import_repository.dart';
import 'package:docuai/src/features/import/domain/usecases/import_images.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';

/// Bringing photos in from the device.
///
/// A gallery photo differs from a scan in ways that cause real defects rather
/// than untidiness — rotation held in EXIF, eight megabytes per page, a format
/// the PDF composer cannot draw. Normalisation is where those are dealt with,
/// so most of this is about what comes out the other side.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_import');
  });

  tearDown(() async {
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } on FileSystemException {
      // Windows may still hold a handle; the OS reclaims it.
    }
  });

  Future<String> writeImage(
    String name, {
    int width = 40,
    int height = 60,
    List<int>? raw,
  }) async {
    final file = File(p.join(tempDir.path, name));
    await file.writeAsBytes(
      raw ?? img.encodePng(img.Image(width: width, height: height)),
    );
    return file.path;
  }

  group('normalising', () {
    test('anything the app can decode comes out as a JPEG', () async {
      // A PNG from the gallery would otherwise be stored under a .jpg name and
      // handed to a PDF composer that cannot draw it.
      final source = await writeImage('shot.png');
      final target = p.join(tempDir.path, 'out.jpg');

      final written = await ImportedImageNormalizer.normalize(
        sourcePath: source,
        targetPath: target,
      );

      expect(written, target);
      final decoded = img.decodeImage(await File(target).readAsBytes());
      expect(decoded, isNotNull);
      expect(img.findDecoderForData(await File(target).readAsBytes()),
          isA<img.JpegDecoder>());
    });

    test('an oversized photo is brought down to a sane edge', () async {
      final source = await writeImage('big.png', width: 4000, height: 3000);
      final target = p.join(tempDir.path, 'big.jpg');

      await ImportedImageNormalizer.normalize(
        sourcePath: source,
        targetPath: target,
      );

      final decoded = img.decodeImage(await File(target).readAsBytes())!;
      expect(decoded.width, ImportedImageNormalizer.maxEdge);
      expect(
        decoded.height,
        lessThan(ImportedImageNormalizer.maxEdge),
        reason: 'the aspect ratio has to survive the resize',
      );
    });

    test('a photo already small enough is left at its size', () async {
      final source = await writeImage('small.png', width: 800, height: 600);
      final target = p.join(tempDir.path, 'small.jpg');

      await ImportedImageNormalizer.normalize(
        sourcePath: source,
        targetPath: target,
      );

      final decoded = img.decodeImage(await File(target).readAsBytes())!;
      expect(decoded.width, 800);
      expect(decoded.height, 600);
    });

    test('a portrait photo is measured on its long edge', () async {
      final source = await writeImage('tall.png', width: 1500, height: 4000);
      final target = p.join(tempDir.path, 'tall.jpg');

      await ImportedImageNormalizer.normalize(
        sourcePath: source,
        targetPath: target,
      );

      final decoded = img.decodeImage(await File(target).readAsBytes())!;
      expect(decoded.height, ImportedImageNormalizer.maxEdge);
      expect(decoded.width, lessThan(ImportedImageNormalizer.maxEdge));
    });

    test('bytes that cannot be decoded are reported, not thrown', () async {
      // HEIC is the everyday case: Android hands it over and this app cannot
      // read it. Throwing would lose the whole batch.
      final source = await writeImage(
        'photo.heic',
        raw: <int>[0, 1, 2, 3, 4, 5, 6, 7],
      );

      final written = await ImportedImageNormalizer.normalize(
        sourcePath: source,
        targetPath: p.join(tempDir.path, 'out.jpg'),
      );

      expect(written, isNull);
    });
  });

  group('picking', () {
    /// Stands in for the platform picker.
    ImageImportRepositoryImpl repositoryReturning(
      List<String> paths, {
      Set<String> undecodable = const <String>{},
    }) => ImageImportRepositoryImpl(
      picker: ({int? limit}) async => paths.map(XFile.new).toList(),
      normalizer: ({required sourcePath, required targetPath}) async =>
          undecodable.contains(p.basename(sourcePath)) ? null : targetPath,
      temporaryDirectory: () async => tempDir,
    );

    test('dismissing the picker is a success with nothing in it', () async {
      final result = await repositoryReturning(<String>[]).pickImages();

      expect(result, isA<Success<ImportOutcome>>());
      expect(result.valueOrNull!.isEmpty, isTrue);
      expect(
        result.valueOrNull!.hasRejections,
        isFalse,
        reason: 'cancelling is not an error and has nothing to report',
      );
    });

    test('one unreadable photo does not cost the others', () async {
      final result = await repositoryReturning(
        <String>[
          p.join(tempDir.path, 'a.jpg'),
          p.join(tempDir.path, 'b.heic'),
          p.join(tempDir.path, 'c.jpg'),
        ],
        undecodable: <String>{'b.heic'},
      ).pickImages();

      final outcome = result.valueOrNull!;
      expect(outcome.imagePaths, hasLength(2));
      expect(
        outcome.rejected,
        <String>['b.heic'],
        reason: 'named, so the user knows which one to convert',
      );
    });

    test('nothing decodable is still a success carrying the rejections', () async {
      final result = await repositoryReturning(
        <String>[p.join(tempDir.path, 'a.heic')],
        undecodable: <String>{'a.heic'},
      ).pickImages();

      expect(result.valueOrNull!.isEmpty, isTrue);
      expect(result.valueOrNull!.hasRejections, isTrue);
    });
  });

  group('becoming a document', () {
    late FakeDocumentRepository documents;
    late FakeSearchRepository search;

    setUp(() {
      documents = FakeDocumentRepository();
      search = FakeSearchRepository();
    });

    tearDown(() => documents.dispose());

    test('imported pages say where they came from', () async {
      final result = await ImportImagesAsDocument(
        importer: _FakeImporter(
          const ImportOutcome(imagePaths: <String>['/tmp/a.jpg']),
        ),
        documents: documents,
      )(title: 'Imported today');

      final document = result.valueOrNull!.document;
      expect(document.source, DocumentSource.imported);
      expect(document.pages.single.kind, PageKind.imported);
      expect(
        document.pages.single.ocrStatus,
        OcrStatus.pending,
        reason: 'an imported photo has not been read any more than a scan has',
      );
    });

    test('choosing nothing is reported silently', () async {
      final result = await ImportImagesAsDocument(
        importer: _FakeImporter(const ImportOutcome(imagePaths: <String>[])),
        documents: documents,
      )(title: 'Imported');

      final failure = (result as Failed<ImportResult>).failure;
      expect(failure, isA<ImportFailure>());
      expect((failure as ImportFailure).cancelled, isTrue);
    });

    test('choosing photos that all failed is reported out loud', () async {
      // The user did pick something. Saying nothing would look like the app
      // ignored the tap.
      final result = await ImportImagesAsDocument(
        importer: _FakeImporter(
          const ImportOutcome(
            imagePaths: <String>[],
            rejected: <String>['a.heic'],
          ),
        ),
        documents: documents,
      )(title: 'Imported');

      final failure = (result as Failed<ImportResult>).failure as ImportFailure;
      expect(failure.cancelled, isFalse);
    });

    test('importing into an existing document appends and re-indexes', () async {
      documents.seed(buildDocument(id: 'doc'));

      final result = await ImportImagesIntoDocument(
        importer: _FakeImporter(
          const ImportOutcome(imagePaths: <String>['/tmp/a.jpg']),
        ),
        documents: documents,
        search: search,
      )('doc');

      final document = result.valueOrNull!.document;
      expect(document.pages, hasLength(2));
      expect(document.pages.last.kind, PageKind.imported);
      expect(search.indexedIds, contains('doc'));
      expect(
        document.pdfPath,
        isNull,
        reason: 'a new page makes any exported PDF stale',
      );
    });

    test('a partial import still produces the document', () async {
      final result = await ImportImagesAsDocument(
        importer: _FakeImporter(
          const ImportOutcome(
            imagePaths: <String>['/tmp/a.jpg'],
            rejected: <String>['b.heic'],
          ),
        ),
        documents: documents,
      )(title: 'Imported');

      expect(result.valueOrNull!.document.pages, hasLength(1));
      expect(result.valueOrNull!.rejected, <String>['b.heic']);
    });
  });
}

class _FakeImporter implements ImageImportRepository {
  const _FakeImporter(this._outcome);

  final ImportOutcome _outcome;

  @override
  FutureResult<ImportOutcome> pickImages({int limit = 30}) async =>
      Success(_outcome);
}
