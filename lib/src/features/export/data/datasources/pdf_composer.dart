import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Everything the renderer needs, as plain data.
///
/// Deliberately holds absolute paths and strings only: this object is sent to
/// another isolate, so it must not carry anything tied to the sending one —
/// no `StoragePaths`, no entities, no providers.
class PdfJob {
  const PdfJob({required this.imagePaths, required this.title});

  final List<String> imagePaths;
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

  for (final path in job.imagePaths) {
    final image = pw.MemoryImage(await File(path).readAsBytes());

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (context) =>
            pw.Center(child: pw.Image(image, fit: pw.BoxFit.contain)),
      ),
    );
  }

  return document.save();
}

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
