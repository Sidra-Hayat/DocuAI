import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/features/documents/presentation/providers/document_providers.dart';
import 'package:docuai/src/features/export/presentation/providers/export_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeExportRepository export;
  late FakeDocumentRepository documents;
  late ProviderContainer container;

  setUp(() {
    export = FakeExportRepository();
    documents = FakeDocumentRepository();
    container = ProviderContainer(
      overrides: [
        exportRepositoryProvider.overrideWithValue(export),
        documentRepositoryProvider.overrideWithValue(documents),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    documents.dispose();
  });

  ExportController controller() =>
      container.read(exportControllerProvider.notifier);

  ExportState state() => container.read(exportControllerProvider);

  test('starts idle', () {
    expect(state(), isA<ExportIdle>());
  });

  test('builds a PDF then shares it, returning to idle', () async {
    final document = buildDocument();
    documents.seed(document);

    await controller().shareAsPdf(document);

    expect(export.buildCount, 1);
    expect(export.sharedPaths, <String>['documents/doc-1/doc-1.pdf']);
    expect(state(), isA<ExportIdle>());
  });

  test('reuses an existing PDF instead of composing another', () async {
    final document = buildDocument(pdfPath: 'documents/doc-1/doc-1.pdf');
    documents.seed(document);

    await controller().shareAsPdf(document);

    expect(export.buildCount, 0);
    expect(export.sharedPaths, hasLength(1));
  });

  test('rebuild discards the recorded PDF and composes a fresh one', () async {
    final document = buildDocument(pdfPath: 'documents/doc-1/stale.pdf');
    documents.seed(document);

    await controller().shareAsPdf(document, rebuild: true);

    expect(export.buildCount, 1);
    expect(
      export.sharedPaths.single,
      'documents/doc-1/doc-1.pdf',
      reason: 'the freshly built path must be the one shared',
    );
  });

  test('a failed rebuild reports and does not open the share sheet', () async {
    documents.seed(buildDocument());
    export.buildResult = const Failed(ExportFailure('Out of space.'));

    await controller().shareAsPdf(buildDocument(), rebuild: true);

    final current = state();
    expect(current, isA<ExportFailedState>());
    expect((current as ExportFailedState).message, 'Out of space.');
    expect(export.sharedPaths, isEmpty);
  });

  test('a failed share is reported against the right document', () async {
    final document = buildDocument(
      id: 'doc-7',
      pdfPath: 'documents/doc-7/x.pdf',
    );
    documents.seed(document);
    export.shareFailure = const ExportFailure('No app can receive the PDF.');

    await controller().shareAsPdf(document);

    final current = state();
    expect(current, isA<ExportFailedState>());
    expect(current.documentId, 'doc-7');
  });

  test('a second share while one is running is ignored', () async {
    final document = buildDocument(pdfPath: 'documents/doc-1/x.pdf');
    documents.seed(document);

    final first = controller().shareAsPdf(document);
    final second = controller().shareAsPdf(document);
    await Future.wait(<Future<void>>[first, second]);

    expect(
      export.sharedPaths,
      hasLength(1),
      reason: 'a double tap must not open two share sheets',
    );
  });

  test('reset clears a failure so the button leaves its retry state', () async {
    documents.seed(buildDocument());
    export.shareFailure = const ExportFailure('Nope.');
    await controller().shareAsPdf(buildDocument());
    expect(state(), isA<ExportFailedState>());

    controller().reset();

    expect(state(), isA<ExportIdle>());
  });
}
