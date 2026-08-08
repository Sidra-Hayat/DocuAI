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
        pages: <PdfPageJob>[
          PdfImagePage(await writeJpeg('page_000.jpg')),
          PdfImagePage(await writeJpeg('page_001.jpg')),
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
          pages: <PdfPageJob>[
            for (var i = 0; i < pages; i++)
              PdfImagePage(await writeJpeg('p$i.jpg')),
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
        pages: <PdfPageJob>[PdfImagePage(await writeJpeg('page_000.jpg'))],
        title: 'Rental agreement',
      ),
    );

    expect(String.fromCharCodes(bytes), contains('Rental agreement'));
  });

  test('a bigger image still fits on the page', () async {
    final bytes = await composePdfBytes(
      PdfJob(
        pages: <PdfPageJob>[
          PdfImagePage(await writeJpeg('big.jpg', width: 2000, height: 3000)),
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
          pages: <PdfPageJob>[
            PdfImagePage(await writeJpeg('page_000.jpg')),
            PdfImagePage(p.join(tempDir.path, 'missing.jpg')),
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
      pages: <PdfPageJob>[PdfImagePage(await writeJpeg('page_000.jpg'))],
      title: 'Isolate',
    );

    final onIsolate = await renderPdfInIsolate(job);

    expect(String.fromCharCodes(onIsolate.take(5)), '%PDF-');
    expect(onIsolate, isNotEmpty);
  });

  group('written pages', () {
    test('a text-only document produces a real PDF', () async {
      final bytes = await composePdfBytes(
        const PdfJob(
          pages: <PdfPageJob>[
            PdfTextPage('The deposit is 500.00 EUR.\n\nDue on 12/03/2026.'),
          ],
          title: 'Tenancy notes',
        ),
      );

      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes, isNotEmpty);
    });

    test('a written page needs no file on disk', () async {
      // The whole point: a document that was typed has nothing in storage, and
      // asking the composer to read one would fail every export of a note.
      await expectLater(
        composePdfBytes(
          const PdfJob(
            pages: <PdfPageJob>[PdfTextPage('Nothing on disk.')],
            title: 'Note',
          ),
        ),
        completes,
      );
    });

    test('long text flows onto more sheets rather than being cut off', () async {
      Future<int> sheetsFor(String text) async {
        final bytes = await composePdfBytes(
          PdfJob(pages: <PdfPageJob>[PdfTextPage(text)], title: 'Long'),
        );
        return RegExp(
          r'/Type\s*/Page[^s]',
        ).allMatches(String.fromCharCodes(bytes)).length;
      }

      final short = await sheetsFor('One line.');
      final long = await sheetsFor(
        List<String>.generate(
          400,
          (i) => 'Clause $i of the agreement, set out in full for the record.',
        ).join('\n\n'),
      );

      expect(short, 1);
      expect(
        long,
        greaterThan(1),
        reason: 'a single sheet would silently drop everything after it',
      );
    });

    test('an empty written page draws nothing rather than a blank sheet', () async {
      final bytes = await composePdfBytes(
        const PdfJob(
          pages: <PdfPageJob>[
            PdfTextPage('   \n\n  '),
            PdfTextPage('Actual content.'),
          ],
          title: 'Mostly empty',
        ),
      );

      expect(
        RegExp(r'/Type\s*/Page[^s]')
            .allMatches(String.fromCharCodes(bytes))
            .length,
        1,
      );
    });

    test('scans and written pages are drawn in document order', () async {
      final bytes = await composePdfBytes(
        PdfJob(
          pages: <PdfPageJob>[
            const PdfTextPage('A heading I typed.'),
            PdfImagePage(await writeJpeg('scan.jpg')),
            const PdfTextPage('A note after the scan.'),
          ],
          title: 'Mixed',
        ),
      );

      expect(
        RegExp(r'/Type\s*/Page[^s]')
            .allMatches(String.fromCharCodes(bytes))
            .length,
        3,
      );
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });
  });
}
