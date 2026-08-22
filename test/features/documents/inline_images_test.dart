import 'dart:io';

import 'package:docuai/hive_registrar.g.dart';
import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/core/text/markup.dart';
import 'package:docuai/src/core/text/markup_editing.dart';
import 'package:docuai/src/features/assistant/data/datasources/passage_extractor.dart';
import 'package:docuai/src/features/documents/data/datasources/document_local_data_source.dart';
import 'package:docuai/src/features/documents/data/models/document_model.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/documents/domain/usecases/insert_inline_image.dart';
import 'package:docuai/src/features/export/data/datasources/docx_composer.dart';
import 'package:docuai/src/features/export/data/datasources/pdf_composer.dart';
import 'package:docuai/src/features/export/data/repositories/export_repository_impl.dart';
import 'package:docuai/src/features/import/domain/repositories/image_import_repository.dart';
import 'package:docuai/src/features/search/data/datasources/search_tokenizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';

/// Pictures inside a written document.
///
/// The design in one sentence: a picture is a line of markup naming a file in
/// the document's own folder, which means the thing that changed is the *text*
/// and nothing about how a document is stored. Everything below is either a
/// consequence of that or a guard on it.
///
/// Two properties matter more than any individual case:
///
///  * **A picture is never text.** Search indexes words and the assistant
///    quotes sentences; the name of a JPEG is neither, and both must be unable
///    to see one.
///  * **Nothing existing moves.** A document written before this feature must
///    produce the same extracted text, the same tokens and the same passages as
///    it did before — byte for byte, so the index does not even need rebuilding.
void main() {
  const marker = '![Image](9c2e1f4a.jpg)';

  group('the markup', () {
    test('a picture line is recognised and names its file', () {
      final blocks = Markup.parse('Before\n$marker\nAfter');

      expect(blocks.map((block) => block.kind), <MarkupBlockKind>[
        MarkupBlockKind.paragraph,
        MarkupBlockKind.image,
        MarkupBlockKind.paragraph,
      ]);
      expect(blocks[1].imageName, '9c2e1f4a.jpg');
    });

    test('mixed text and pictures keep their order', () {
      final blocks = Markup.parse(
        'One\n![Image](a.jpg)\nTwo\n![Image](b.jpg)\nThree',
      );

      expect(
        blocks.map(
          (block) => block.kind == MarkupBlockKind.image
              ? block.imageName
              : block.text,
        ),
        <String>['One', 'a.jpg', 'Two', 'b.jpg', 'Three'],
      );
    });

    test('a reference inside a sentence stays ordinary text', () {
      // The format is line-based. Treating a mid-sentence reference as a
      // picture would mean a paragraph that is partly a block, which nothing
      // downstream could lay out.
      final blocks = Markup.parse('See ![Image](a.jpg) here');

      expect(blocks.single.kind, MarkupBlockKind.paragraph);
    });

    test('withoutImages removes the line and leaves the words', () {
      expect(Markup.withoutImages('Before\n$marker\nAfter'), 'Before\nAfter');
    });

    test('withoutImages returns text with no pictures unchanged', () {
      // The property the whole design rests on: every document written before
      // this feature is untouched by it.
      for (final text in <String>[
        'Total amount due: 248.60 EUR',
        '# Heading\n- bullet\n> quote\n**bold** and *italic*',
        'A line with (parentheses) and [brackets]',
        '',
      ]) {
        expect(Markup.withoutImages(text), same(text), reason: text);
      }
    });

    test('the whole line is a marker, so stripping drops it', () {
      expect(Markup.toInlineText('Before\n$marker\nAfter'), 'Before After');
    });
  });

  group('inserting and removing', () {
    test('a picture is placed at the caret on a line of its own', () {
      const edit = TextEdit(text: 'Before after', start: 6, end: 6);

      final result = MarkupEditing.insertImage(edit, 'a.jpg');

      expect(result.text, 'Before\n![Image](a.jpg)\n\n after');
      expect(
        result.text.substring(result.start),
        ' after',
        reason: 'the caret is left where writing continues',
      );
    });

    test('inserting into an empty page adds no leading blank line', () {
      const edit = TextEdit(text: '', start: 0, end: 0);

      expect(
        MarkupEditing.insertImage(edit, 'a.jpg').text,
        '![Image](a.jpg)\n\n',
      );
    });

    test('removing takes the line and its break', () {
      const text = 'One\n![Image](a.jpg)\nTwo';
      const edit = TextEdit(text: text, start: 6, end: 6);

      expect(MarkupEditing.removeImageAt(edit).text, 'One\nTwo');
    });

    test('removing does nothing when the caret is not on a picture', () {
      const edit = TextEdit(text: 'One\nTwo', start: 1, end: 1);

      expect(MarkupEditing.removeImageAt(edit).text, 'One\nTwo');
    });
  });

  group('picking a picture', () {
    late FakeDocumentRepository documents;

    setUp(() => documents = FakeDocumentRepository());
    tearDown(() => documents.dispose());

    InsertInlineImage useCase(_FakeImageImporter importer) =>
        InsertInlineImage(importer: importer, documents: documents);

    test('a chosen picture is copied and its name returned', () async {
      final importer = _FakeImageImporter(
        const ImportOutcome(imagePaths: <String>['/cache/docuai_import/x.jpg']),
      );

      final result = await useCase(importer)(documentId: 'doc');

      expect(result, isA<Success<String>>());
      expect(
        documents.inlineImages.values,
        contains('/cache/docuai_import/x.jpg'),
        reason: 'the picker output is what gets copied',
      );
    });

    test('a dismissed picker is silent, not an error', () async {
      final importer = _FakeImageImporter(
        const ImportOutcome(imagePaths: <String>[]),
      );

      final result = await useCase(importer)(documentId: 'doc');

      final failure = (result as Failed<String>).failure as ImportFailure;
      expect(
        failure.cancelled,
        isTrue,
        reason: 'the user knows they backed out; a message would be noise',
      );
    });

    test('an unreadable picture is reported', () async {
      final importer = _FakeImageImporter(
        const ImportOutcome(
          imagePaths: <String>[],
          rejected: <String>['x.heic'],
        ),
      );

      final result = await useCase(importer)(documentId: 'doc');

      final failure = (result as Failed<String>).failure as ImportFailure;
      expect(failure.cancelled, isFalse);
      expect(failure.message, contains('could not be read'));
    });

    test('a failed copy is reported rather than swallowed', () async {
      documents.inlineImageFailure = const StorageFailure('The disk is full.');
      final importer = _FakeImageImporter(
        const ImportOutcome(imagePaths: <String>['/cache/x.jpg']),
      );

      final result = await useCase(importer)(documentId: 'doc');

      expect((result as Failed<String>).failure.message, 'The disk is full.');
    });
  });

  group('storage', () {
    late Directory tempDir;
    late Box<DocumentModel> box;
    late StoragePaths paths;
    late DocumentLocalDataSource source;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('docuai_inline');
      Hive.init(p.join(tempDir.path, 'hive'));
      Hive.registerAdapters();
    });

    setUp(() async {
      box = await Hive.openBox<DocumentModel>(
        'docs_${DateTime.now().microsecondsSinceEpoch}',
      );
      paths = StoragePaths(tempDir);
      source = DocumentLocalDataSource(box: box, paths: paths);
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

    Future<File> aPicture(String name) async {
      final file = File(p.join(tempDir.path, name));
      await file.writeAsBytes(<int>[1, 2, 3, 4]);
      return file;
    }

    test(
      'the picture is copied into the document, not referenced in place',
      () async {
        final document = await source.createTextDocument(title: 'Notes');
        final picked = await aPicture('picked.jpg');

        final name = await source.addInlineImage(document.id, picked.path);

        final stored = File(paths.inlineImagePath(document.id, name));
        expect(stored.existsSync(), isTrue);
        expect(await stored.readAsBytes(), <int>[1, 2, 3, 4]);
        expect(
          picked.existsSync(),
          isTrue,
          reason: 'copied, never moved — the picker owns its own file',
        );
      },
    );

    test('the temporary path is never what gets persisted', () async {
      final document = await source.createTextDocument(title: 'Notes');
      final picked = await aPicture('temp_cache.jpg');

      final name = await source.addInlineImage(document.id, picked.path);
      final saved = await source.updatePageText(
        document.id,
        document.pages.first.id,
        'Look:\n![Image]($name)',
      );

      final text = saved.pages.first.text;
      expect(text, contains(name));
      expect(
        text,
        isNot(contains(picked.path)),
        reason: 'a cache path in a document is a picture that vanishes',
      );
      expect(text, isNot(contains(tempDir.path)));
    });

    test('the picture is still there when the document is reopened', () async {
      final document = await source.createTextDocument(title: 'Notes');
      final picked = await aPicture('survives.jpg');
      final name = await source.addInlineImage(document.id, picked.path);

      await source.updatePageText(
        document.id,
        document.pages.first.id,
        '![Image]($name)',
      );

      // Reading back through Hive is the closest a host test gets to a restart:
      // the record comes off disk and the file is found from what it says.
      final reopened = source.read(document.id).toEntity();
      final referenced = Markup.imageNames(reopened.pages.first.text).single;

      expect(referenced, name);
      expect(
        File(paths.inlineImagePath(document.id, referenced)).existsSync(),
        isTrue,
      );
    });

    test('removing a picture from the text deletes its file', () async {
      final document = await source.createTextDocument(title: 'Notes');
      final name = await source.addInlineImage(
        document.id,
        (await aPicture('doomed.jpg')).path,
      );
      final pageId = document.pages.first.id;

      await source.updatePageText(document.id, pageId, 'Text\n![Image]($name)');
      expect(
        File(paths.inlineImagePath(document.id, name)).existsSync(),
        isTrue,
      );

      await source.updatePageText(document.id, pageId, 'Text');

      expect(
        File(paths.inlineImagePath(document.id, name)).existsSync(),
        isFalse,
        reason: 'a picture nothing refers to is a picture nobody can reach',
      );
    });

    test('a picture still referenced is never swept', () async {
      final document = await source.createTextDocument(title: 'Notes');
      final keep = await source.addInlineImage(
        document.id,
        (await aPicture('keep.jpg')).path,
      );
      final drop = await source.addInlineImage(
        document.id,
        (await aPicture('drop.jpg')).path,
      );
      final pageId = document.pages.first.id;

      await source.updatePageText(
        document.id,
        pageId,
        '![Image]($keep)\n![Image]($drop)',
      );
      await source.updatePageText(document.id, pageId, '![Image]($keep)');

      expect(
        File(paths.inlineImagePath(document.id, keep)).existsSync(),
        isTrue,
      );
      expect(
        File(paths.inlineImagePath(document.id, drop)).existsSync(),
        isFalse,
      );
    });

    test('the sweep cannot reach a scanned page', () async {
      // The reason inline pictures live in their own subfolder. A sweep that
      // ran over the document directory would be one predicate away from
      // deleting the pages themselves.
      final picked = await aPicture('page.jpg');
      final document = await source.create(
        title: 'Scan',
        sourceImagePaths: <String>[picked.path],
      );

      await source.addTextPage(document.id);
      final reloaded = source.read(document.id);
      await source.updatePageText(document.id, reloaded.pages.last.id, 'Typed');

      final pagePath = source.read(document.id).pages.first.imagePath!;
      expect(File(paths.absolutePath(pagePath)).existsSync(), isTrue);
    });
  });

  group('search and the assistant never see a picture', () {
    Document withText(String text) => buildDocument(
      id: 'doc',
      title: 'Notes',
      source: DocumentSource.created,
      pages: <DocumentPage>[buildTextPage(id: 'p0', index: 0, text: text)],
    );

    test('extractedText leaves the reference out', () {
      final document = withText('The meter was replaced.\n$marker\nSigned.');

      expect(document.extractedText, 'The meter was replaced.\nSigned.');
    });

    test('no part of a filename becomes a search token', () {
      final document = withText('Notes\n$marker');
      final tokens = SearchTokenizer.tokenize(document.extractedText);

      for (final fragment in <String>['9c2e1f4a', 'jpg', 'image']) {
        expect(tokens, isNot(contains(fragment)), reason: fragment);
      }
      expect(tokens, contains('notes'));
    });

    test('extractedText is identical for a document with no pictures', () {
      // Same string, therefore same tokens, therefore the same index — an
      // existing library does not even need rebuilding.
      final plain = buildDocument(
        pages: <DocumentPage>[
          buildTextPage(id: 'a', index: 0, text: 'First page.'),
          buildTextPage(id: 'b', index: 1, text: 'Second page.'),
        ],
      );

      expect(plain.extractedText, 'First page.\n\nSecond page.');
    });

    test('a passage is never taken from a picture line', () {
      final document = withText(
        'The standing charge applies to every account here.\n'
        '$marker\n'
        'Payment is due at the end of the quarter.',
      );

      final passages = PassageExtractor.extract(document);

      expect(passages, isNotEmpty);
      for (final passage in passages) {
        expect(passage.text, isNot(contains('9c2e1f4a')));
        expect(passage.pageText, isNot(contains('9c2e1f4a')));
      }
    });

    test('a page holding nothing but a picture yields no passages', () {
      expect(PassageExtractor.extract(withText(marker)), isEmpty);
    });

    test('citation offsets index into the text the passage came from', () {
      // The offsets travel with the passage and are used to widen a citation.
      // Stripping in one place and not the other would put every citation a
      // marker's width out of step.
      final document = withText(
        '$marker\nThe standing charge applies to every account here.',
      );

      for (final passage in PassageExtractor.extract(document)) {
        expect(
          passage.pageText.substring(passage.start, passage.end),
          contains(passage.text.split(' ').first),
        );
      }
    });
  });

  group('PDF', () {
    test('draws text and pictures in the order the page holds them', () async {
      final job = PdfJob(
        title: 'Notes',
        pages: <PdfPageJob>[
          PdfTextPage(
            'One\n![Image](a.jpg)\nTwo',
            images: <String, String>{'a.jpg': _aRealJpeg()},
          ),
        ],
      );

      final bytes = await composePdfBytes(job);

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('fails clearly when a referenced picture is gone', () async {
      final job = PdfJob(
        title: 'Notes',
        pages: <PdfPageJob>[
          const PdfTextPage(
            'One\n![Image](missing.jpg)',
            images: <String, String>{},
          ),
        ],
      );

      await expectLater(
        composePdfBytes(job),
        throwsA(isA<PdfImageMissingException>()),
        reason: 'a PDF quietly missing a picture is discovered after sending',
      );
    });

    test('a scanned document still exports exactly as it did', () async {
      final job = PdfJob(
        title: 'Scan',
        pages: <PdfPageJob>[PdfImagePage(_aRealJpeg())],
      );

      expect(await composePdfBytes(job), isNotEmpty);
    });
  });

  group('Word export', () {
    test('refuses a document holding a picture, and says why', () async {
      final job = DocxJob(
        title: 'Notes',
        pages: <DocxPage>[DocxPage('One\n$marker\nTwo')],
      );

      await expectLater(
        composeDocxBytes(job),
        throwsA(isA<DocxImageUnsupportedException>()),
      );
    });

    test(
      'the repository turns that into advice rather than an error',
      () async {
        final repository = ExportRepositoryImpl(
          paths: StoragePaths(Directory.systemTemp),
        );

        final result = await repository.buildDocx(
          buildDocument(
            id: 'doc',
            source: DocumentSource.created,
            pages: <DocumentPage>[
              buildTextPage(id: 'p0', index: 0, text: 'One\n$marker'),
            ],
          ),
        );

        final message = (result as Failed<String>).failure.message;
        expect(message, contains('pictures'));
        expect(
          message,
          contains('PDF'),
          reason: 'a refusal that names no way forward is a dead end',
        );
      },
    );

    test('a text-only document still exports', () async {
      final job = DocxJob(
        title: 'Notes',
        pages: <DocxPage>[const DocxPage('# Heading\nOrdinary text.')],
      );

      expect(await composeDocxBytes(job), isNotEmpty);
    });
  });
}

/// A real JPEG on disk.
///
/// Encoded rather than hand-written: the composer reads the bytes and the `pdf`
/// package sniffs the format, so a stub that is not genuinely a JPEG tests the
/// error path by accident.
String _aRealJpeg() {
  final file = File(
    p.join(Directory.systemTemp.path, 'docuai_inline_probe.jpg'),
  );
  if (!file.existsSync()) {
    file.writeAsBytesSync(
      img.encodeJpg(img.Image(width: 8, height: 8), quality: 80),
    );
  }
  return file.path;
}

/// Stands in for the photo picker.
class _FakeImageImporter implements ImageImportRepository {
  _FakeImageImporter(this._outcome);

  final ImportOutcome _outcome;

  @override
  FutureResult<ImportOutcome> pickImages({int limit = 30}) async =>
      Success(_outcome);

  @override
  FutureResult<ImportOutcome> readImages(
    List<String> paths, {
    int limit = 30,
  }) async => Success(_outcome);
}
