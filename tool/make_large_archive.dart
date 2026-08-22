// Builds the archive the small fixtures cannot stand in for.
//
//   dart run tool/make_large_archive.dart [output directory]
//
// Seventeen importable files and roughly 55 MB of them, which is the shape of
// the archive that exposed three bugs at once on a real device: an import that
// could not be stopped, thirteen files that never arrived and never explained
// themselves, and a browser that opened inside the sending app's task.
//
// None of that reproduces on `folders.zip`. Six entries totalling 1.4 KB import
// faster than a person can reach for Stop, and a PDF of one hand-written page
// rasterises in a frame. Size is the test.
//
// Deliberately all-importable: eight PDFs, six photographs and three text
// files. If the app drops one, the drop is the app's and not the archive's.

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

Future<void> main(List<String> arguments) async {
  final directory = Directory(
    arguments.isEmpty ? p.join('build', 'test-archives') : arguments.first,
  )..createSync(recursive: true);

  stdout.writeln('Building photographs…');
  // One base photograph per PDF page and per loose picture. Generated rather
  // than checked in, for the same reason as the small fixtures: 55 MB of
  // binaries in a repository is 55 MB in every clone, forever.
  final photos = <Uint8List>[
    for (var i = 0; i < 6; i++) _photograph(seed: i),
  ];

  final archive = Archive();

  // ---- Eight PDFs, three pages each --------------------------------------
  stdout.writeln('Building PDFs…');
  for (var i = 0; i < 8; i++) {
    final bytes = await _pdf(
      title: 'Statement ${i + 1}',
      pages: <Uint8List>[
        photos[i % photos.length],
        photos[(i + 1) % photos.length],
        photos[(i + 2) % photos.length],
      ],
    );
    final folder = i < 4 ? 'statements/2026' : 'statements/2025';
    archive.add(ArchiveFile.bytes('$folder/statement_${i + 1}.pdf', bytes));
  }

  // ---- Six photographs ----------------------------------------------------
  for (var i = 0; i < photos.length; i++) {
    archive.add(ArchiveFile.bytes('photos/scan_${i + 1}.jpg', photos[i]));
  }

  // ---- Three text files ---------------------------------------------------
  for (var i = 0; i < 3; i++) {
    archive.add(
      ArchiveFile.string(
        'notes/note_${i + 1}.txt',
        'Note ${i + 1}\n\n${'This is a line of an ordinary note. ' * 40}\n',
      ),
    );
  }

  stdout.writeln('Compressing…');
  final path = p.join(directory.path, 'large.zip');
  File(path).writeAsBytesSync(ZipEncoder().encodeBytes(archive), flush: true);

  final megabytes = (File(path).lengthSync() / (1024 * 1024)).toStringAsFixed(1);
  stdout.writeln(
    '\nlarge.zip  $megabytes MB  ${archive.files.length} files\n'
    '  8 PDFs (3 pages each) · 6 photographs · 3 text files\n'
    '  All seventeen are formats DocuAI imports, so anything missing from the\n'
    '  library afterwards is the app dropping it.\n',
  );
}

/// A photograph-sized JPEG that does not compress.
///
/// Smooth gradients plus noise, because a flat colour deflates to nothing and
/// the point of this fixture is its weight. Roughly 2–3 MB each at this size.
Uint8List _photograph({required int seed}) {
  const width = 2600;
  const height = 1900;

  final random = Random(seed);
  final image = img.Image(width: width, height: height);

  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final r = (x * 255 ~/ width + seed * 40) % 256;
      final g = (y * 255 ~/ height + seed * 25) % 256;
      const b = 128;
      final noise = random.nextInt(48) - 24;

      image.setPixelRgb(
        x,
        y,
        (r + noise).clamp(0, 255),
        (g + noise).clamp(0, 255),
        (b + noise).clamp(0, 255),
      );
    }
  }

  return img.encodeJpg(image, quality: 90);
}

/// A real multi-page PDF, one full-bleed photograph per page.
///
/// Composed with the same `pdf` package the app exports with, so what the
/// device's renderer is handed is a PDF of the kind it actually meets.
Future<Uint8List> _pdf({
  required String title,
  required List<Uint8List> pages,
}) async {
  final document = pw.Document(title: title);

  for (final page in pages) {
    final image = pw.MemoryImage(page);
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Image(image, fit: pw.BoxFit.cover),
        ),
      ),
    );
  }

  return document.save();
}
