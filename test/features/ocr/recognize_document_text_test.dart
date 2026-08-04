import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/ocr/domain/usecases/recognize_document_text.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeOcrRepository ocr;
  late FakeDocumentRepository documents;
  late FakeSearchRepository search;
  late RecognizeDocumentText recognize;

  setUp(() {
    ocr = FakeOcrRepository();
    documents = FakeDocumentRepository();
    search = FakeSearchRepository();
    recognize = RecognizeDocumentText(
      ocr: ocr,
      documents: documents,
      search: search,
      clock: fixedClock,
    );
  });

  tearDown(() => documents.dispose());

  test('recognises every pending page and saves the text', () async {
    documents.seed(
      buildDocument(
        pages: <DocumentPage>[
          buildPage(id: 'a', index: 0, imagePath: 'p/0.jpg'),
          buildPage(id: 'b', index: 1, imagePath: 'p/1.jpg'),
        ],
      ),
    );
    ocr.results['p/0.jpg'] = const Success('first page');
    ocr.results['p/1.jpg'] = const Success('second page');

    final result = await recognize('doc-1');

    final saved = result.valueOrNull!;
    expect(saved.pages.map((page) => page.text), <String>[
      'first page',
      'second page',
    ]);
    expect(saved.ocrStatus, OcrStatus.completed);
    expect(saved.updatedAt, kNow);
  });

  test('skips pages that already completed', () async {
    documents.seed(
      buildDocument(
        pages: <DocumentPage>[
          buildPage(
            id: 'a',
            index: 0,
            imagePath: 'p/0.jpg',
            text: 'already read',
            ocrStatus: OcrStatus.completed,
          ),
          buildPage(id: 'b', index: 1, imagePath: 'p/1.jpg'),
        ],
      ),
    );

    final result = await recognize('doc-1');

    expect(ocr.requestedPaths, <String>['p/1.jpg']);
    expect(result.valueOrNull?.pages.first.text, 'already read');
  });

  test('force re-runs pages that already completed', () async {
    documents.seed(
      buildDocument(
        pages: <DocumentPage>[
          buildPage(
            id: 'a',
            index: 0,
            imagePath: 'p/0.jpg',
            text: 'stale',
            ocrStatus: OcrStatus.completed,
          ),
        ],
      ),
    );
    ocr.defaultResult = const Success('fresh');

    final result = await recognize('doc-1', force: true);

    expect(ocr.requestedPaths, <String>['p/0.jpg']);
    expect(result.valueOrNull?.pages.single.text, 'fresh');
  });

  test('one failed page does not abort the others', () async {
    documents.seed(
      buildDocument(
        pages: <DocumentPage>[
          buildPage(id: 'a', index: 0, imagePath: 'p/0.jpg'),
          buildPage(id: 'b', index: 1, imagePath: 'p/1.jpg'),
          buildPage(id: 'c', index: 2, imagePath: 'p/2.jpg'),
        ],
      ),
    );
    ocr.results['p/1.jpg'] = const Failed(OcrFailure('Image unreadable.'));

    final saved = (await recognize('doc-1')).valueOrNull!;

    expect(saved.pages[0].ocrStatus, OcrStatus.completed);
    expect(saved.pages[1].ocrStatus, OcrStatus.failed);
    expect(saved.pages[2].ocrStatus, OcrStatus.completed);
    expect(saved.ocrStatus, OcrStatus.failed);
    expect(
      saved.pagesAwaitingOcr.map((page) => page.id),
      <String>['b'],
      reason: 'the failed page must stay retryable',
    );
  });

  test('a failed retry keeps text from an earlier successful run', () async {
    documents.seed(
      buildDocument(
        pages: <DocumentPage>[
          buildPage(
            id: 'a',
            index: 0,
            imagePath: 'p/0.jpg',
            text: 'previously recognised',
            ocrStatus: OcrStatus.failed,
          ),
        ],
      ),
    );
    ocr.defaultResult = const Failed(OcrFailure('Still unreadable.'));

    final saved = (await recognize('doc-1')).valueOrNull!;

    expect(saved.pages.single.text, 'previously recognised');
    expect(saved.pages.single.ocrStatus, OcrStatus.failed);
  });

  test('reports progress once per page it touches', () async {
    documents.seed(
      buildDocument(
        pages: <DocumentPage>[
          buildPage(id: 'a', index: 0, imagePath: 'p/0.jpg'),
          buildPage(
            id: 'b',
            index: 1,
            imagePath: 'p/1.jpg',
            ocrStatus: OcrStatus.completed,
          ),
          buildPage(id: 'c', index: 2, imagePath: 'p/2.jpg'),
        ],
      ),
    );

    final progress = <String>[];
    await recognize(
      'doc-1',
      onProgress: (done, total) => progress.add('$done/$total'),
    );

    expect(progress, <String>['1/2', '2/2']);
  });

  test('indexes the document for search once text exists', () async {
    documents.seed(buildDocument());

    await recognize('doc-1');

    expect(search.indexedIds, <String>['doc-1']);
  });

  test('does not index a document that yielded no text', () async {
    documents.seed(buildDocument());
    ocr.defaultResult = const Success('   ');

    await recognize('doc-1');

    expect(search.indexedIds, isEmpty);
  });

  test('still succeeds when indexing fails', () async {
    documents.seed(buildDocument());
    search.indexFailure = const StorageFailure('Index box is locked.');

    final result = await recognize('doc-1');

    expect(result.isSuccess, isTrue);
    expect(result.valueOrNull?.hasText, isTrue);
  });

  test('returns the document untouched when nothing is pending', () async {
    documents.seed(
      buildDocument(
        pages: <DocumentPage>[
          buildPage(id: 'a', index: 0, ocrStatus: OcrStatus.completed),
        ],
      ),
    );

    final result = await recognize('doc-1');

    expect(ocr.requestedPaths, isEmpty);
    expect(documents.savedDocuments, isEmpty);
    expect(result.valueOrNull?.updatedAt, kEarlier);
  });

  test('propagates a load failure', () async {
    final result = await recognize('missing');

    expect(result.failureOrNull, isA<StorageFailure>());
    expect(ocr.requestedPaths, isEmpty);
  });
}
