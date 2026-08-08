import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// One page to draw.
///
/// A sealed pair rather than two lists, because the order pages are drawn in is
/// the order the document holds them — and a document may interleave scans and
/// written pages freely.
sealed class PdfPageJob {
  const PdfPageJob();
}

/// A scanned or imported page: an image file to place on the sheet.
final class PdfImagePage extends PdfPageJob {
  const PdfImagePage(this.absolutePath);

  final String absolutePath;
}

/// A written page: text to set and flow across as many sheets as it needs.
final class PdfTextPage extends PdfPageJob {
  const PdfTextPage(this.text);

  final String text;
}

/// Everything the renderer needs, as plain data.
///
/// Deliberately holds absolute paths and strings only: this object is sent to
/// another isolate, so it must not carry anything tied to the sending one —
/// no `StoragePaths`, no entities, no providers.
class PdfJob {
  const PdfJob({required this.pages, required this.title});

  final List<PdfPageJob> pages;
  final String title;
}

/// Renders [job] into PDF bytes.
///
/// A top-level function because that is what an isolate entry point has to be.
///
/// Every page becomes one A4 page with the image scaled to fit and no margin —
/// the scan already has its own borders, and adding more would shrink the
/// content twice.
///
/// A page whose image cannot be read aborts the whole export rather than being
/// skipped. A PDF that is quietly missing page 3 is worse than one that failed
/// loudly: the user would only discover it after sending the file to someone.
Future<Uint8List> composePdfBytes(PdfJob job) async {
  final document = pw.Document(title: job.title, producer: 'DocuAI');

  for (final page in job.pages) {
    switch (page) {
      case PdfImagePage(:final absolutePath):
        final image = pw.MemoryImage(await File(absolutePath).readAsBytes());

        document.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: pw.EdgeInsets.zero,
            build: (context) =>
                pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
          ),
        );

      case PdfTextPage(:final text):
        final paragraphs = _paragraphsOf(text);
        // Nothing written on it. A blank sheet in the middle of a document is
        // noise, and the caller has already refused a document with nothing in
        // it at all.
        if (paragraphs.isEmpty) continue;

        document.addPage(
          // MultiPage, not Page: written text has no fixed extent, and a single
          // sheet would silently cut off everything past the first page.
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            // Margins here where the image pages have none. A scan carries its
            // own borders; set text needs its own.
            margin: const pw.EdgeInsets.symmetric(
              horizontal: 56,
              vertical: 64,
            ),
            build: (context) => <pw.Widget>[
              for (final paragraph in paragraphs)
                pw.Paragraph(
                  text: paragraph,
                  style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
                ),
            ],
          ),
        );
    }
  }

  return document.save();
}

/// Splits written text into paragraphs on blank lines.
///
/// Single newlines are left inside a paragraph, where the layout engine wraps
/// them as part of the same block. That matches how the text was typed: a blank
/// line is a deliberate break, a wrapped line is not.
List<String> _paragraphsOf(String text) => text
    .split(RegExp(r'\n[ \t]*\n+'))
    .map((paragraph) => paragraph.trim())
    .where((paragraph) => paragraph.isNotEmpty)
    .toList(growable: false);

/// How the composer runs a job. Injected so tests can render inline instead of
/// paying for an isolate spawn per case.
typedef PdfRenderer = Future<Uint8List> Function(PdfJob job);

/// Renders on a background isolate.
///
/// Composition decodes and re-encodes every page image, which for a twenty-page
/// document is seconds of CPU. On the UI isolate that is a frozen app and a
/// dropped frame count in the hundreds; the `pdf` package is pure Dart, so
/// moving the work costs nothing but the hop.
Future<Uint8List> renderPdfInIsolate(PdfJob job) =>
    Isolate.run(() => composePdfBytes(job));
