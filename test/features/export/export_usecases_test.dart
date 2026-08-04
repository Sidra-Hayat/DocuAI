import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/export/domain/usecases/export_document_as_pdf.dart';
import 'package:docuai/src/features/export/domain/usecases/share_document.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeExportRepository export;
  late FakeDocumentRepository documents;
  late ExportDocumentAsPdf exportAsPdf;

  setUp(() {
    export = FakeExportRepository();
    documents = FakeDocumentRepository();
    exportAsPdf = ExportDocumentAsPdf(
      export: export,
      documents: documents,
      clock: fixedClock,
    );
  });

  tearDown(() => documents.dispose());

  group('ExportDocumentAsPdf', () {
    test('records the generated path on the document', () async {
      documents.seed(buildDocument());

      final result = await exportAsPdf('doc-1');

      expect(result.valueOrNull?.pdfPath, 'documents/doc-1/doc-1.pdf');
      expect(documents.savedDocuments.single.updatedAt, kNow);
    });

    test('refuses to export a document with no pages', () async {
      documents.seed(buildDocument(pages: const <DocumentPage>[]));

      final result = await exportAsPdf('doc-1');

      expect(result.failureOrNull, isA<ExportFailure>());
      expect(export.buildCount, 0);
    });

    test('does not save when the build fails', () async {
      documents.seed(buildDocument());
      export.buildResult = const Failed(ExportFailure('Out of memory.'));

      final result = await exportAsPdf('doc-1');

      expect(result.failureOrNull, isA<ExportFailure>());
      expect(documents.savedDocuments, isEmpty);
    });
  });

  group('ShareDocument', () {
    late ShareDocument share;

    setUp(() {
      share = ShareDocument(export: export, exportAsPdf: exportAsPdf);
    });

    test('reuses an existing PDF instead of rebuilding it', () async {
      final document = buildDocument(pdfPath: 'documents/doc-1/doc-1.pdf');
      documents.seed(document);

      final result = await share(document);

      expect(result.isSuccess, isTrue);
      expect(export.buildCount, 0);
      expect(export.sharedPaths, <String>['documents/doc-1/doc-1.pdf']);
      expect(export.lastSubject, 'Lecture notes');
    });

    test('builds a PDF first when the document has never been exported', () async {
      final document = buildDocument();
      documents.seed(document);

      final result = await share(document);

      expect(result.isSuccess, isTrue);
      expect(export.buildCount, 1);
      expect(export.sharedPaths, <String>['documents/doc-1/doc-1.pdf']);
    });

    test('does not open the share sheet when the export fails', () async {
      final document = buildDocument();
      documents.seed(document);
      export.buildResult = const Failed(ExportFailure('Rendering failed.'));

      final result = await share(document);

      expect(result.failureOrNull, isA<ExportFailure>());
      expect(export.sharedPaths, isEmpty);
    });
  });
}
