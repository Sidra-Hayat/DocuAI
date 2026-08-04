import 'dart:io';
import 'dart:typed_data';

import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/export/data/datasources/pdf_composer.dart';
import 'package:docuai/src/features/export/data/repositories/export_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../helpers/fakes.dart';

void main() {
  late Directory tempDir;
  late StoragePaths paths;
  late List<PdfJob> rendered;
  late List<ShareParams> shared;
  late ShareResult shareResult;

  /// Renders inline instead of spawning an isolate per case, and records the
  /// job so the tests can assert on what the repository asked for.
  Future<Uint8List> fakeRenderer(PdfJob job) async {
    rendered.add(job);
    return Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46, 0x2D, 1, 2, 3]);
  }

  Future<ShareResult> fakeLauncher(ShareParams params) async {
    shared.add(params);
    return shareResult;
  }

  ExportRepositoryImpl buildRepository() => ExportRepositoryImpl(
    paths: paths,
    renderer: fakeRenderer,
    launcher: fakeLauncher,
  );

  /// Writes the page files a document claims to have.
  Future<Document> seedDocumentFiles(Document document) async {
    for (final page in document.pages) {
      final file = File(paths.absolutePath(page.imagePath));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(<int>[0xFF, 0xD8, 0xFF, 0xD9]);
    }
    return document;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_export_test');
    paths = StoragePaths(tempDir);
    rendered = <PdfJob>[];
    shared = <ShareParams>[];
    shareResult = const ShareResult('ok', ShareResultStatus.success);
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  group('buildPdf', () {
    test('writes the PDF inside the document folder and returns a relative path',
        () async {
      final document = await seedDocumentFiles(buildDocument());

      final result = await buildRepository().buildPdf(document);

      final relative = result.valueOrNull!;
      expect(p.isRelative(relative), isTrue);
      expect(File(paths.absolutePath(relative)).existsSync(), isTrue);
      expect(p.split(relative), contains('doc-1'));
    });

    test('names the file after the document', () async {
      final document = await seedDocumentFiles(
        buildDocument(title: 'Rental agreement'),
      );

      final result = await buildRepository().buildPdf(document);

      expect(p.basename(result.valueOrNull!), 'Rental agreement.pdf');
    });

    test('strips characters a filesystem or a recipient would reject', () async {
      final document = await seedDocumentFiles(
        buildDocument(title: 'Invoice: 42/2026 <final>'),
      );

      final result = await buildRepository().buildPdf(document);
      final name = p.basename(result.valueOrNull!);

      expect(name, 'Invoice 422026 final.pdf');
      expect(name, isNot(contains('/')));
      expect(name, isNot(contains(':')));
    });

    test('falls back to a generic name when nothing usable survives', () async {
      final document = await seedDocumentFiles(buildDocument(title: '///'));

      final result = await buildRepository().buildPdf(document);

      expect(p.basename(result.valueOrNull!), 'document.pdf');
    });

    test('passes every page to the renderer, in order, as absolute paths',
        () async {
      final document = await seedDocumentFiles(
        buildDocument(
          pages: <DocumentPage>[
            buildPage(id: 'a', index: 0, imagePath: 'documents/doc-1/p0.jpg'),
            buildPage(id: 'b', index: 1, imagePath: 'documents/doc-1/p1.jpg'),
          ],
        ),
      );

      await buildRepository().buildPdf(document);

      expect(rendered.single.imagePaths, hasLength(2));
      expect(rendered.single.imagePaths.every(p.isAbsolute), isTrue);
      expect(rendered.single.imagePaths.first, endsWith('p0.jpg'));
      expect(rendered.single.title, 'Lecture notes');
    });

    test('refuses before rendering when a page image is missing', () async {
      // Deliberately not seeded: the file the document points at is absent.
      final document = buildDocument();

      final result = await buildRepository().buildPdf(document);

      expect(result.failureOrNull, isA<ExportFailure>());
      expect(
        rendered,
        isEmpty,
        reason: 'a missing page must fail in milliseconds, not after rendering',
      );
      expect(result.failureOrNull!.message, contains('Page 1'));
    });

    test('overwrites a previous export rather than accumulating files',
        () async {
      final document = await seedDocumentFiles(buildDocument());
      final repository = buildRepository();

      final first = await repository.buildPdf(document);
      final second = await repository.buildPdf(document);

      expect(first.valueOrNull, second.valueOrNull);
      final folder = Directory(p.join(tempDir.path, 'documents', 'doc-1'));
      expect(
        folder.listSync().where((e) => e.path.endsWith('.pdf')),
        hasLength(1),
      );
    });

    test('reports a renderer failure as an ExportFailure', () async {
      final document = await seedDocumentFiles(buildDocument());
      final repository = ExportRepositoryImpl(
        paths: paths,
        renderer: (job) async => throw const FileSystemException('nope'),
        launcher: fakeLauncher,
      );

      final result = await repository.buildPdf(document);

      expect(result.failureOrNull, isA<ExportFailure>());
    });
  });

  group('shareFile', () {
    Future<String> writePdf() async {
      final file = File(p.join(tempDir.path, 'documents', 'doc-1', 'out.pdf'));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(<int>[0x25, 0x50, 0x44, 0x46]);
      return paths.relativePath(file.path);
    }

    test('hands the share sheet an absolute path and the subject', () async {
      final relative = await writePdf();

      final result = await buildRepository().shareFile(
        relative,
        subject: 'Water bill',
      );

      expect(result.isSuccess, isTrue);
      expect(shared.single.subject, 'Water bill');
      expect(p.isAbsolute(shared.single.files!.single.path), isTrue);
      expect(shared.single.files!.single.path, endsWith('out.pdf'));
    });

    test('a dismissed sheet is a success, not an error', () async {
      shareResult = const ShareResult('', ShareResultStatus.dismissed);

      final result = await buildRepository().shareFile(await writePdf());

      expect(
        result.isSuccess,
        isTrue,
        reason: 'Android reports dismissed for completed shares it cannot '
            'describe, so this must not surface as a failure',
      );
    });

    test('reports when nothing on the device can receive the file', () async {
      shareResult = ShareResult.unavailable;

      final result = await buildRepository().shareFile(await writePdf());

      expect(result.failureOrNull, isA<ExportFailure>());
    });

    test('reports a PDF that has vanished from storage', () async {
      final result = await buildRepository().shareFile(
        'documents/doc-1/gone.pdf',
      );

      expect(result.failureOrNull, isA<ExportFailure>());
      expect(result.failureOrNull!.message, contains('Export it again'));
      expect(shared, isEmpty);
    });

    test('reports a platform error from the share sheet', () async {
      final relative = await writePdf();
      final repository = ExportRepositoryImpl(
        paths: paths,
        renderer: fakeRenderer,
        launcher: (params) async => throw Exception('no activity'),
      );

      final result = await repository.shareFile(relative);

      expect(result.failureOrNull, isA<ExportFailure>());
    });
  });
}
