import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/import/data/datasources/document_text_extractor.dart';
import 'package:docuai/src/features/import/domain/repositories/file_import_repository.dart';
import 'package:docuai/src/features/import/domain/usecases/import_file.dart';
import 'package:docuai/src/features/import/domain/usecases/import_images.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

/// Bringing a file in from the device.
///
/// The rasteriser is not exercised here — it is a thin call into the platform's
/// own PDF renderer, and a unit test of it would be a test of Android. What is
/// tested is everything around it: what the extractors make of a file's bytes,
/// and what the use case does with the two kinds of result.
void main() {
  group('plain text', () {
    test('decodes UTF-8', () {
      final bytes = Uint8List.fromList(utf8.encode('Deposit: 500,00 €'));

      expect(DocumentTextExtractor.plainText(bytes), 'Deposit: 500,00 €');
    });

    test('drops a byte-order mark', () {
      // Notepad on Windows writes one, and left in place it becomes an
      // invisible first character that search then fails to match on.
      final bytes = Uint8List.fromList(utf8.encode('﻿Heading'));

      expect(DocumentTextExtractor.plainText(bytes), 'Heading');
    });

    test('survives bytes that are not UTF-8 at all', () {
      // A file saved in some other encoding should import mostly-readable and
      // be correctable by hand, not refuse to open.
      final bytes = Uint8List.fromList(<int>[0x48, 0x69, 0xFF, 0xFE]);

      expect(DocumentTextExtractor.plainText(bytes), startsWith('Hi'));
    });
  });

  group('word documents', () {
    /// Builds the smallest `.docx` that is still one: a ZIP with the one part
    /// the extractor reads.
    Uint8List docx(String documentXml) {
      final archive = Archive()
        ..addFile(
          ArchiveFile(
            'word/document.xml',
            documentXml.length,
            utf8.encode(documentXml),
          ),
        );

      return Uint8List.fromList(ZipEncoder().encode(archive));
    }

    test('reads paragraphs in order', () {
      final bytes = docx('''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>Tenancy agreement</w:t></w:r></w:p>
    <w:p><w:r><w:t>The deposit is </w:t></w:r><w:r><w:t>500 EUR.</w:t></w:r></w:p>
  </w:body>
</w:document>''');

      expect(
        DocumentTextExtractor.wordDocument(bytes),
        'Tenancy agreement\nThe deposit is 500 EUR.',
        reason: 'runs within one paragraph are one line, not two',
      );
    });

    test('keeps line breaks and tabs inside a paragraph', () {
      final bytes = docx('''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>Line one</w:t><w:br/><w:t>Line two</w:t></w:r></w:p>
  </w:body>
</w:document>''');

      expect(DocumentTextExtractor.wordDocument(bytes), 'Line one\nLine two');
    });

    test('collapses runs of empty paragraphs', () {
      // Word documents are full of blank paragraphs used as spacing. Carried
      // over one for one, they produce a page that is mostly gaps.
      final bytes = docx('''
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    <w:p><w:r><w:t>Above</w:t></w:r></w:p>
    <w:p/><w:p/><w:p/>
    <w:p><w:r><w:t>Below</w:t></w:r></w:p>
  </w:body>
</w:document>''');

      expect(DocumentTextExtractor.wordDocument(bytes), 'Above\n\nBelow');
    });

    test('returns nothing for a file that is not a Word document', () {
      // The caller turns this into "that file could not be read", which is the
      // honest answer for a `.doc` renamed to `.docx`.
      final bytes = Uint8List.fromList(utf8.encode('not a zip at all'));

      expect(DocumentTextExtractor.wordDocument(bytes), isEmpty);
    });
  });

  group('importing a file', () {
    late FakeDocumentRepository documents;
    late FakeSearchRepository search;

    setUp(() {
      documents = FakeDocumentRepository();
      search = FakeSearchRepository();
    });

    tearDown(() => documents.dispose());

    ImportFileAsDocument useCase(_FakeFileImporter importer) =>
        ImportFileAsDocument(
          importer: importer,
          documents: documents,
          search: search,
        );

    test('a text file becomes a document you can already search', () async {
      final result = await useCase(
        _FakeFileImporter(
          const ImportedFile(
            name: 'Tenancy notes',
            kind: ImportedFileKind.text,
            text: 'The deposit is 500 EUR.',
          ),
        ),
      )();

      final document = (result as Success<ImportResult>).value.document;

      expect(document.title, 'Tenancy notes', reason: 'named after the file');
      expect(document.pages.single.text, 'The deposit is 500 EUR.');
      expect(
        search.indexedIds,
        contains(document.id),
        reason:
            'there is no text to recognise, so nothing else would ever index it',
      );
    });

    test('a PDF becomes pages, left for recognition to read', () async {
      final result = await useCase(
        _FakeFileImporter(
          const ImportedFile(
            name: 'Electricity bill',
            kind: ImportedFileKind.pages,
            imagePaths: <String>['/tmp/a.jpg', '/tmp/b.jpg'],
          ),
        ),
      )();

      final document = (result as Success<ImportResult>).value.document;

      expect(document.pages, hasLength(2));
      expect(document.source, DocumentSource.imported);
      expect(document.pages.first.kind, PageKind.imported);
      expect(
        search.indexedIds,
        isEmpty,
        reason: 'a page nobody has read yet has nothing to index',
      );
    });

    test('backing out of the picker stays silent', () async {
      final result = await useCase(
        _FakeFileImporter.failing(
          const ImportFailure('No file was chosen.', cancelled: true),
        ),
      )();

      final failure = (result as Failed<ImportResult>).failure;

      expect(
        (failure as ImportFailure).cancelled,
        isTrue,
        reason: 'the user knows they dismissed it; a snackbar would be noise',
      );
    });

    test('an empty file is reported rather than filed', () async {
      final result = await useCase(
        _FakeFileImporter(
          const ImportedFile(name: 'Blank', kind: ImportedFileKind.text),
        ),
      )();

      expect(result, isA<Failed<ImportResult>>());
      expect(documents.store, isEmpty);
    });
  });
}

class _FakeFileImporter implements FileImportRepository {
  _FakeFileImporter(this._file) : _failure = null;
  _FakeFileImporter.failing(Failure failure) : _file = null, _failure = failure;

  final ImportedFile? _file;
  final Failure? _failure;

  @override
  FutureResult<ImportedFile> pickFile() async {
    final failure = _failure;
    if (failure != null) return Failed<ImportedFile>(failure);
    return Success<ImportedFile>(_file!);
  }
}
