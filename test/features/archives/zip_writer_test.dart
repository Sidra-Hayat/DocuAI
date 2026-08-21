import 'dart:io';

import 'package:archive/archive.dart';
import 'package:docuai/src/features/archives/data/datasources/zip_reader.dart';
import 'package:docuai/src/features/archives/data/datasources/zip_writer.dart';
import 'package:docuai/src/features/archives/domain/entities/zip_build.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The encoder that produces the file somebody else's phone has to open.
///
/// Every test here goes through **real files on disk and a real ZIP**, decoded
/// afterwards by a decoder that knows nothing about how it was made. An
/// assertion against the writer's own bookkeeping would prove the writer agrees
/// with itself; the point of this feature is that WhatsApp, Files and Windows
/// Explorer agree with it.
///
/// The cancellation tests are the ones worth reading. "A stopped build leaves
/// no partial file" is the requirement this datasource was written against —
/// it had already gone wrong once in the import path — and it is checked here
/// as a fact about the file system rather than as a status code.
void main() {
  late Directory workspace;
  late Directory sources;
  late Directory build;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('docuai_zip_writer');
    sources = await Directory(p.join(workspace.path, 'sources')).create();
    build = await Directory(p.join(workspace.path, 'build')).create();
  });

  tearDown(() async {
    if (workspace.existsSync()) await workspace.delete(recursive: true);
  });

  /// Writes a real file and returns its path.
  String file(String name, String contents) {
    final path = p.join(sources.path, name);
    File(path).writeAsStringSync(contents);
    return path;
  }

  /// A file of [kilobytes], compressible enough that deflate has work to do.
  String bulkyFile(String name, int kilobytes) {
    final line = '${'the quick brown fox jumps over the lazy dog ' * 24}\n';
    final buffer = StringBuffer();
    while (buffer.length < kilobytes * 1024) {
      buffer.write(line);
    }
    return file(name, buffer.toString());
  }

  ZipEntryPlan plan(String entryName, String sourcePath) =>
      ZipEntryPlan(entryName: entryName, sourcePath: sourcePath, sourceId: entryName);

  String targetPath([String name = 'archive.zip']) =>
      p.join(workspace.path, name);

  /// Reads the finished archive back with a decoder that has never heard of
  /// this app.
  Archive decode(String path) =>
      ZipDecoder().decodeBytes(File(path).readAsBytesSync());

  group('what it writes', () {
    test('produces an archive an ordinary decoder can read', () async {
      final result = await const ZipWriter().write(
        entries: <ZipEntryPlan>[
          plan('notes.txt', file('a.txt', 'first')),
          plan('report.txt', file('b.txt', 'second')),
        ],
        targetPath: targetPath(),
        buildDirectory: build,
      );

      expect(result.status, ZipWriteStatus.written);
      expect(File(targetPath()).existsSync(), isTrue);

      final archive = decode(targetPath());
      expect(archive.files.map((f) => f.name), <String>['notes.txt', 'report.txt']);
      expect(
        String.fromCharCodes(archive.files.first.readBytes()!),
        'first',
      );
    });

    test('reports the size of the file it actually wrote', () async {
      final result = await const ZipWriter().write(
        entries: <ZipEntryPlan>[plan('a.txt', file('a.txt', 'hello'))],
        targetPath: targetPath(),
        buildDirectory: build,
      );

      expect(result.sizeBytes, File(targetPath()).lengthSync());
      expect(result.path, targetPath());
    });

    test('keeps content byte-for-byte through a deflated entry', () async {
      // Deflate is the path with something to get wrong. A text file is not in
      // the already-compressed list, so this entry is genuinely compressed and
      // genuinely inflated again by the decoder.
      final contents = bulkyFile('big.txt', 64);
      final original = File(contents).readAsStringSync();

      await const ZipWriter().write(
        entries: <ZipEntryPlan>[plan('big.txt', contents)],
        targetPath: targetPath(),
        buildDirectory: build,
      );

      final archive = decode(targetPath());
      expect(
        String.fromCharCodes(archive.files.single.readBytes()!),
        original,
      );
      // And it really was compressed, rather than quietly stored.
      expect(File(targetPath()).lengthSync(), lessThan(original.length));
    });

    test('stores an already-compressed entry instead of deflating it', () async {
      // A JPEG's bytes do not compress, so deflating one costs the whole file
      // being read into memory to save nothing. The name is what decides it —
      // there is no sniffing — so a `.jpg` of text is stored too, which is the
      // observable behaviour worth pinning.
      final path = bulkyFile('photo.jpg', 64);

      await const ZipWriter().write(
        entries: <ZipEntryPlan>[plan('photo.jpg', path)],
        targetPath: targetPath(),
        buildDirectory: build,
      );

      final entry = decode(targetPath()).files.single;
      expect(entry.compression, CompressionType.none);
      // Stored, so it survives the round trip unchanged all the same.
      expect(
        String.fromCharCodes(entry.readBytes()!),
        File(path).readAsStringSync(),
      );
    });

    test('the app can still open what it just wrote', () async {
      // The regression guard across the two halves of this feature. A ZIP
      // DocuAI creates must be one DocuAI can browse — if these ever disagree,
      // the user finds out by sending somebody a file the sender cannot read.
      await const ZipWriter().write(
        entries: <ZipEntryPlan>[
          plan('invoice.pdf', file('a.pdf', '%PDF-1.4 pretend')),
          plan('photo.jpg', file('b.jpg', 'pretend jpeg')),
          plan('notes.txt', file('c.txt', 'plain words')),
        ],
        targetPath: targetPath(),
        buildDirectory: build,
      );

      final listing = ZipReader.listSync(targetPath());

      expect(listing.fileCount, 3);
      expect(listing.refusedEntries, 0);
      expect(
        listing.files.map((entry) => entry.path),
        containsAll(<String>['invoice.pdf', 'photo.jpg', 'notes.txt']),
      );
    });

    test('ordinary text stays inside the reader’s zip-bomb ratio', () async {
      // The two halves of this feature have to agree, and the reader refuses to
      // list an entry claiming better than 300:1. Prose does not come close —
      // this is the guard that says so, and it is what would fail first if the
      // writer ever started compressing harder than the reader will accept.
      final path = bulkyFile('letter.txt', 256);

      await const ZipWriter().write(
        entries: <ZipEntryPlan>[plan('letter.txt', path)],
        targetPath: targetPath(),
        buildDirectory: build,
      );

      final listing = ZipReader.listSync(targetPath());
      expect(listing.refusedEntries, 0);
      expect(listing.files.single.path, 'letter.txt');
    });

    test('degenerate content is the one case the reader will not list', () async {
      // Recorded rather than fixed — see the note on [ZipWriter]. A file of one
      // repeated byte deflates about 650:1, which is indistinguishable from a
      // bomb, so DocuAI's browser leaves it out even though every other
      // extractor opens it. The archive itself is correct.
      final path = p.join(sources.path, 'degenerate.txt');
      File(path).writeAsBytesSync(List<int>.filled(64 * 1024, 65));

      await const ZipWriter().write(
        entries: <ZipEntryPlan>[
          plan('degenerate.txt', path),
          plan('ordinary.txt', bulkyFile('ordinary.txt', 64)),
        ],
        targetPath: targetPath(),
        buildDirectory: build,
      );

      // A general-purpose decoder sees both, which is what the recipient gets.
      expect(decode(targetPath()).files.length, 2);

      // DocuAI's own reader sets the repetitive one aside, and says so rather
      // than silently showing a shorter list.
      final listing = ZipReader.listSync(targetPath());
      expect(listing.fileCount, 1);
      expect(listing.refusedEntries, 1);
    });

    test('leaves no part file behind on success', () async {
      await const ZipWriter().write(
        entries: <ZipEntryPlan>[plan('a.txt', file('a.txt', 'hello'))],
        targetPath: targetPath(),
        buildDirectory: build,
      );

      expect(
        build.listSync().where((e) => e.path.endsWith('.part')),
        isEmpty,
      );
    });
  });

  group('stopping', () {
    test('cancelled before it starts writes nothing at all', () async {
      final result = await const ZipWriter().write(
        entries: <ZipEntryPlan>[plan('a.txt', file('a.txt', 'hello'))],
        targetPath: targetPath(),
        buildDirectory: build,
        isCancelled: () => true,
      );

      expect(result.status, ZipWriteStatus.cancelled);
      expect(result.path, isNull);
      expect(File(targetPath()).existsSync(), isFalse);
      expect(build.listSync(), isEmpty);
    });

    test('cancelled part way leaves neither an archive nor a part file', () async {
      // Cancellation is asked for the moment the first entry is reported, and
      // the poll interval is squeezed so the worker hears about it between
      // entries rather than after all of them.
      var cancelled = false;

      final result = await const ZipWriter(
        pollInterval: Duration(milliseconds: 1),
      ).write(
        entries: <ZipEntryPlan>[
          for (var i = 0; i < 8; i++)
            plan('file_$i.txt', bulkyFile('source_$i.txt', 256)),
        ],
        targetPath: targetPath(),
        buildDirectory: build,
        isCancelled: () => cancelled,
        onProgress: (_) => cancelled = true,
      );

      expect(result.status, ZipWriteStatus.cancelled);

      // The two things that matter, stated as facts about the disk rather than
      // about the return value.
      expect(
        File(targetPath()).existsSync(),
        isFalse,
        reason: 'the target name is only ever claimed by a complete archive',
      );
      expect(
        build.listSync(),
        isEmpty,
        reason: 'the part file is deleted on the way out',
      );
    });

    test('a cancelled build cannot leave a half-archive at the target', () async {
      // The specific shape of the bug this is written against: a stopped job
      // that leaves something at the name the user will go looking for. Even a
      // *valid* ZIP would be wrong here — the user pressed Stop.
      var cancelled = false;

      await const ZipWriter(pollInterval: Duration(milliseconds: 1)).write(
        entries: <ZipEntryPlan>[
          for (var i = 0; i < 8; i++)
            plan('file_$i.txt', bulkyFile('source_$i.txt', 256)),
        ],
        targetPath: targetPath(),
        buildDirectory: build,
        isCancelled: () => cancelled,
        onProgress: (_) => cancelled = true,
      );

      final left = Directory(workspace.path)
          .listSync()
          .map((entity) => p.basename(entity.path))
          .toList()
        ..sort();

      expect(left, <String>['build', 'sources']);
    });
  });

  group('failing', () {
    test('an entry that vanished mid-build is left out, not fatal', () async {
      final missing = p.join(sources.path, 'gone.txt');

      final result = await const ZipWriter().write(
        entries: <ZipEntryPlan>[
          plan('present.txt', file('a.txt', 'here')),
          plan('gone.txt', missing),
        ],
        targetPath: targetPath(),
        buildDirectory: build,
      );

      expect(result.status, ZipWriteStatus.written);
      expect(decode(targetPath()).files.map((f) => f.name), <String>[
        'present.txt',
      ]);
    });

    test('refuses an empty selection rather than writing an empty file', () async {
      final result = await const ZipWriter().write(
        entries: const <ZipEntryPlan>[],
        targetPath: targetPath(),
        buildDirectory: build,
      );

      expect(result.status, ZipWriteStatus.failed);
      expect(File(targetPath()).existsSync(), isFalse);
    });
  });

  group('entry names', () {
    test('leaves distinct names alone', () {
      expect(
        uniqueEntryNames(<String>['a.pdf', 'b.pdf']),
        <String>['a.pdf', 'b.pdf'],
      );
    });

    test('numbers a collision the way a person would', () {
      expect(
        uniqueEntryNames(<String>['Invoice.pdf', 'Invoice.pdf', 'Invoice.pdf']),
        <String>['Invoice.pdf', 'Invoice (2).pdf', 'Invoice (3).pdf'],
      );
    });

    test('treats a case-only difference as a collision', () {
      // It is not one inside the archive, and it is one on the Windows or macOS
      // machine the recipient extracts it on.
      expect(
        uniqueEntryNames(<String>['Invoice.pdf', 'invoice.pdf']),
        <String>['Invoice.pdf', 'invoice (2).pdf'],
      );
    });

    test('does not collide with a name that already looks numbered', () {
      expect(
        uniqueEntryNames(<String>['A.pdf', 'A (2).pdf', 'A.pdf']),
        <String>['A.pdf', 'A (2).pdf', 'A (3).pdf'],
      );
    });

    test('a separator in a title cannot become a folder in the archive', () {
      // A document titled "2024/05 Rent" would otherwise unpack as a directory
      // on the recipient's machine — the same shape of problem the reader
      // refuses on the way in, arriving from the other direction.
      expect(sanitiseEntryName('2024/05 Rent'), '2024_05 Rent');
      expect(sanitiseEntryName(r'C:\accounts'), 'C__accounts');
    });

    test('strips what Windows will not accept at the end of a name', () {
      expect(sanitiseEntryName('Report.'), 'Report');
      expect(sanitiseEntryName('Report  '), 'Report');
    });

    test('never returns an empty name', () {
      expect(sanitiseEntryName('   '), 'document');
      expect(sanitiseEntryName('///'), isNot(isEmpty));
    });

    test('a sanitised title still round-trips through a real archive', () async {
      final name = '${sanitiseEntryName('2024/05 Rent')}.pdf';

      await const ZipWriter().write(
        entries: <ZipEntryPlan>[plan(name, file('a.pdf', 'rent'))],
        targetPath: targetPath(),
        buildDirectory: build,
      );

      final listing = ZipReader.listSync(targetPath());
      expect(listing.files.single.path, '2024_05 Rent.pdf');
    });
  });
}
