// Builds the archives the ZIP viewer has to be tested against on a real phone.
//
//   dart run tool/make_test_archives.dart [output directory]
//
// Defaults to `build/test-archives/`. Push them to a device with:
//
//   adb push build/test-archives/. /sdcard/Download/
//
// then open each one from Files, from Downloads, and by sending it through
// WhatsApp to yourself — the three routes differ in which Android intent they
// produce and which of them the app has to survive is the whole of Part A.
//
// Why a script rather than four checked-in binaries: two of these archives are
// deliberately malformed, and a repository that contains a path-traversal ZIP
// is a repository that will one day have it flagged by somebody's scanner. This
// makes them on demand, in about a second, from source anyone can read.

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

void main(List<String> arguments) {
  final directory = Directory(
    arguments.isEmpty ? p.join('build', 'test-archives') : arguments.first,
  )..createSync(recursive: true);

  _write(directory, 'folders.zip', _folders());
  _write(directory, 'nested.zip', _nested());
  _write(directory, 'traversal.zip', _traversal());
  _writeBytes(directory, 'corrupt.zip', _corrupt());
  _writeBytes(directory, 'truncated.zip', _truncated());
  _write(directory, 'bomb.zip', _bomb());

  stdout.writeln('\nArchives written to ${directory.path}');
  stdout.writeln(
    'Expected results:\n'
    '  folders.zip    browses; folders open and Back steps out of them\n'
    '  nested.zip     inner.zip is listed as a file and offers another app\n'
    '  traversal.zip  one entry is refused, and the browser says one was\n'
    '  corrupt.zip    an error screen naming damage — never a crash\n'
    '  truncated.zip  the same error screen, not "this archive is empty"\n'
    '  bomb.zip       bomb.bin is refused; ordinary.txt still lists, and the\n'
    '                 browser reports that one entry was left out\n',
  );
}

/// Folders two deep, a mix of kinds, and a file only another app can open.
Archive _folders() {
  final archive = Archive()
    ..add(ArchiveFile.string('readme.txt', 'A test archive for DocuAI.\n'))
    ..add(ArchiveFile.bytes('invoices/january/bill.pdf', _pdf('January')))
    ..add(ArchiveFile.bytes('invoices/february/bill.pdf', _pdf('February')))
    ..add(
      ArchiveFile.string(
        'invoices/february/note.md',
        '# February\n\nPaid on the 3rd.\n',
      ),
    )
    ..add(ArchiveFile.bytes('photos/scan.png', _png()))
    // Nothing on the device reads this, which is the row that must offer a
    // chooser rather than doing nothing.
    ..add(ArchiveFile.string('data/rows.csv', 'a,b,c\n1,2,3\n'));

  return archive;
}

/// A ZIP inside a ZIP. Must be listed, never unpacked in place.
Archive _nested() {
  final inner = Archive()
    ..add(ArchiveFile.string('inside.txt', 'You should not see this listed.\n'));

  return Archive()
    ..add(ArchiveFile.string('outer.txt', 'The outer archive.\n'))
    ..add(ArchiveFile.bytes('inner.zip', ZipEncoder().encodeBytes(inner)));
}

/// Zip Slip. The entry names a file outside the archive root.
///
/// `../../databases/documents.hive` is not a random choice: it is where this
/// app's library actually lives, so an extractor that honoured the name would
/// overwrite every document the user has. The browser must list `safe.txt`
/// alone and report that one entry was left out.
Archive _traversal() => Archive()
  ..add(ArchiveFile.string('safe.txt', 'This one is fine.\n'))
  ..add(
    ArchiveFile.string(
      '../../databases/documents.hive',
      'if you can read this at that path, the check failed\n',
    ),
  )
  // The same attack written the other way, which a `..`-only check misses.
  ..add(ArchiveFile.string(r'..\..\shared_prefs\owned.xml', 'also blocked\n'))
  // And an absolute path, which a naive join treats as the root.
  ..add(ArchiveFile.string('/sdcard/Download/owned.txt', 'also blocked\n'));

/// An entry far past what one file is allowed to unpack to.
///
/// 160 MB of one repeated byte, against a 128 MB per-entry ceiling. Not a real
/// bomb — a real one is nested and unpacks to petabytes — but it exercises the
/// rule that stops one, without asking the machine building the fixtures for a
/// petabyte.
///
/// The *ratio* rule is deliberately not what this trips, and it is worth
/// knowing why: the `archive` package's own deflate manages about 230:1 on
/// zeros, which is under the 300:1 ceiling. A real zipper reaches a thousand to
/// one on the same input and would be refused on the ratio alone. Both rules
/// exist because neither catches what the other does.
Archive _bomb() => Archive()
  ..add(ArchiveFile.string('ordinary.txt', 'This entry is unremarkable.\n'))
  ..add(ArchiveFile.bytes('bomb.bin', Uint8List(160 * 1024 * 1024)));

/// Not a ZIP at all, wearing the name of one. The commonest "corrupt archive"
/// a user actually meets: a download that returned an error page.
List<int> _corrupt() =>
    '<html><body>404 Not Found</body></html>\n'.codeUnits;

/// A ZIP whose download stopped half way.
///
/// A ZIP's directory lives at its *end*, so this is the interesting case: the
/// front of the file is a perfectly valid archive and the part that says what
/// is in it is missing. A reader that trusts the decoder's empty result reports
/// this as an empty archive, which is the wrong thing to tell somebody whose
/// download failed.
List<int> _truncated() {
  final whole = ZipEncoder().encodeBytes(
    Archive()
      ..add(
        ArchiveFile.string(
          'a.txt',
          'Content long enough that halving the file loses the directory.\n' * 8,
        ),
      ),
  );
  return whole.sublist(0, whole.length ~/ 2);
}

/// A PDF with one page, small enough to write by hand.
///
/// Real enough for Android's own renderer to open, which is what the reader
/// hands it to.
Uint8List _pdf(String title) {
  final content = 'BT /F1 24 Tf 72 700 Td ($title) Tj ET';

  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] '
        '/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
    '<< /Length ${content.length} >>\nstream\n$content\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];

  final buffer = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];

  for (var i = 0; i < objects.length; i++) {
    offsets.add(buffer.length);
    buffer.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }

  final xref = buffer.length;
  buffer
    ..write('xref\n0 ${objects.length + 1}\n')
    ..write('0000000000 65535 f \n');
  for (final offset in offsets) {
    buffer.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  buffer.write(
    'trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
    'startxref\n$xref\n%%EOF\n',
  );

  return Uint8List.fromList(buffer.toString().codeUnits);
}

/// The smallest valid PNG: one opaque pixel.
Uint8List _png() => Uint8List.fromList(<int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
  0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
  0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
  0x00, 0x03, 0x01, 0x01, 0x00, 0x18, 0xDD, 0x8D,
  0xB0, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
  0x44, 0xAE, 0x42, 0x60, 0x82,
]);

void _write(Directory directory, String name, Archive archive) =>
    _writeBytes(directory, name, ZipEncoder().encodeBytes(archive));

void _writeBytes(Directory directory, String name, List<int> bytes) {
  final file = File(p.join(directory.path, name))
    ..writeAsBytesSync(bytes, flush: true);
  stdout.writeln('${name.padRight(16)} ${file.lengthSync()} bytes');
}
