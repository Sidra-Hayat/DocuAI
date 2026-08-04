import 'dart:io';

import 'package:docuai/src/core/error/exceptions.dart';
import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/features/ocr/data/datasources/mlkit_text_recognizer.dart';
import 'package:docuai/src/features/ocr/data/repositories/ocr_repository_impl.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('google_mlkit_text_recognizer');

  late Directory tempDir;
  late StoragePaths paths;
  late MlKitTextRecognizer recognizer;
  late List<MethodCall> calls;

  /// Writes a stand-in page image and returns the relative path the way a
  /// `DocumentPage` would hold it.
  Future<String> writePage(String name) async {
    final file = File(p.join(tempDir.path, 'documents', 'doc-1', name));
    await file.parent.create(recursive: true);
    await file.writeAsBytes(<int>[0xFF, 0xD8, 0xFF, 0xD9]);
    return paths.relativePath(file.path);
  }

  void mockChannel(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(() async {
    calls = <MethodCall>[];
    tempDir = await Directory.systemTemp.createTemp('docuai_ocr_test');
    paths = StoragePaths(tempDir);
    recognizer = MlKitTextRecognizer(paths: paths);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('MlKitTextRecognizer', () {
    test('returns the recognised text', () async {
      mockChannel(
        (call) async => <dynamic, dynamic>{
          'text': 'Total due: 42.00 EUR',
          'blocks': <dynamic>[],
        },
      );

      expect(
        await recognizer.recognize(await writePage('page_000.jpg')),
        'Total due: 42.00 EUR',
      );
    });

    test('resolves the stored relative path before calling ML Kit', () async {
      mockChannel(
        (call) async => <dynamic, dynamic>{'text': '', 'blocks': <dynamic>[]},
      );
      final relative = await writePage('page_000.jpg');

      await recognizer.recognize(relative);

      final start = calls.firstWhere(
        (call) => call.method == 'vision#startTextRecognizer',
      );
      final imageData = (start.arguments as Map)['imageData'] as Map;

      expect(p.isAbsolute(imageData['path'] as String), isTrue);
      expect(imageData['path'], p.join(tempDir.path, relative));
    });

    test('empty text is a valid result, not an error', () async {
      mockChannel(
        (call) async => <dynamic, dynamic>{'text': '', 'blocks': <dynamic>[]},
      );

      expect(await recognizer.recognize(await writePage('page_000.jpg')), '');
    });

    test('reuses one native recogniser across pages', () async {
      mockChannel(
        (call) async => <dynamic, dynamic>{'text': 'x', 'blocks': <dynamic>[]},
      );

      await recognizer.recognize(await writePage('page_000.jpg'));
      await recognizer.recognize(await writePage('page_001.jpg'));
      await recognizer.recognize(await writePage('page_002.jpg'));

      final ids = calls
          .where((call) => call.method == 'vision#startTextRecognizer')
          .map((call) => (call.arguments as Map)['id'])
          .toSet();

      expect(
        ids,
        hasLength(1),
        reason: 'a detector per page would allocate a native model per page',
      );
    });

    test('a missing page image is reported before ML Kit is called', () async {
      mockChannel(
        (call) async => <dynamic, dynamic>{'text': 'x', 'blocks': <dynamic>[]},
      );

      await expectLater(
        recognizer.recognize('documents/doc-1/gone.jpg'),
        throwsA(isA<CacheException>()),
      );
      expect(calls, isEmpty);
    });

    test('a platform error becomes an MlKitException', () async {
      mockChannel(
        (call) async => throw PlatformException(code: 'TextRecognizer'),
      );

      await expectLater(
        recognizer.recognize(await writePage('page_000.jpg')),
        throwsA(isA<MlKitException>()),
      );
    });

    test('an unreadable reply becomes an MlKitException', () async {
      mockChannel((call) async => null);

      await expectLater(
        recognizer.recognize(await writePage('page_000.jpg')),
        throwsA(isA<MlKitException>()),
      );
    });

    test('close releases the instance and is safe when none was made', () async {
      mockChannel(
        (call) async => <dynamic, dynamic>{'text': 'x', 'blocks': <dynamic>[]},
      );

      await recognizer.close();
      expect(calls, isEmpty, reason: 'nothing was allocated yet');

      await recognizer.recognize(await writePage('page_000.jpg'));
      await recognizer.close();

      expect(
        calls.map((call) => call.method),
        contains('vision#closeTextRecognizer'),
      );
    });
  });

  group('OcrRepositoryImpl', () {
    test('wraps recognised text in a Success', () async {
      mockChannel(
        (call) async => <dynamic, dynamic>{
          'text': 'Invoice',
          'blocks': <dynamic>[],
        },
      );
      final repository = OcrRepositoryImpl(recognizer);

      final result = await repository.recognizeText(
        await writePage('page_000.jpg'),
      );

      expect(result.valueOrNull, 'Invoice');
    });

    test('reports a missing image as an OcrFailure, not a storage error', () async {
      final repository = OcrRepositoryImpl(recognizer);

      final result = await repository.recognizeText('documents/x/gone.jpg');

      expect(
        result.failureOrNull,
        isA<OcrFailure>(),
        reason: 'the page is marked failed and stays retryable; the library '
            'itself is not broken',
      );
    });

    test('reports a recognition error as an OcrFailure', () async {
      mockChannel(
        (call) async => throw PlatformException(code: 'TextRecognizer'),
      );
      final repository = OcrRepositoryImpl(recognizer);

      final result = await repository.recognizeText(
        await writePage('page_000.jpg'),
      );

      expect(result.failureOrNull, isA<OcrFailure>());
    });
  });
}
