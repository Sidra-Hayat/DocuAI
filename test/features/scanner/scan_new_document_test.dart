import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/features/scanner/domain/usecases/scan_new_document.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeScannerRepository scanner;
  late FakeDocumentRepository documents;
  late ScanNewDocument scan;

  setUp(() {
    scanner = FakeScannerRepository();
    documents = FakeDocumentRepository();
    scan = ScanNewDocument(scanner: scanner, documents: documents);
  });

  tearDown(() => documents.dispose());

  test('persists the captured pages under the given title', () async {
    scanner.result = const Success(<String>['/tmp/a.jpg', '/tmp/b.jpg']);

    final result = await scan(title: '  Passport  ');

    expect(result.valueOrNull?.pageCount, 2);
    expect(documents.lastCreatedTitle, 'Passport');
    expect(documents.lastSourceImagePaths, <String>['/tmp/a.jpg', '/tmp/b.jpg']);
  });

  test('falls back to the default title when none is usable', () async {
    await scan(title: '   ');
    expect(documents.lastCreatedTitle, ScanNewDocument.defaultTitle);

    await scan();
    expect(documents.lastCreatedTitle, ScanNewDocument.defaultTitle);
  });

  test('forwards the page limit to the scanner', () async {
    await scan(pageLimit: 5);
    expect(scanner.lastPageLimit, 5);
  });

  test('reports a cancelled scan without creating a document', () async {
    scanner.result = const Success(<String>[]);

    final result = await scan();

    expect(result.failureOrNull, isA<ScanFailure>());
    expect(documents.store, isEmpty);
  });

  test('propagates a scanner failure unchanged', () async {
    const failure = ScanFailure('Play Services module unavailable.');
    scanner.result = const Failed(failure);

    final result = await scan();

    expect(result.failureOrNull, same(failure));
    expect(documents.lastSourceImagePaths, isNull);
  });
}
