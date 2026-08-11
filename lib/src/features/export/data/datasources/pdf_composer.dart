import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../../core/text/markup.dart';

/// A picture the document refers to and the exporter could not find.
///
/// Its own type rather than a generic failure so the repository can say which
/// file is missing, and so the message a user sees names the document rather
/// than a path they have never seen.
class PdfImageMissingException implements Exception {
  const PdfImageMissingException(this.imageName);

  final String imageName;

  @override
  String toString() => 'PdfImageMissingException: $imageName';
}

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
  const PdfTextPage(this.text, {this.images = const <String, String>{}});

  final String text;

  /// Every picture the text names, mapped to where the file actually is.
  ///
  /// Resolved by the caller rather than here, because the text stores bare
  /// filenames and only the repository knows which document's folder they
  /// belong to — and because this object crosses an isolate, where a
  /// `StoragePaths` would be useless.
  final Map<String, String> images;
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

      case PdfTextPage(:final text, :final images):
        final blocks = Markup.parse(text);
        // Nothing written on it. A blank sheet in the middle of a document is
        // noise, and the caller has already refused a document with nothing in
        // it at all.
        if (blocks.isEmpty) continue;

        // Decoded before the page is built, because a picture has to be read
        // from disk and building a widget tree is synchronous. Ordered by
        // block, so the widgets below can take them in the order they appear.
        final decoded = <int, pw.MemoryImage>{};
        for (var i = 0; i < blocks.length; i++) {
          final name = blocks[i].imageName;
          if (blocks[i].kind != MarkupBlockKind.image || name == null) continue;

          final path = images[name];
          // Loudly, never quietly. A PDF silently missing a picture is worse
          // than one that failed: the user finds out after sending it to
          // somebody, and by then the document is the record.
          if (path == null) {
            throw PdfImageMissingException(name);
          }

          final file = File(path);
          if (!file.existsSync()) throw PdfImageMissingException(name);

          decoded[i] = pw.MemoryImage(await file.readAsBytes());
        }

        document.addPage(
          // MultiPage, not Page: written text has no fixed extent, and a single
          // sheet would silently cut off everything past the first page.
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            // Margins here where the image pages have none. A scan carries its
            // own borders; set text needs its own.
            margin: const pw.EdgeInsets.symmetric(horizontal: 56, vertical: 64),
            // One list, in block order, so a picture lands exactly where the
            // text put it. MultiPage flows the whole sequence across sheets.
            build: (context) => <pw.Widget>[
              for (var i = 0; i < blocks.length; i++)
                if (decoded[i] case final image?)
                  _imageWidget(image)
                else
                  _blockWidget(blocks[i]),
            ],
          ),
        );
    }
  }

  return document.save();
}

/// Places a picture in the flow of the text.
///
/// Bounded in height rather than scaled to the page. A picture dropped into a
/// paragraph is an illustration, not a plate: letting a tall photograph take a
/// whole sheet would break the reading in a way the writer did not ask for.
pw.Widget _imageWidget(pw.MemoryImage image) => pw.Container(
  margin: const pw.EdgeInsets.symmetric(vertical: 10),
  alignment: pw.Alignment.centerLeft,
  child: pw.ConstrainedBox(
    constraints: const pw.BoxConstraints(maxHeight: 320),
    child: pw.Image(image, fit: pw.BoxFit.contain),
  ),
);

/// Sets one parsed line.
///
/// Headings, lists and quotes are *drawn*, never reproduced as their markers.
/// A `# Total` sitting in an exported PDF would be worse than no formatting at
/// all: it shows the reader the syntax instead of the result.
pw.Widget _blockWidget(MarkupBlock block) {
  final inline = pw.RichText(
    text: pw.TextSpan(
      children: <pw.InlineSpan>[
        for (final span in block.spans)
          pw.TextSpan(
            text: span.text,
            style: pw.TextStyle(
              fontWeight: span.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              fontStyle: span.italic
                  ? pw.FontStyle.italic
                  : pw.FontStyle.normal,
            ),
          ),
      ],
    ),
  );

  return switch (block.kind) {
    // Handled by the caller, which has the decoded bytes. Reaching here means
    // a block was classified as a picture and then not resolved, which is a
    // bug rather than a document problem.
    MarkupBlockKind.image => pw.SizedBox.shrink(),
    MarkupBlockKind.heading1 => _heading(block, 20, 14),
    MarkupBlockKind.heading2 => _heading(block, 16, 12),
    MarkupBlockKind.heading3 => _heading(block, 13, 10),
    MarkupBlockKind.bullet => _listItem('•', inline),
    MarkupBlockKind.numbered => _listItem('${block.number ?? 1}.', inline),
    MarkupBlockKind.quote => pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6, left: 12),
      padding: const pw.EdgeInsets.only(left: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          left: pw.BorderSide(color: PdfColors.grey500, width: 2),
        ),
      ),
      child: pw.DefaultTextStyle(
        style: pw.TextStyle(
          fontSize: 11,
          lineSpacing: 3,
          fontStyle: pw.FontStyle.italic,
          color: PdfColors.grey800,
        ),
        child: inline,
      ),
    ),
    MarkupBlockKind.paragraph => pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      child: pw.DefaultTextStyle(
        style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
        child: inline,
      ),
    ),
  };
}

/// Headings are set from their plain text: emphasis inside one adds nothing to
/// a line that is already bold and larger than everything around it.
pw.Widget _heading(MarkupBlock block, double size, double topGap) =>
    pw.Container(
      margin: pw.EdgeInsets.only(top: topGap, bottom: size / 3),
      child: pw.Text(
        block.text,
        style: pw.TextStyle(fontSize: size, fontWeight: pw.FontWeight.bold),
      ),
    );

pw.Widget _listItem(String marker, pw.Widget content) => pw.Container(
  margin: const pw.EdgeInsets.only(bottom: 4, left: 8),
  child: pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: <pw.Widget>[
      pw.SizedBox(
        width: 18,
        child: pw.Text(marker, style: const pw.TextStyle(fontSize: 11)),
      ),
      pw.Expanded(
        child: pw.DefaultTextStyle(
          style: const pw.TextStyle(fontSize: 11, lineSpacing: 3),
          child: content,
        ),
      ),
    ],
  ),
);

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
