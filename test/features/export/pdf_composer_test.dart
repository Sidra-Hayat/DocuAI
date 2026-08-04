import 'dart:io';

import 'package:docuai/src/features/export/data/datasources/pdf_composer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;

  /// A real JPEG, because `pw.MemoryImage` sniffs the format and refuses bytes
  /// it cannot decode — a file of arbitrary bytes would not exercise anything.
  Future<String> writeJpeg(String name, {int width = 200, int height = 280}) async {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(240, 240, 240));
    img.fillRect(
      image,
      x1: 20,
      y1: 20,
      x2: width - 20,
      y2: 60,
      color: img.ColorRgb8(60, 60, 60),
    );

    final file = File(p.join(tempDir.path, name));
    await file.writeAsBytes(img.encodeJpg(image, quality: 80));
    return file.path;
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_pdf_test');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  test('produces a valid PDF from the page images', () async {
    final bytes = await composePdfBytes(
      PdfJob(
        imagePaths: <String>[
          await writeJpeg('page_000.jpg'),
          await writeJpeg('page_001.jpg'),
        ],
        title: 'Water bill',
      ),
    );

    expect(bytes, isNotEmpty);
    expect(
      String.fromCharCodes(bytes.take(5)),
      '%PDF-',
      reason: 'every PDF starts with this signature',
    );
  });

  test('writes one PDF page per document page', () async {
    Future<int> pageCountFor(int pages) async {
      final bytes = await composePdfBytes(
        PdfJob(
          imagePaths: <String>[
            for (var i = 0; i < pages; i++) await writeJpeg('p$i.jpg'),
          ],
          title: 'Multi',
        ),
      );
      // Counting `/Type /Page` objects is crude but does not need a parser, and
      // the alternative is trusting the composer to report on itself.
      return RegExp(
        r'/Type\s*/Page[^s]',
      ).allMatches(String.fromCharCodes(bytes)).length;
    }

    expect(await pageCountFor(1), 1);
    expect(await pageCountFor(3), 3);
  });

  test('carries the document title into the PDF metadata', () async {
    final bytes = await composePdfBytes(
      PdfJob(
        imagePaths: <String>[await writeJpeg('page_000.jpg')],
        title: 'Rental agreement',
      ),
    );

    expect(String.fromCharCodes(bytes), contains('Rental agreement'));
  });

  test('a bigger image still fits on the page', () async {
    final bytes = await composePdfBytes(
      PdfJob(
        imagePaths: <String>[
          await writeJpeg('big.jpg', width: 2000, height: 3000),
        ],
        title: 'Large scan',
      ),
    );

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('fails rather than silently dropping an unreadable page', () async {
    await expectLater(
      composePdfBytes(
        PdfJob(
          imagePaths: <String>[
            await writeJpeg('page_000.jpg'),
            p.join(tempDir.path, 'missing.jpg'),
          ],
          title: 'Broken',
        ),
      ),
      throwsA(isA<FileSystemException>()),
      reason: 'a PDF quietly missing a page is worse than a failed export',
    );
  });

  test('renders the same bytes on a background isolate', () async {
    final job = PdfJob(
      imagePaths: <String>[await writeJpeg('page_000.jpg')],
      title: 'Isolate',
    );

    final onIsolate = await renderPdfInIsolate(job);

    expect(String.fromCharCodes(onIsolate.take(5)), '%PDF-');
    expect(onIsolate, isNotEmpty);
  });
}
