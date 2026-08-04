import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/usecases/delete_document.dart';
import 'package:docuai/src/features/documents/domain/usecases/rename_document.dart';
import 'package:docuai/src/features/documents/domain/usecases/toggle_favorite.dart';
import 'package:docuai/src/features/documents/domain/usecases/update_document_tags.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeDocumentRepository documents;
  late FakeSearchRepository search;

  setUp(() {
    documents = FakeDocumentRepository();
    search = FakeSearchRepository();
  });

  tearDown(() => documents.dispose());

  group('RenameDocument', () {
    test('trims the title and stamps updatedAt', () async {
      documents.seed(buildDocument());
      final rename = RenameDocument(documents, clock: fixedClock);

      final result = await rename(
        documentId: 'doc-1',
        title: '  Water bill  ',
      );

      expect(result, isA<Success<Document>>());
      final saved = documents.savedDocuments.single;
      expect(saved.title, 'Water bill');
      expect(saved.updatedAt, kNow);
      expect(saved.createdAt, kEarlier, reason: 'createdAt must not move');
    });

    test('rejects a title that is blank once trimmed', () async {
      documents.seed(buildDocument());
      final rename = RenameDocument(documents, clock: fixedClock);

      final result = await rename(documentId: 'doc-1', title: '   ');

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(documents.savedDocuments, isEmpty);
    });

    test('rejects an over-long title', () async {
      documents.seed(buildDocument());
      final rename = RenameDocument(documents, clock: fixedClock);

      final result = await rename(
        documentId: 'doc-1',
        title: 'x' * (RenameDocument.maxTitleLength + 1),
      );

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(documents.savedDocuments, isEmpty);
    });

    test('does not write when the title is unchanged', () async {
      documents.seed(buildDocument(title: 'Lecture notes'));
      final rename = RenameDocument(documents, clock: fixedClock);

      final result = await rename(
        documentId: 'doc-1',
        title: '  Lecture notes ',
      );

      expect(result.valueOrNull?.updatedAt, kEarlier);
      expect(documents.savedDocuments, isEmpty);
    });

    test('propagates a read failure without attempting a write', () async {
      final rename = RenameDocument(documents, clock: fixedClock);

      final result = await rename(documentId: 'missing', title: 'Anything');

      expect(result.failureOrNull, isA<StorageFailure>());
      expect(documents.savedDocuments, isEmpty);
    });
  });

  group('UpdateDocumentTags', () {
    test('lower-cases, trims and de-duplicates while keeping order', () {
      expect(
        UpdateDocumentTags.normalise(<String>[
          '  Receipts ',
          'receipts',
          'RECEIPTS',
          'Tax',
          '',
          '   ',
        ]),
        <String>['receipts', 'tax'],
      );
    });

    test('drops tags longer than the limit', () {
      final tooLong = 'x' * (UpdateDocumentTags.maxTagLength + 1);

      expect(
        UpdateDocumentTags.normalise(<String>['ok', tooLong]),
        <String>['ok'],
      );
    });

    test('saves the normalised list', () async {
      documents.seed(buildDocument());
      final update = UpdateDocumentTags(documents, clock: fixedClock);

      await update(
        documentId: 'doc-1',
        tags: <String>['University', 'university', ' Notes '],
      );

      expect(documents.savedDocuments.single.tags, <String>[
        'university',
        'notes',
      ]);
      expect(documents.savedDocuments.single.updatedAt, kNow);
    });

    test('rejects more tags than a document may hold', () async {
      documents.seed(buildDocument());
      final update = UpdateDocumentTags(documents, clock: fixedClock);

      final result = await update(
        documentId: 'doc-1',
        tags: <String>[
          for (var i = 0; i <= UpdateDocumentTags.maxTagsPerDocument; i++)
            'tag$i',
        ],
      );

      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(documents.savedDocuments, isEmpty);
    });
  });

  group('ToggleFavorite', () {
    test('flips the flag and leaves updatedAt alone', () async {
      documents.seed(buildDocument(isFavorite: false));
      final toggle = ToggleFavorite(documents);

      final result = await toggle('doc-1');

      expect(result.valueOrNull?.isFavorite, isTrue);
      expect(
        documents.savedDocuments.single.updatedAt,
        kEarlier,
        reason: 'favouriting is a bookmark, not an edit',
      );
    });
  });

  group('DeleteDocument', () {
    test('removes the index entry before deleting the document', () async {
      documents.seed(buildDocument());
      final delete = DeleteDocument(documents: documents, search: search);

      final result = await delete('doc-1');

      expect(result.isSuccess, isTrue);
      expect(search.removedIds, <String>['doc-1']);
      expect(documents.deletedIds, <String>['doc-1']);
      expect(documents.store, isEmpty);
    });

    test('surfaces a delete failure', () async {
      documents
        ..seed(buildDocument())
        ..saveFailure = const StorageFailure('Read-only storage.');
      final delete = DeleteDocument(documents: documents, search: search);

      final result = await delete('doc-1');

      expect(result.failureOrNull, isA<StorageFailure>());
    });
  });
}
