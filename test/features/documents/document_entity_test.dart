import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  group('Document.ocrStatus', () {
    test('is pending for a document with no pages', () {
      expect(
        buildDocument(pages: const <DocumentPage>[]).ocrStatus,
        OcrStatus.pending,
      );
    });

    test('is completed only when every page succeeded', () {
      final document = buildDocument(
        pages: <DocumentPage>[
          buildPage(id: 'a', index: 0, ocrStatus: OcrStatus.completed),
          buildPage(id: 'b', index: 1, ocrStatus: OcrStatus.completed),
        ],
      );

      expect(document.ocrStatus, OcrStatus.completed);
    });

    test('reports running ahead of pending and failed', () {
      final document = buildDocument(
        pages: <DocumentPage>[
          buildPage(id: 'a', index: 0, ocrStatus: OcrStatus.failed),
          buildPage(id: 'b', index: 1, ocrStatus: OcrStatus.pending),
          buildPage(id: 'c', index: 2, ocrStatus: OcrStatus.running),
        ],
      );

      expect(document.ocrStatus, OcrStatus.running);
    });

    test('reports pending ahead of failed, so a retry is not hidden', () {
      final document = buildDocument(
        pages: <DocumentPage>[
          buildPage(id: 'a', index: 0, ocrStatus: OcrStatus.failed),
          buildPage(id: 'b', index: 1, ocrStatus: OcrStatus.pending),
        ],
      );

      expect(document.ocrStatus, OcrStatus.pending);
    });

    test('is failed when the run finished but a page did not', () {
      final document = buildDocument(
        pages: <DocumentPage>[
          buildPage(id: 'a', index: 0, ocrStatus: OcrStatus.completed),
          buildPage(id: 'b', index: 1, ocrStatus: OcrStatus.failed),
        ],
      );

      expect(document.ocrStatus, OcrStatus.failed);
    });
  });

  group('Document.extractedText', () {
    test('joins pages in order and skips the empty ones', () {
      final document = buildDocument(
        pages: <DocumentPage>[
          buildPage(id: 'a', index: 0, text: 'first'),
          buildPage(id: 'b', index: 1, text: '   '),
          buildPage(id: 'c', index: 2, text: 'third'),
        ],
      );

      expect(document.extractedText, 'first\n\nthird');
      expect(document.hasText, isTrue);
    });

    test('is empty when no page has been recognised', () {
      expect(buildDocument().extractedText, isEmpty);
      expect(buildDocument().hasText, isFalse);
    });
  });

  group('Document.pagesAwaitingOcr', () {
    test('includes pending and failed pages but not running or completed', () {
      final document = buildDocument(
        pages: <DocumentPage>[
          buildPage(id: 'a', index: 0, ocrStatus: OcrStatus.completed),
          buildPage(id: 'b', index: 1, ocrStatus: OcrStatus.pending),
          buildPage(id: 'c', index: 2, ocrStatus: OcrStatus.failed),
          buildPage(id: 'd', index: 3, ocrStatus: OcrStatus.running),
        ],
      );

      expect(
        document.pagesAwaitingOcr.map((page) => page.id),
        <String>['b', 'c'],
      );
    });
  });

  group('Document convenience getters', () {
    test('coverPage is the first page, or null when there are none', () {
      expect(buildDocument().coverPage?.id, 'page-1');
      expect(
        buildDocument(pages: const <DocumentPage>[]).coverPage,
        isNull,
      );
    });

    test('hasPdf follows pdfPath', () {
      expect(buildDocument().hasPdf, isFalse);
      expect(buildDocument(pdfPath: 'documents/doc-1/x.pdf').hasPdf, isTrue);
    });
  });

  group('DocumentPage', () {
    test('hasText ignores whitespace-only recognition results', () {
      expect(buildPage(text: '  \n ').hasText, isFalse);
      expect(buildPage(text: 'Invoice').hasText, isTrue);
    });

    test('displayLabel is one-based for the user', () {
      expect(buildPage(index: 0).displayLabel, 'Page 1');
      expect(buildPage(index: 4).displayLabel, 'Page 5');
    });
  });
}
