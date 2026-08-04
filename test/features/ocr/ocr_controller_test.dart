import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/documents/presentation/providers/document_providers.dart';
import 'package:docuai/src/features/ocr/presentation/providers/ocr_controller.dart';
import 'package:docuai/src/features/search/presentation/providers/search_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeOcrRepository ocr;
  late FakeDocumentRepository documents;
  late FakeSearchRepository search;
  late ProviderContainer container;
  late List<OcrState> states;

  setUp(() {
    ocr = FakeOcrRepository();
    documents = FakeDocumentRepository();
    search = FakeSearchRepository();
    container = ProviderContainer(
      overrides: [
        ocrRepositoryProvider.overrideWithValue(ocr),
        documentRepositoryProvider.overrideWithValue(documents),
        searchRepositoryProvider.overrideWithValue(search),
      ],
    );
    states = <OcrState>[];
    container.listen(ocrControllerProvider, (previous, next) => states.add(next));
  });

  tearDown(() {
    container.dispose();
    documents.dispose();
  });

  OcrController controller() => container.read(ocrControllerProvider.notifier);

  test('starts idle', () {
    expect(container.read(ocrControllerProvider), isA<OcrIdle>());
  });

  test('recognises the pages and reports completion', () async {
    documents.seed(
      buildDocument(
        pages: <DocumentPage>[
          buildPage(id: 'a', index: 0, imagePath: 'p/0.jpg'),
          buildPage(id: 'b', index: 1, imagePath: 'p/1.jpg'),
        ],
      ),
    );

    await controller().run('doc-1');

    expect(container.read(ocrControllerProvider), isA<OcrCompleted>());
    expect(documents.savedDocuments.single.hasText, isTrue);
  });

  test('reports progress page by page', () async {
    documents.seed(
      buildDocument(
        pages: <DocumentPage>[
          buildPage(id: 'a', index: 0, imagePath: 'p/0.jpg'),
          buildPage(id: 'b', index: 1, imagePath: 'p/1.jpg'),
          buildPage(id: 'c', index: 2, imagePath: 'p/2.jpg'),
        ],
      ),
    );

    await controller().run('doc-1');

    final progress = states
        .whereType<OcrRunning>()
        .map((state) => '${state.done}/${state.total}')
        .toList();

    expect(progress, <String>['0/0', '1/3', '2/3', '3/3']);
    expect(states.whereType<OcrRunning>().last.fraction, 1.0);
  });

  test('carries the document id so a screen can ignore other runs', () async {
    documents.seed(buildDocument(id: 'doc-9'));

    await controller().run('doc-9');

    expect(
      states.every((state) => state is OcrIdle || state.documentId == 'doc-9'),
      isTrue,
    );
  });

  test('a page that cannot be read still completes the run', () async {
    documents.seed(
      buildDocument(
        pages: <DocumentPage>[
          buildPage(id: 'a', index: 0, imagePath: 'p/0.jpg'),
          buildPage(id: 'b', index: 1, imagePath: 'p/1.jpg'),
        ],
      ),
    );
    ocr.results['p/1.jpg'] = const Failed(OcrFailure('Image unreadable.'));

    await controller().run('doc-1');

    expect(
      container.read(ocrControllerProvider),
      isA<OcrCompleted>(),
      reason: 'one bad page must not present as a failed document',
    );
    final saved = documents.savedDocuments.single;
    expect(saved.pages.first.ocrStatus, OcrStatus.completed);
    expect(saved.pages.last.ocrStatus, OcrStatus.failed);
  });

  test('a document that cannot be loaded is a failure', () async {
    await controller().run('missing');

    final state = container.read(ocrControllerProvider);
    expect(state, isA<OcrFailedState>());
    expect((state as OcrFailedState).documentId, 'missing');
  });

  test('a second run for the same document while running is ignored', () async {
    documents.seed(buildDocument());

    final first = controller().run('doc-1');
    final second = controller().run('doc-1');
    await Future.wait(<Future<void>>[first, second]);

    expect(ocr.requestedPaths, hasLength(1));
  });

  test('force re-reads pages that already completed', () async {
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

    await controller().run('doc-1', force: true);

    expect(documents.savedDocuments.single.pages.single.text, 'fresh');
  });

  test('reset returns to idle', () async {
    documents.seed(buildDocument());
    await controller().run('doc-1');

    controller().reset();

    expect(container.read(ocrControllerProvider), isA<OcrIdle>());
  });
}
