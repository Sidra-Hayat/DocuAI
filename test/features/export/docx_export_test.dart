import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/export/data/datasources/docx_composer.dart';
import 'package:docuai/src/features/export/data/repositories/export_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';

/// Turning a document into a Word file.
///
/// The division of labour between the two exports is the thing to hold: a PDF
/// is a copy of the pages, a Word file is the text to work on. A scan's
/// recognised text belongs in the second — it is the part of a scan anyone
/// would want to edit — and a document with no text belongs in neither.
void main() {
  late Directory tempDir;
  late StoragePaths paths;
  late List<DocxJob> written;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_docx');
    paths = StoragePaths(tempDir);
    written = <DocxJob>[];
  });

  tearDown(() async {
    try {
      if (tempDir.existsSync()) await tempDir.delete(recursive: true);
    } on FileSystemException {
      // Windows may still hold a handle; the OS reclaims it.
    }
  });

  /// Records the job and returns a byte marker, so the repository's own
  /// behaviour is under test rather than the composer's.
  ExportRepositoryImpl repository() => ExportRepositoryImpl(
    paths: paths,
    docxWriter: (job) async {
      written.add(job);
      return Uint8List.fromList(<int>[0x50, 0x4B, 0x03, 0x04]);
    },
  );

  /// The real composer, for the cases that are about the file itself.
  ExportRepositoryImpl realRepository() =>
      ExportRepositoryImpl(paths: paths, docxWriter: composeDocxBytes);

  group('what goes in', () {
    test('a written document exports its text', () async {
      final note = buildDocument(
        id: 'note',
        title: 'Tenancy notes',
        source: DocumentSource.created,
        pages: <DocumentPage>[
          buildTextPage(id: 't0', index: 0, text: '# Deposit\n500.00 EUR'),
        ],
      );

      final result = await repository().buildDocx(note);

      expect(result, isA<Success<String>>());
      expect(written.single.pages.single.text, '# Deposit\n500.00 EUR');
      expect(written.single.title, 'Tenancy notes');
    });

    test("a scan's recognised text is included", () async {
      // A Word file is wanted because it can be edited, and the recognised
      // text is the part of a scan anyone would want to edit.
      final scan = buildDocument(
        id: 'bill',
        pages: <DocumentPage>[
          buildPage(
            id: 'p0',
            index: 0,
            text: 'Total amount due: 248.60 EUR',
            ocrStatus: OcrStatus.completed,
          ),
        ],
      );

      await repository().buildDocx(scan);

      expect(written.single.pages.single.text, 'Total amount due: 248.60 EUR');
    });

    test('pages keep their order across kinds', () async {
      final mixed = buildDocument(
        id: 'mixed',
        pages: <DocumentPage>[
          buildTextPage(id: 't0', index: 0, text: 'Typed first.'),
          buildPage(
            id: 'p1',
            index: 1,
            imagePath: 'a/p1.jpg',
            text: 'Scanned second.',
            ocrStatus: OcrStatus.completed,
          ),
        ],
      );

      await repository().buildDocx(mixed);

      expect(written.single.pages.map((page) => page.text), <String>[
        'Typed first.',
        'Scanned second.',
      ]);
    });

    test('a page with no text contributes nothing', () async {
      final document = buildDocument(
        id: 'doc',
        pages: <DocumentPage>[
          buildPage(id: 'p0', index: 0, text: 'Has text.', ocrStatus: OcrStatus.completed),
          buildPage(id: 'p1', index: 1, imagePath: 'a/p1.jpg'),
        ],
      );

      await repository().buildDocx(document);

      expect(
        written.single.pages,
        hasLength(1),
        reason: 'a blank page in a Word file is a blank page in a Word file',
      );
    });
  });

  group('refusing rather than writing an empty file', () {
    test('a scan whose text has not been recognised yet', () async {
      final unread = buildDocument(
        id: 'bill',
        pages: <DocumentPage>[buildPage(id: 'p0', index: 0)],
      );

      final result = await repository().buildDocx(unread);

      expect(result, isA<Failed<String>>());
      expect(written, isEmpty);

      final message = (result as Failed<String>).failure.message;
      expect(message, contains('Recognise the text'));
      expect(
        message,
        contains('PDF'),
        reason: 'the pages can still be sent — say so rather than dead-ending',
      );
    });

    test('an empty written document', () async {
      final blank = buildDocument(
        id: 'note',
        source: DocumentSource.created,
        pages: <DocumentPage>[buildTextPage(id: 't0', index: 0, text: '')],
      );

      final result = await repository().buildDocx(blank);

      expect(result, isA<Failed<String>>());
      expect(
        (result as Failed<String>).failure.message,
        contains('nothing written'),
      );
    });

    test('nothing is left on disk after a refusal', () async {
      final blank = buildDocument(
        id: 'note',
        source: DocumentSource.created,
        pages: <DocumentPage>[buildTextPage(id: 't0', index: 0, text: '')],
      );

      await repository().buildDocx(blank);

      final folder = Directory(p.join(paths.documentsRoot.path, 'note'));
      expect(
        folder.existsSync() ? folder.listSync() : const <FileSystemEntity>[],
        isEmpty,
      );
    });
  });

  group('the written file', () {
    test('lands in the document folder, named after the document', () async {
      final note = buildDocument(
        id: 'note',
        title: 'Tenancy notes',
        source: DocumentSource.created,
        pages: <DocumentPage>[
          buildTextPage(id: 't0', index: 0, text: 'Something.'),
        ],
      );

      final relative = (await realRepository().buildDocx(note)).valueOrNull!;

      expect(p.basename(relative), 'Tenancy notes.docx');
      expect(p.isRelative(relative), isTrue);
      expect(File(paths.absolutePath(relative)).existsSync(), isTrue);
    });

    test('is a readable zip holding a Word document', () async {
      final note = buildDocument(
        id: 'note',
        source: DocumentSource.created,
        pages: <DocumentPage>[
          buildTextPage(id: 't0', index: 0, text: 'The deposit is 500.00 EUR.'),
        ],
      );

      final relative = (await realRepository().buildDocx(note)).valueOrNull!;
      final archive = ZipDecoder().decodeBytes(
        await File(paths.absolutePath(relative)).readAsBytes(),
      );

      final document = archive.findFile('word/document.xml');
      expect(document, isNotNull);
      expect(
        utf8.decode(document!.content as List<int>),
        contains('The deposit is 500.00 EUR.'),
      );
    });

    test('is rebuilt from scratch every time, so it cannot go stale', () async {
      // No path is stored on the document, which is the simplest possible
      // answer to "never export stale content": there is nothing to be stale.
      var note = buildDocument(
        id: 'note',
        source: DocumentSource.created,
        pages: <DocumentPage>[
          buildTextPage(id: 't0', index: 0, text: 'First draft.'),
        ],
      );

      await realRepository().buildDocx(note);

      note = note.copyWith(
        pages: <DocumentPage>[
          buildTextPage(id: 't0', index: 0, text: 'Second draft.'),
        ],
      );
      final relative = (await realRepository().buildDocx(note)).valueOrNull!;

      final archive = ZipDecoder().decodeBytes(
        await File(paths.absolutePath(relative)).readAsBytes(),
      );
      final xml = utf8.decode(
        archive.findFile('word/document.xml')!.content as List<int>,
      );

      expect(xml, contains('Second draft.'));
      expect(xml, isNot(contains('First draft.')));
      expect(
        note.pdfPath,
        isNull,
        reason: 'no docx path is recorded on the document either',
      );
    });

    test('a writer that throws becomes a clear failure', () async {
      final note = buildDocument(
        id: 'note',
        source: DocumentSource.created,
        pages: <DocumentPage>[
          buildTextPage(id: 't0', index: 0, text: 'Something.'),
        ],
      );

      final result = await ExportRepositoryImpl(
        paths: paths,
        docxWriter: (job) async => throw StateError('out of memory'),
      ).buildDocx(note);

      expect(result, isA<Failed<String>>());
      expect(
        (result as Failed<String>).failure,
        isA<ExportFailure>(),
        reason: 'a repository that promised not to throw must not throw',
      );
      expect(result.failure.message, contains('Word file'));
    });
  });
}
