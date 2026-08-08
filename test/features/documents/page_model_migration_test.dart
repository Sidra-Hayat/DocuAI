import 'dart:io';

import 'package:docuai/hive_registrar.g.dart';
import 'package:docuai/src/core/constants/hive_boxes.dart';
import 'package:docuai/src/features/documents/data/models/document_model.dart';
import 'package:docuai/src/features/documents/data/models/document_page_model.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:path/path.dart' as p;

/// Records written before pages had kinds must still open.
///
/// **What these prove and what they do not.** The generated adapter builds a
/// `fields` map from whatever the stored frame contains and then reads
/// `fields[5] as String?`. A field that was never written is absent from that
/// map and a field written as null is present holding null — both arrive at the
/// constructor as null, through the same lookup. These tests drive that
/// constructor path through a real Hive box, so the decoding under test is the
/// decoding that runs in production.
///
/// What they do not re-prove is that Hive itself tolerates a frame carrying
/// fewer fields than the current adapter declares. That is Hive's own format
/// contract — `numOfFields` is read from the frame, not assumed — and it is
/// visible in the generated `read`. Reaching into `BinaryReaderImpl` to
/// hand-assemble old bytes would test the package rather than this app, and
/// would break on an unrelated `hive_ce` patch bump.
void main() {
  late Directory tempDir;
  late Box<DocumentModel> box;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_migration');
    Hive.init(p.join(tempDir.path, 'hive'));
    Hive.registerAdapters();
  });

  setUp(() async {
    box = await Hive.openBox<DocumentModel>(
      'documents_${DateTime.now().microsecondsSinceEpoch}',
    );
  });

  tearDown(() async {
    if (box.isOpen) await box.deleteFromDisk();
  });

  tearDownAll(() async {
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } on FileSystemException {
      // Windows may still hold the box file; the OS reclaims it.
    }
  });

  /// A page exactly as the previous version wrote one: no kind.
  DocumentPageModel legacyPage({
    String id = 'page-0',
    String imagePath = 'documents/doc-1/page_000.jpg',
    int index = 0,
    String text = 'Recognised earlier.',
  }) => DocumentPageModel(
    id: id,
    imagePath: imagePath,
    index: index,
    text: text,
    ocrStatus: OcrStatus.completed.name,
    kind: null,
  );

  /// A document exactly as the previous version wrote one: no source.
  DocumentModel legacyDocument({
    String id = 'doc-1',
    List<DocumentPageModel>? pages,
  }) => DocumentModel(
    id: id,
    title: 'Electricity bill',
    createdAt: DateTime.utc(2026, 5, 1),
    updatedAt: DateTime.utc(2026, 5, 2),
    pages: pages ?? <DocumentPageModel>[legacyPage()],
    tags: const <String>['utilities'],
    pdfPath: 'documents/doc-1/bill.pdf',
    isFavorite: true,
    source: null,
  );

  Future<Document> roundTrip(DocumentModel model) async {
    await box.put(model.id, model);
    return box.get(model.id)!.toEntity();
  }

  group('type identity', () {
    test('the shipped type ids have not moved', () {
      // Hive writes the type id into every stored payload. Renumbering one
      // reinterprets every record already on a user's device, and there is no
      // recovering from it afterwards.
      expect(HiveTypeIds.document, 0);
      expect(HiveTypeIds.documentPage, 1);
      expect(HiveTypeIds.chatMessage, 3);
      expect(HiveTypeIds.answerCitation, 4);
    });

    test('the adapters still claim those ids', () {
      expect(DocumentModelAdapter().typeId, HiveTypeIds.document);
      expect(DocumentPageModelAdapter().typeId, HiveTypeIds.documentPage);
    });
  });

  group('a document stored before this change', () {
    test('opens with everything it had', () async {
      final document = await roundTrip(legacyDocument());

      expect(document.id, 'doc-1');
      expect(document.title, 'Electricity bill');
      expect(document.tags, <String>['utilities']);
      expect(document.pdfPath, 'documents/doc-1/bill.pdf');
      expect(document.isFavorite, isTrue);
      expect(document.createdAt, DateTime.utc(2026, 5, 1));
      expect(document.updatedAt, DateTime.utc(2026, 5, 2));
    });

    test('reads as scanned, because that is what it was', () async {
      final document = await roundTrip(legacyDocument());

      expect(document.source, DocumentSource.scanned);
      expect(document.pages.single.kind, PageKind.scanned);
    });

    test('keeps its image and its recognised text', () async {
      final document = await roundTrip(legacyDocument());
      final page = document.pages.single;

      expect(page.imagePath, 'documents/doc-1/page_000.jpg');
      expect(page.hasImage, isTrue);
      expect(page.text, 'Recognised earlier.');
      expect(page.ocrStatus, OcrStatus.completed);
    });

    test('still reports itself as read, so nothing re-runs OCR on it', () async {
      final document = await roundTrip(legacyDocument());

      expect(document.ocrStatus, OcrStatus.completed);
      expect(document.pagesAwaitingOcr, isEmpty);
      expect(document.hasText, isTrue);
    });

    test('a multi-page one keeps its order', () async {
      final document = await roundTrip(
        legacyDocument(
          pages: <DocumentPageModel>[
            legacyPage(id: 'b', index: 1, text: 'Second.'),
            legacyPage(id: 'a', index: 0, text: 'First.'),
          ],
        ),
      );

      expect(document.pages.map((page) => page.id), <String>['a', 'b']);
    });
  });

  group('a page written by a later version', () {
    test('an unrecognised kind falls back instead of throwing', () async {
      // Forward compatibility: after a downgrade, the library has to open. A
      // page it cannot classify is better shown as a scan than not at all.
      final document = await roundTrip(
        legacyDocument(
          pages: <DocumentPageModel>[
            DocumentPageModel(
              id: 'future',
              imagePath: 'documents/doc-1/page_000.jpg',
              index: 0,
              text: 'From a newer build.',
              ocrStatus: OcrStatus.completed.name,
              kind: 'handwriting',
            ),
          ],
        ),
      );

      expect(document.pages.single.kind, PageKind.scanned);
    });

    test('an unrecognised source falls back too', () async {
      await box.put(
        'doc-2',
        DocumentModel(
          id: 'doc-2',
          title: 'From a newer build',
          createdAt: DateTime.utc(2026, 5, 1),
          updatedAt: DateTime.utc(2026, 5, 1),
          pages: <DocumentPageModel>[legacyPage()],
          tags: const <String>[],
          pdfPath: null,
          isFavorite: false,
          source: 'dictated',
        ),
      );

      expect(box.get('doc-2')!.toEntity().source, DocumentSource.scanned);
    });
  });

  group('the new shape', () {
    test('a text page persists with no image and comes back as one', () async {
      final document = await roundTrip(
        DocumentModel(
          id: 'note',
          title: 'Meeting note',
          createdAt: DateTime.utc(2026, 8, 8),
          updatedAt: DateTime.utc(2026, 8, 8),
          pages: <DocumentPageModel>[
            DocumentPageModel(
              id: 'text-0',
              imagePath: null,
              index: 0,
              text: 'Agreed to renew in March.',
              ocrStatus: OcrStatus.completed.name,
              kind: PageKind.text.name,
            ),
          ],
          tags: const <String>[],
          pdfPath: null,
          isFavorite: false,
          source: DocumentSource.created.name,
        ),
      );

      final page = document.pages.single;
      expect(page.imagePath, isNull);
      expect(page.hasImage, isFalse);
      expect(page.kind, PageKind.text);
      expect(page.text, 'Agreed to renew in March.');
      expect(document.source, DocumentSource.created);
      expect(document.ocrStatus, OcrStatus.completed);
    });

    test('every kind and source survives a round trip by name', () async {
      // Names, never indices. An index is a position in a list: inserting a
      // case would silently reinterpret every value already stored.
      for (final kind in PageKind.values) {
        final page = await roundTrip(
          legacyDocument(
            pages: <DocumentPageModel>[
              DocumentPageModel(
                id: 'p',
                imagePath: kind == PageKind.text ? null : 'documents/d/p.jpg',
                index: 0,
                text: 'x',
                ocrStatus: OcrStatus.completed.name,
                kind: kind.name,
              ),
            ],
          ),
        );

        expect(page.pages.single.kind, kind);
      }

      for (final source in DocumentSource.values) {
        await box.put(
          'doc-$source',
          DocumentModel(
            id: 'doc-$source',
            title: 't',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
            pages: <DocumentPageModel>[legacyPage()],
            tags: const <String>[],
            pdfPath: null,
            isFavorite: false,
            source: source.name,
          ),
        );

        expect(box.get('doc-$source')!.toEntity().source, source);
      }
    });

    test('a mixed document keeps each page as what it is', () async {
      final document = await roundTrip(
        DocumentModel(
          id: 'mixed',
          title: 'Lease and notes',
          createdAt: DateTime.utc(2026, 8, 8),
          updatedAt: DateTime.utc(2026, 8, 8),
          pages: <DocumentPageModel>[
            legacyPage(id: 'scan', index: 0),
            DocumentPageModel(
              id: 'shot',
              imagePath: 'documents/mixed/shot.jpg',
              index: 1,
              text: '',
              ocrStatus: OcrStatus.pending.name,
              kind: PageKind.imported.name,
            ),
            DocumentPageModel(
              id: 'note',
              imagePath: null,
              index: 2,
              text: 'Ask about the deposit.',
              ocrStatus: OcrStatus.completed.name,
              kind: PageKind.text.name,
            ),
          ],
          tags: const <String>[],
          pdfPath: null,
          isFavorite: false,
          source: DocumentSource.scanned.name,
        ),
      );

      expect(
        document.pages.map((page) => page.kind),
        <PageKind>[PageKind.scanned, PageKind.imported, PageKind.text],
      );
      expect(document.imagePages.map((page) => page.id), <String>[
        'scan',
        'shot',
      ]);
      expect(
        document.ocrStatus,
        OcrStatus.pending,
        reason: 'the imported page has not been read yet',
      );
      expect(document.pagesAwaitingOcr.map((page) => page.id), <String>['shot']);
    });
  });
}
