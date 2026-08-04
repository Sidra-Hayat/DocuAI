import 'package:docuai/src/core/error/exceptions.dart';
import 'package:docuai/src/features/scanner/data/datasources/mlkit_document_scanner.dart';
import 'package:docuai/src/features/scanner/data/datasources/scanner_availability.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tests the translation layer over ML Kit's plugin by mocking its method
/// channel.
///
/// Everything asserted here comes from reading the plugin's Android source:
/// cancelling answers with an *error*, not an empty result, and the returned
/// paths are `Uri.path` values pointing into the app cache. Those behaviours
/// are what this wrapper exists to normalise, so they are what the tests pin.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('google_mlkit_document_scanner');
  const scanner = MlKitDocumentScanner();

  late List<MethodCall> calls;

  void mockChannel(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return handler(call);
        });
  }

  setUp(() => calls = <MethodCall>[]);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('returns the captured page paths', () async {
    mockChannel(
      (call) async => <dynamic, dynamic>{
        'images': <String>['/cache/scan/page0.jpg', '/cache/scan/page1.jpg'],
        'pdf': null,
      },
    );

    final pages = await scanner.scan(pageLimit: 20);

    expect(pages, <String>['/cache/scan/page0.jpg', '/cache/scan/page1.jpg']);
  });

  test('asks for JPEG pages in full mode, with the given limit', () async {
    mockChannel((call) async => <dynamic, dynamic>{'images': <String>[]});

    await scanner.scan(pageLimit: 7);

    final start = calls.firstWhere(
      (call) => call.method == 'vision#startDocumentScanner',
    );
    final options = (start.arguments as Map)['options'] as Map;

    expect(options['pageLimit'], 7);
    expect(options['formats'], <String>['jpeg']);
    expect(options['mode'], 'full');
    expect(
      options['isGalleryImport'],
      isTrue,
      reason: 'gallery import is the fallback when the camera path fails',
    );
  });

  test('treats cancellation as an empty capture, not a failure', () async {
    mockChannel(
      (call) async => call.method == 'vision#startDocumentScanner'
          ? throw PlatformException(
              code: 'DocumentScanner',
              message: 'Operation cancelled',
            )
          : null,
    );

    await expectLater(scanner.scan(pageLimit: 20), completion(isEmpty));
  });

  test('turns a genuine platform error into an MlKitException', () async {
    mockChannel(
      (call) async => call.method == 'vision#startDocumentScanner'
          ? throw PlatformException(
              code: 'DocumentScanner',
              message: 'Failed to start document scanner',
            )
          : null,
    );

    await expectLater(
      scanner.scan(pageLimit: 20),
      throwsA(
        isA<MlKitException>().having(
          (error) => error.message,
          'message',
          contains('Google Play Services'),
        ),
      ),
    );
  });

  test('survives a result with no images key', () async {
    mockChannel((call) async => <dynamic, dynamic>{'images': null, 'pdf': null});

    expect(await scanner.scan(pageLimit: 20), isEmpty);
  });

  test('turns an unreadable result into an MlKitException', () async {
    // The plugin dereferences the response map without a null check, so a
    // null reply throws inside its own parsing rather than returning anything.
    mockChannel((call) async => null);

    await expectLater(
      scanner.scan(pageLimit: 20),
      throwsA(isA<MlKitException>()),
    );
  });

  test('closes the scanner instance even when the scan fails', () async {
    mockChannel(
      (call) async => call.method == 'vision#startDocumentScanner'
          ? throw PlatformException(code: 'DocumentScanner', message: 'boom')
          : null,
    );

    await scanner.scan(pageLimit: 20).catchError((_) => <String>[]);

    expect(
      calls.map((call) => call.method),
      contains('vision#closeDocumentScanner'),
      reason: 'the plugin holds instances in a map until they are closed',
    );
  });

  test('closes the scanner instance after a successful scan', () async {
    mockChannel(
      (call) async => <dynamic, dynamic>{
        'images': <String>['/cache/scan/page0.jpg'],
      },
    );

    await scanner.scan(pageLimit: 20);

    expect(
      calls.map((call) => call.method),
      containsAllInOrder(<String>[
        'vision#startDocumentScanner',
        'vision#closeDocumentScanner',
      ]),
    );
  });

  group('ScannerAvailability', () {
    test('reports unavailable off Android without calling the channel', () async {
      // The host running these tests is not Android, which is exactly the
      // "no Play Services" answer the check is meant to give. The Android path
      // calls into MainActivity and can only be exercised on a device.
      expect(await const ScannerAvailability().isAvailable(), isFalse);
    });
  });
}
