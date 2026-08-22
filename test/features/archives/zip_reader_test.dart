import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:docuai/src/features/archives/data/datasources/zip_reader.dart';
import 'package:docuai/src/features/archives/domain/entities/archive_entry.dart';
import 'package:docuai/src/features/archives/domain/entities/archive_limits.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The reader that decides what a stranger's archive is allowed to do.
///
/// Every test here is written against a **real ZIP file on disk**, built by the
/// same encoder anybody else's zipper would produce something equivalent to,
/// and read through the same code path the app uses. A fake archive object
/// would test the checks against a shape that cannot occur; these test them
/// against the bytes.
///
/// The hostile cases are the point. A ZIP is the one input to this app whose
/// *contents* are chosen by whoever sent it — names, sizes and all — and the
/// four ways that has historically been used to attack an extractor each get a
/// test: escaping the directory, claiming an absolute path, hiding the escape
/// in Windows separators, and claiming an impossible amount of output.
void main() {
  late Directory workspace;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('docuai_zip_reader');
  });

  tearDown(() async {
    if (workspace.existsSync()) await workspace.delete(recursive: true);
  });

  /// Writes a real ZIP holding [entries], and returns its path.
  String writeZip(String name, Map<String, List<int>> entries) {
    final archive = Archive();
    for (final entry in entries.entries) {
      archive.add(ArchiveFile.bytes(entry.key, entry.value));
    }

    final path = p.join(workspace.path, name);
    File(path).writeAsBytesSync(ZipEncoder().encodeBytes(archive), flush: true);
    return path;
  }

  List<int> text(String value) => value.codeUnits;

  group('safeEntryPath', () {
    test('keeps an ordinary nested name', () {
      expect(
        ZipReader.safeEntryPath('invoices/january/bill.pdf'),
        'invoices/january/bill.pdf',
      );
    });

    test('normalises Windows separators, which a real zipper writes', () {
      expect(
        ZipReader.safeEntryPath(r'invoices\january\bill.pdf'),
        'invoices/january/bill.pdf',
      );
    });

    test('drops redundant segments without changing where the file lands', () {
      expect(ZipReader.safeEntryPath('./a//b/./c.txt'), 'a/b/c.txt');
    });

    test('refuses a path that climbs out of the archive', () {
      expect(ZipReader.safeEntryPath('../escaped.txt'), isNull);
      expect(ZipReader.safeEntryPath('a/../../escaped.txt'), isNull);
      // The one that a naive check misses: legal-looking, and it still leaves.
      expect(ZipReader.safeEntryPath('a/b/../../../escaped.txt'), isNull);
    });

    test('refuses a climb hidden in backslashes', () {
      // Without folding separators first, this is a single innocent file name
      // that no `..` check ever sees.
      expect(ZipReader.safeEntryPath(r'a\..\..\escaped.txt'), isNull);
    });

    test('refuses an absolute path', () {
      expect(ZipReader.safeEntryPath('/etc/hosts'), isNull);
      expect(ZipReader.safeEntryPath(r'C:\Windows\System32\drivers'), isNull);
      expect(ZipReader.safeEntryPath(r'\\server\share\file.txt'), isNull);
    });

    test('refuses a name carrying a NUL', () {
      expect(ZipReader.safeEntryPath('good\u0000/../../bad.txt'), isNull);
    });

    test('refuses a name that is nothing at all', () {
      expect(ZipReader.safeEntryPath(''), isNull);
      expect(ZipReader.safeEntryPath('.'), isNull);
      expect(ZipReader.safeEntryPath('/'), isNull);
    });
  });

  group('listing an archive', () {
    test('reports every file with its folder, size and kind', () {
      final path = writeZip('holiday.zip', <String, List<int>>{
        'notes.txt': text('hello'),
        'scans/receipt.pdf': text('%PDF-1.4 not really'),
        'scans/photo.jpg': text('jpeg-ish'),
      });

      final listing = ZipReader.listSync(path);

      expect(listing.name, 'holiday.zip');
      expect(listing.fileCount, 3);
      expect(listing.refusedEntries, 0);

      final receipt = listing.files.firstWhere(
        (file) => file.path == 'scans/receipt.pdf',
      );
      expect(receipt.kind, ArchiveEntryKind.pdf);
      expect(receipt.name, 'receipt.pdf');
      expect(receipt.parent, 'scans');
      expect(receipt.sizeBytes, greaterThan(0));
    });

    test('derives folders from paths, so an entry-less folder still shows', () {
      // Written with no directory entries at all — which is what several
      // zippers produce, and why folders are never read from the archive.
      final path = writeZip('nested.zip', <String, List<int>>{
        'a/b/deep.txt': text('deep'),
        'a/shallow.txt': text('shallow'),
        'root.txt': text('root'),
      });

      final listing = ZipReader.listSync(path);

      final root = listing.childrenOf('');
      expect(root.map((entry) => entry.name), <String>['a', 'root.txt']);
      expect(root.first.kind, ArchiveEntryKind.folder);
      // Two levels down still counts towards the folder that starts here.
      expect(root.first.sizeBytes, greaterThan(0));

      final insideA = listing.childrenOf('a');
      expect(insideA.map((entry) => entry.name), <String>['b', 'shallow.txt']);

      expect(listing.childrenOf('a/b').single.name, 'deep.txt');
    });

    test('a folder holding only subfolders counts them, not zero', () {
      // From a real device: `invoices` contains two month folders and no loose
      // files, and the row read "0 items · 1.2 KB" while offering a chevron
      // into it. Counting only direct *files* is what produced that.
      final path = writeZip('invoices.zip', <String, List<int>>{
        'invoices/january/bill.pdf': text('january'),
        'invoices/february/bill.pdf': text('february'),
        'invoices/february/note.md': text('note'),
      });

      final invoices = ZipReader.listSync(path).childrenOf('').single;

      expect(invoices.name, 'invoices');
      expect(invoices.kind, ArchiveEntryKind.folder);
      // Two subfolders directly inside, whatever is under them.
      expect(invoices.childCount, 2);
      // And the byte total still reaches all the way down.
      expect(invoices.sizeBytes, greaterThan(0));
    });

    test('a subfolder is counted once, not once per file beneath it', () {
      final path = writeZip('deep.zip', <String, List<int>>{
        'top/sub/one.txt': text('1'),
        'top/sub/two.txt': text('2'),
        'top/sub/three.txt': text('3'),
        'top/loose.txt': text('loose'),
      });

      final top = ZipReader.listSync(path).childrenOf('').single;

      // One subfolder plus one loose file, not three plus one.
      expect(top.childCount, 2);
      expect(
        ZipReader.listSync(path).childrenOf('top').map((e) => e.name),
        <String>['sub', 'loose.txt'],
      );
      expect(ZipReader.listSync(path).childrenOf('top/sub').length, 3);
    });

    test('a nested ZIP is listed as a file and never opened', () {
      final inner = writeZip('inner.zip', <String, List<int>>{
        'secret.txt': text('inner'),
      });

      final outer = writeZip('outer.zip', <String, List<int>>{
        'bundle.zip': File(inner).readAsBytesSync(),
        'readme.txt': text('outer'),
      });

      final listing = ZipReader.listSync(outer);

      final bundle = listing.files.firstWhere(
        (file) => file.name == 'bundle.zip',
      );
      expect(bundle.kind, ArchiveEntryKind.archive);
      expect(bundle.kind.isReadable, isFalse);
      expect(bundle.kind.isImportable, isFalse);

      // And nothing from inside it leaked into the outer listing.
      expect(
        listing.files.map((file) => file.name),
        isNot(contains('secret.txt')),
      );
    });
  });

  group('refusing what an archive should not contain', () {
    test('leaves out a path-traversal entry and counts it', () {
      final path = writeZip('malicious.zip', <String, List<int>>{
        '../../databases/documents.hive': text('pwned'),
        'harmless.txt': text('fine'),
      });

      final listing = ZipReader.listSync(path);

      expect(listing.fileCount, 1);
      expect(listing.files.single.path, 'harmless.txt');
      // Counted, not swallowed: the browser says so on screen.
      expect(listing.refusedEntries, 1);
    });

    test('leaves out an absolute path', () {
      final path = writeZip('absolute.zip', <String, List<int>>{
        '/data/data/com.sidrahayat.docuai/files/x': text('pwned'),
        'ok.txt': text('fine'),
      });

      final listing = ZipReader.listSync(path);
      expect(listing.files.single.path, 'ok.txt');
      expect(listing.refusedEntries, 1);
    });

    test('refuses an entry that claims impossible compression', () {
      // A megabyte of one repeated byte: a few hundred bytes stored, and a
      // ratio far past anything real data reaches.
      final path = writeZip('bomb.zip', <String, List<int>>{
        'bomb.bin': Uint8List(1024 * 1024),
        'ok.txt': text('fine'),
      });

      final listing = ZipReader.listSync(
        path,
        limits: const ArchiveLimits(maxRatio: 20),
      );

      expect(listing.files.single.path, 'ok.txt');
      expect(listing.refusedEntries, 1);
    });

    test('refuses an entry larger than the per-entry cap', () {
      final path = writeZip('big.zip', <String, List<int>>{
        'big.bin': Uint8List(64 * 1024),
        'ok.txt': text('fine'),
      });

      final listing = ZipReader.listSync(
        path,
        // Ratio left wide open, so this can only be the size rule firing.
        limits: const ArchiveLimits(maxEntryBytes: 1024, maxRatio: 1000000),
      );

      expect(listing.files.single.path, 'ok.txt');
      expect(listing.refusedEntries, 1);
    });

    test('refuses the whole archive when it holds too many entries', () {
      final path = writeZip('many.zip', <String, List<int>>{
        for (var i = 0; i < 6; i++) 'file_$i.txt': text('x'),
      });

      expect(
        () => ZipReader.listSync(
          path,
          limits: const ArchiveLimits(maxEntries: 3),
        ),
        throwsA(isA<ArchiveReadException>()),
      );
    });

    test('refuses the whole archive when it unpacks to too much', () {
      final path = writeZip('huge.zip', <String, List<int>>{
        'a.bin': Uint8List(8 * 1024),
        'b.bin': Uint8List(8 * 1024),
      });

      expect(
        () => ZipReader.listSync(
          path,
          limits: const ArchiveLimits(
            maxTotalBytes: 10 * 1024,
            maxRatio: 1000000,
          ),
        ),
        throwsA(isA<ArchiveReadException>()),
      );
    });
  });

  group('a file that is not a readable archive', () {
    test('reports damage rather than throwing something raw', () {
      final path = p.join(workspace.path, 'corrupt.zip');
      File(path).writeAsBytesSync(text('this is not a zip file at all'));

      expect(
        () => ZipReader.listSync(path),
        throwsA(
          isA<ArchiveReadException>().having(
            (error) => error.message,
            'message',
            contains('could not be opened'),
          ),
        ),
      );
    });

    test('reports a truncated archive the same way', () {
      final path = writeZip('cut.zip', <String, List<int>>{
        'a.txt': text('some content worth truncating'),
      });

      // Half a download. The central directory lives at the end of a ZIP, so
      // this is the shape a partly-received file actually has.
      final bytes = File(path).readAsBytesSync();
      File(path).writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));

      expect(
        () => ZipReader.listSync(path),
        throwsA(isA<ArchiveReadException>()),
      );
    });

    test('reports an empty file rather than an empty archive', () {
      final path = p.join(workspace.path, 'empty.zip');
      File(path).writeAsBytesSync(<int>[]);

      expect(
        () => ZipReader.listSync(path),
        throwsA(isA<ArchiveReadException>()),
      );
    });

    test('reports a file that is not there', () {
      expect(
        () => ZipReader.listSync(p.join(workspace.path, 'missing.zip')),
        throwsA(isA<ArchiveReadException>()),
      );
    });
  });

  group('extracting one entry', () {
    late Directory into;

    setUp(() async {
      into = await Directory(p.join(workspace.path, 'out')).create();
    });

    test('writes only that entry, and only inside the target folder', () {
      final path = writeZip('two.zip', <String, List<int>>{
        'a/wanted.txt': text('wanted'),
        'b/unwanted.txt': text('unwanted'),
      });

      final written = ZipReader.extractEntrySync(
        archivePath: path,
        entryPath: 'a/wanted.txt',
        intoPath: into.path,
      );

      expect(p.isWithin(into.path, written), isTrue);
      expect(File(written).readAsStringSync(), 'wanted');

      // Lazily: the entry nobody asked for was never written.
      expect(
        into.listSync().map((entity) => p.basename(entity.path)),
        <String>['wanted.txt'],
      );
    });

    test('flattens the entry to a bare name, so no folder is recreated', () {
      final path = writeZip('deep.zip', <String, List<int>>{
        'a/b/c/report.pdf': text('report'),
      });

      final written = ZipReader.extractEntrySync(
        archivePath: path,
        entryPath: 'a/b/c/report.pdf',
        intoPath: into.path,
      );

      expect(p.dirname(written), into.path);
      expect(p.basename(written), 'report.pdf');
    });

    test('a crafted entry path cannot write outside the target', () {
      final path = writeZip('two.zip', <String, List<int>>{
        'wanted.txt': text('wanted'),
      });

      // The second line of defence, tested on its own: even handed a path the
      // listing would never have produced, extraction writes inside the folder
      // it was given or not at all.
      expect(
        () => ZipReader.extractEntrySync(
          archivePath: path,
          entryPath: '../../wanted.txt',
          intoPath: into.path,
        ),
        throwsA(isA<ArchiveReadException>()),
      );

      expect(into.listSync(), isEmpty);
      expect(
        File(p.join(workspace.path, 'wanted.txt')).existsSync(),
        isFalse,
      );
    });

    test('a prefix keeps same-named entries from overwriting each other', () {
      final path = writeZip('months.zip', <String, List<int>>{
        'january/summary.txt': text('january'),
        'february/summary.txt': text('february'),
      });

      final first = ZipReader.extractEntrySync(
        archivePath: path,
        entryPath: 'january/summary.txt',
        intoPath: into.path,
        prefix: 'a_',
      );
      final second = ZipReader.extractEntrySync(
        archivePath: path,
        entryPath: 'february/summary.txt',
        intoPath: into.path,
        prefix: 'b_',
      );

      expect(first, isNot(second));
      expect(File(first).readAsStringSync(), 'january');
      expect(File(second).readAsStringSync(), 'february');
    });

    test('an entry that is not in the archive is reported, not invented', () {
      final path = writeZip('one.zip', <String, List<int>>{
        'a.txt': text('a'),
      });

      expect(
        () => ZipReader.extractEntrySync(
          archivePath: path,
          entryPath: 'b.txt',
          intoPath: into.path,
        ),
        throwsA(isA<ArchiveReadException>()),
      );
    });

    test('the size rules are re-checked at extraction, not merely at listing', () {
      final path = writeZip('bomb.zip', <String, List<int>>{
        'bomb.bin': Uint8List(1024 * 1024),
      });

      expect(
        () => ZipReader.extractEntrySync(
          archivePath: path,
          entryPath: 'bomb.bin',
          intoPath: into.path,
          limits: const ArchiveLimits(maxRatio: 20),
        ),
        throwsA(isA<ArchiveReadException>()),
      );

      expect(into.listSync(), isEmpty);
    });
  });
}
