import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/features/documents/presentation/providers/document_providers.dart';
import 'package:docuai/src/features/scanner/presentation/providers/scan_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeScannerRepository scanner;
  late FakeDocumentRepository documents;
  late ProviderContainer container;

  setUp(() {
    scanner = FakeScannerRepository();
    documents = FakeDocumentRepository();
    container = ProviderContainer(
      overrides: [
        scannerRepositoryProvider.overrideWithValue(scanner),
        documentRepositoryProvider.overrideWithValue(documents),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    documents.dispose();
  });

  ScanController controller() =>
      container.read(scanControllerProvider.notifier);

  ScanState state() => container.read(scanControllerProvider);

  test('starts idle', () {
    expect(state(), isA<ScanIdle>());
  });

  test('saves the captured pages and reports the new document', () async {
    scanner.result = const Success(<String>['/tmp/a.jpg', '/tmp/b.jpg']);

    await controller().start();

    final current = state();
    expect(current, isA<ScanSaved>());
    expect((current as ScanSaved).document.pageCount, 2);
    expect(documents.lastSourceImagePaths, hasLength(2));
  });

  test('titles the document by when it was scanned', () async {
    await controller().start(clock: fixedClock);

    expect(documents.lastCreatedTitle, ScanController.defaultTitleFor(kNow));
    expect(documents.lastCreatedTitle, contains('Scan '));
  });

  test('a cancelled scan is its own state, carrying no error', () async {
    scanner.result = const Success(<String>[]);

    await controller().start();

    expect(
      state(),
      isA<ScanCancelled>(),
      reason: 'backing out must not surface as a failure message',
    );
  });

  test('a real scanner failure carries its message', () async {
    scanner.result = const Failed(
      ScanFailure('The scanner could not start. It needs Google Play Services.'),
    );

    await controller().start();

    final current = state();
    expect(current, isA<ScanFailedState>());
    expect(
      (current as ScanFailedState).message,
      contains('Google Play Services'),
    );
  });

  test('a storage failure while saving is reported, not swallowed', () async {
    documents.saveFailure = const StorageFailure('Disk is full.');

    await controller().start();

    expect(state(), isA<ScanFailedState>());
    expect((state() as ScanFailedState).message, 'Disk is full.');
  });

  test('reset returns to idle so the screen does not replay the outcome', () async {
    await controller().start();
    expect(state(), isA<ScanSaved>());

    controller().reset();

    expect(state(), isA<ScanIdle>());
  });

  test('a second start while one is running is ignored', () async {
    scanner.result = const Success(<String>['/tmp/a.jpg']);

    final first = controller().start();
    final second = controller().start();
    await Future.wait(<Future<void>>[first, second]);

    expect(
      documents.store.values,
      hasLength(1),
      reason: 'a double tap must not open the scanner twice',
    );
  });

  test('defaultTitleFor is stable and human-readable', () {
    expect(
      ScanController.defaultTitleFor(DateTime(2026, 8, 4, 14, 32)),
      'Scan 4 Aug 2026, 14:32',
    );
  });
}
