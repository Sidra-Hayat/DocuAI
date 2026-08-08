import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

/// A page that may have no image, and a document that may have no images.
///
/// The model change these cover is small; the consequences are not. Every
/// aggregate on `Document` was written when a page was always a scan, and each
/// one is a place where a text page could either be misread as work outstanding
/// or quietly excluded from the text the rest of the app reads.
void main() {
  group('DocumentPage', () {
    test('a scanned page has an image, a text page does not', () {
      expect(buildPage().hasImage, isTrue);
      expect(buildTextPage().hasImage, isFalse);
    });

    test('hasImage follows the path, not the kind', () {
      // The kind is provenance. The path is the fact every caller needs before
      // it reads, renders or deletes a file, and a record whose kind and path
      // disagreed should degrade rather than throw.
      expect(buildPage(kind: PageKind.scanned, imagePath: null).hasImage, isFalse);
      expect(buildPage(kind: PageKind.imported).hasImage, isTrue);
    });

    test('imported and scanned pages are alike in everything but provenance', () {
      final scanned = buildPage(id: 'a', kind: PageKind.scanned);
      final imported = buildPage(id: 'a', kind: PageKind.imported);

      expect(imported.hasImage, scanned.hasImage);
      expect(imported.isText, scanned.isText);
      expect(imported, isNot(scanned), reason: 'only the kind differs');
    });

    test('a text page carries text like any other page', () {
      expect(buildTextPage(text: 'Written by hand').hasText, isTrue);
      expect(buildTextPage(text: '   ').hasText, isFalse);
    });
  });

  group('Document.ocrStatus with pages that have no image', () {
    test('a text-only document is not waiting to be recognised', () {
      // The consequence if this reported pending: the detail screen starts a
      // recognition run whenever it sees pending, and that run has no page to
      // work on — so it could never clear the status that triggered it. Every
      // open would start another.
      final document = buildDocument(
        source: DocumentSource.created,
        pages: <DocumentPage>[buildTextPage()],
      );

      expect(document.ocrStatus, OcrStatus.completed);
      expect(document.pagesAwaitingOcr, isEmpty);
    });

    test('a text page does not mask a scan that still needs reading', () {
      final document = buildDocument(
        pages: <DocumentPage>[
          buildTextPage(id: 't', index: 0),
          buildPage(id: 's', index: 1, ocrStatus: OcrStatus.pending),
        ],
      );

      expect(document.ocrStatus, OcrStatus.pending);
      expect(document.pagesAwaitingOcr.map((page) => page.id), <String>['s']);
    });

    test('a text page does not hold a finished document back', () {
      final document = buildDocument(
        pages: <DocumentPage>[
          buildPage(id: 's', index: 0, ocrStatus: OcrStatus.completed),
          buildTextPage(id: 't', index: 1),
        ],
      );

      expect(document.ocrStatus, OcrStatus.completed);
    });

    test('an empty document is still pending, as it always was', () {
      expect(
        buildDocument(pages: const <DocumentPage>[]).ocrStatus,
        OcrStatus.pending,
      );
    });

    test('a page with no image is never offered to recognition', () {
      // Belt and braces: a text page is created completed, so it should not
      // reach this list anyway. This holds if some other path ever writes one
      // as pending — recognition reads a file, and there is no file.
      final document = buildDocument(
        pages: <DocumentPage>[
          buildPage(
            id: 'broken',
            index: 0,
            imagePath: null,
            ocrStatus: OcrStatus.pending,
          ),
        ],
      );

      expect(document.pagesAwaitingOcr, isEmpty);
      expect(document.ocrStatus, OcrStatus.completed);
    });
  });

  group('Document text', () {
    test('typed pages contribute to the text the rest of the app reads', () {
      // The single reason this model was chosen over a body field on the
      // document: search, passage extraction and the assistant all read
      // extractedText, and none of them had to learn a second source.
      final document = buildDocument(
        pages: <DocumentPage>[
          buildPage(id: 's', index: 0, text: 'Scanned line.'),
          buildTextPage(id: 't', index: 1, text: 'Typed line.'),
        ],
      );

      expect(document.extractedText, 'Scanned line.\n\nTyped line.');
      expect(document.hasText, isTrue);
    });

    test('a text-only document has text', () {
      expect(
        buildDocument(pages: <DocumentPage>[buildTextPage()]).hasText,
        isTrue,
      );
    });
  });

  group('Document image pages', () {
    test('separates what can be drawn from what cannot', () {
      final document = buildDocument(
        pages: <DocumentPage>[
          buildPage(id: 's', index: 0),
          buildTextPage(id: 't', index: 1),
          buildPage(id: 'i', index: 2, kind: PageKind.imported),
        ],
      );

      expect(document.imagePages.map((page) => page.id), <String>['s', 'i']);
      expect(document.hasImagePages, isTrue);
    });

    test('a text-only document has none', () {
      final document = buildDocument(pages: <DocumentPage>[buildTextPage()]);

      expect(document.imagePages, isEmpty);
      expect(document.hasImagePages, isFalse);
    });

    test('the cover is the first page, image or not', () {
      // Deliberate: the cover should be what the document opens with. Callers
      // handle a cover with no image rather than the document hiding one.
      final document = buildDocument(
        pages: <DocumentPage>[
          buildTextPage(id: 't', index: 0),
          buildPage(id: 's', index: 1),
        ],
      );

      expect(document.coverPage?.id, 't');
      expect(document.coverPage?.hasImage, isFalse);
    });
  });

  group('Document.source', () {
    test('defaults to scanned, which is what every existing document is', () {
      expect(buildDocument().source, DocumentSource.scanned);
    });

    test('records origin, which the pages cannot reconstruct', () {
      // An imported document that later gains a camera page is still imported.
      final document = buildDocument(
        source: DocumentSource.imported,
        pages: <DocumentPage>[
          buildPage(id: 'i', index: 0, kind: PageKind.imported),
          buildPage(id: 's', index: 1, kind: PageKind.scanned),
        ],
      );

      expect(document.source, DocumentSource.imported);
    });
  });
}
