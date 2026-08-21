import 'dart:async';
import 'dart:io';

import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/core/router/app_routes.dart';
import 'package:docuai/src/features/archives/data/datasources/external_opener.dart';
import 'package:docuai/src/features/archives/domain/entities/archive_entry.dart';
import 'package:docuai/src/features/archives/domain/repositories/archive_repository.dart';
import 'package:docuai/src/features/archives/presentation/providers/archive_providers.dart';
import 'package:docuai/src/features/archives/presentation/screens/archive_screen.dart';
import 'package:docuai/src/features/documents/presentation/providers/document_providers.dart';
import 'package:docuai/src/features/import/domain/repositories/file_import_repository.dart';
import 'package:docuai/src/features/import/presentation/providers/import_providers.dart';
import 'package:docuai/src/features/search/presentation/providers/search_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;

import '../../helpers/fakes.dart';

/// The archive browser, as a user meets it.
///
/// The behaviour under test is a distinction rather than a feature: **reading
/// is not importing**. A ZIP that opens straight into "import 34 files?" is the
/// thing this screen exists not to be, so the tests check both halves — that
/// tapping a file opens a reader and leaves the library alone, and that
/// importing happens only when it is asked for by name.
void main() {
  late Directory workspace;
  late FakeDocumentRepository documents;
  late FakeSearchRepository search;
  late _FakeArchiveRepository archives;
  late _RecordingOpener opener;

  /// Two folders and a spread of kinds: something readable, something
  /// importable, something neither.
  ArchiveListing buildListing() => ArchiveListing(
    name: 'Invoices 2026.zip',
    sourcePath: p.join(workspace.path, 'Invoices 2026.zip'),
    archiveBytes: 4096,
    files: <ArchiveEntry>[
      const ArchiveEntry(
        path: 'january/bill.pdf',
        kind: ArchiveEntryKind.pdf,
        sizeBytes: 2048,
        compressedBytes: 1024,
      ),
      const ArchiveEntry(
        path: 'january/notes.txt',
        kind: ArchiveEntryKind.text,
        sizeBytes: 128,
        compressedBytes: 64,
      ),
      const ArchiveEntry(
        path: 'receipts.zip',
        kind: ArchiveEntryKind.archive,
        sizeBytes: 999,
        compressedBytes: 900,
      ),
      const ArchiveEntry(
        path: 'readme.md',
        kind: ArchiveEntryKind.text,
        sizeBytes: 64,
        compressedBytes: 32,
      ),
    ],
  );

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('docuai_archive_screen');
    documents = FakeDocumentRepository();
    search = FakeSearchRepository();
    archives = _FakeArchiveRepository(workspace);
    opener = _RecordingOpener();
  });

  tearDown(() async {
    documents.dispose();
    if (workspace.existsSync()) await workspace.delete(recursive: true);
  });

  /// The browser on a real router, because opening an entry is a route push.
  Future<void> pumpBrowser(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => ArchiveScreen(
            args: ArchiveArgs(
              path: p.join(workspace.path, 'Invoices 2026.zip'),
              name: 'Invoices 2026.zip',
            ),
          ),
          routes: <RouteBase>[
            GoRoute(
              path: 'entry',
              name: AppRoutes.archiveEntryName,
              builder: (context, state) =>
                  const Scaffold(body: Text('the reader')),
            ),
            GoRoute(
              path: 'document/:id',
              name: AppRoutes.documentDetailName,
              builder: (context, state) =>
                  const Scaffold(body: Text('the document')),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        // Untyped, because Riverpod 3 does not export its `Override` type —
        // the same reason `bootstrap()` takes no overrides parameter.
        overrides: [
          archiveRepositoryProvider.overrideWithValue(archives),
          externalOpenerProvider.overrideWithValue(opener),
          documentRepositoryProvider.overrideWithValue(documents),
          searchRepositoryProvider.overrideWithValue(search),
          // A real importer over fake storage: what "through the existing
          // pipeline" claims is only worth testing end to end.
          fileImportRepositoryProvider.overrideWithValue(
            const _FakeFileImporter(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('describing the archive', () {
    testWidgets('says what it holds before anything is unpacked', (
      tester,
    ) async {
      archives.listing = buildListing();
      await pumpBrowser(tester);

      expect(find.text('Invoices 2026.zip'), findsWidgets);
      expect(find.textContaining('4 files'), findsOneWidget);
      // Both sizes, because the gap between them is what matters before
      // importing anything.
      expect(find.textContaining('unpacked'), findsOneWidget);
      expect(find.textContaining('as a ZIP'), findsOneWidget);
    });

    testWidgets('says so when entries were left out as unsafe', (tester) async {
      final listing = buildListing();
      archives.listing = ArchiveListing(
        name: listing.name,
        sourcePath: listing.sourcePath,
        archiveBytes: listing.archiveBytes,
        files: listing.files,
        refusedEntries: 2,
      );

      await pumpBrowser(tester);

      expect(find.textContaining('2 entries left out'), findsOneWidget);
    });

    testWidgets('shows an error screen for a damaged archive', (tester) async {
      archives.failure = const ImportFailure(
        'That archive could not be opened. It may be damaged.',
      );

      await pumpBrowser(tester);

      expect(find.text('Could not open this archive'), findsOneWidget);
      expect(find.textContaining('may be damaged'), findsOneWidget);
      // An error screen, not a crash and not an empty list.
      expect(find.byType(ListView), findsNothing);
    });
  });

  group('moving around inside it', () {
    testWidgets('folders come first, and tapping one goes in', (tester) async {
      archives.listing = buildListing();
      await pumpBrowser(tester);

      expect(find.text('january'), findsOneWidget);
      expect(find.text('readme.md'), findsOneWidget);
      // Nothing from inside the folder is on screen yet.
      expect(find.text('bill.pdf'), findsNothing);

      await tester.tap(find.text('january'));
      await tester.pumpAndSettle();

      expect(find.text('bill.pdf'), findsOneWidget);
      expect(find.text('notes.txt'), findsOneWidget);
      expect(find.text('readme.md'), findsNothing);
    });

    testWidgets('the path bar leads back out', (tester) async {
      archives.listing = buildListing();
      await pumpBrowser(tester);

      await tester.tap(find.text('january'));
      await tester.pumpAndSettle();

      // The archive's own name is the root crumb.
      await tester.tap(
        find.descendant(
          of: find.byType(InkWell),
          matching: find.text('Invoices 2026.zip'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('readme.md'), findsOneWidget);
    });

    testWidgets('Back steps out of a folder before leaving the archive', (
      tester,
    ) async {
      archives.listing = buildListing();
      await pumpBrowser(tester);

      await tester.tap(find.text('january'));
      await tester.pumpAndSettle();
      expect(find.text('bill.pdf'), findsOneWidget);

      // The system back gesture, which is what a phone user actually presses.
      await pressSystemBack(tester);
      await tester.pumpAndSettle();

      // Back in the root of the archive, not out of it.
      expect(find.text('readme.md'), findsOneWidget);
      expect(find.text('bill.pdf'), findsNothing);
    });
  });

  group('opening an entry', () {
    testWidgets('a PDF opens the reader and imports nothing', (tester) async {
      archives.listing = buildListing();
      await pumpBrowser(tester);

      await tester.tap(find.text('january'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('bill.pdf'));
      await tester.pumpAndSettle();

      expect(find.text('the reader'), findsOneWidget);
      // The whole point: looking at it did not keep it.
      expect(documents.store, isEmpty);
      expect(archives.extracted, <String>['january/bill.pdf']);
    });

    testWidgets('an unsupported file is offered to another app', (
      tester,
    ) async {
      archives.listing = buildListing();
      await pumpBrowser(tester);

      await tester.tap(find.text('receipts.zip'));
      await tester.pumpAndSettle();

      // A nested archive is never opened in place.
      expect(find.text('the reader'), findsNothing);
      expect(opener.opened, hasLength(1));
      expect(documents.store, isEmpty);
    });

    testWidgets('a failed extraction says so rather than opening nothing', (
      tester,
    ) async {
      archives.listing = buildListing();
      archives.extractFailure = const ImportFailure('That file is damaged.');

      await pumpBrowser(tester);
      await tester.tap(find.text('readme.md'));
      await tester.pumpAndSettle();

      expect(find.text('the reader'), findsNothing);
      expect(find.text('That file is damaged.'), findsOneWidget);
    });
  });

  group('importing a selection', () {
    testWidgets('nothing is offered until something is ticked', (tester) async {
      archives.listing = buildListing();
      await pumpBrowser(tester);

      expect(find.textContaining('Import '), findsNothing);
    });

    testWidgets('a ticked file is imported and reported', (tester) async {
      archives.listing = buildListing();
      await pumpBrowser(tester);

      await tester.tap(find.byType(Checkbox).last);
      await tester.pumpAndSettle();

      expect(find.text('Import 1 file'), findsOneWidget);

      await tester.tap(find.text('Import 1 file'));
      await tester.pumpAndSettle();

      expect(documents.store, hasLength(1));
      expect(documents.store.values.single.title, 'readme');

      // A report the user can read at their own pace, not a snackbar that is
      // gone in five seconds.
      expect(find.text('One file imported'), findsOneWidget);
      expect(find.textContaining('In your library'), findsOneWidget);
      expect(find.text('readme.md'), findsOneWidget);
    });

    testWidgets('Select all takes the whole archive, not the open folder', (
      tester,
    ) async {
      archives.listing = buildListing();
      await pumpBrowser(tester);

      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();

      // Three importable files across two folders. The nested ZIP is not one.
      expect(find.text('Import 3 files'), findsOneWidget);

      await tester.tap(find.text('Import 3 files'));
      await tester.pumpAndSettle();

      expect(documents.store, hasLength(3));
      expect(find.text('All 3 files imported'), findsOneWidget);
    });

    testWidgets('a folder tick selects everything inside it', (tester) async {
      archives.listing = buildListing();
      await pumpBrowser(tester);

      // The first checkbox belongs to the "january" folder row.
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();

      expect(find.text('Import 2 files'), findsOneWidget);
    });

    testWidgets('every selected file appears in the report, with a reason', (
      tester,
    ) async {
      // The reported bug: seventeen selected, four arrived, and nothing said
      // what happened to the other thirteen.
      archives.listing = buildListing();
      archives.failExtractFor = 'january/bill.pdf';

      await pumpBrowser(tester);
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import 3 files'));
      await tester.pumpAndSettle();

      expect(documents.store, hasLength(2));

      // The headline counts, rather than leaving the user to.
      expect(find.text('2 of 3 files imported'), findsOneWidget);
      expect(find.textContaining('Not imported'), findsOneWidget);

      // The file that failed is named, with the reason beside it.
      expect(find.text('bill.pdf'), findsOneWidget);
      expect(find.textContaining('damaged'), findsWidgets);
      expect(find.text('Failed'), findsOneWidget);
    });

    testWidgets('Done returns to the archive, which is still open', (
      tester,
    ) async {
      archives.listing = buildListing();
      await pumpBrowser(tester);

      await tester.tap(find.byType(Checkbox).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import 1 file'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.text('readme.md'), findsOneWidget);
      expect(find.text('january'), findsOneWidget);
    });
  });

  group('stopping an import', () {
    /// An extraction that never finishes, which is what a 50 MB archive of
    /// multi-page PDFs amounts to from the user's side of the screen.
    testWidgets('Stop leaves the busy screen at once, without waiting', (
      tester,
    ) async {
      archives.listing = buildListing();
      archives.hang = true;

      await pumpBrowser(tester);
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import 3 files'));
      await tester.pump();

      expect(find.text('Stop'), findsOneWidget);

      await tester.tap(find.text('Stop'));
      await tester.pump();

      // In the very next frame. The extraction is still hanging — nothing was
      // awaited — and that is the whole point: the user is not made to wait
      // for work they just called off.
      expect(find.text('Stop'), findsNothing);
      expect(find.text('Import stopped'), findsOneWidget);
    });

    testWidgets('the report after Stop accounts for all of them', (
      tester,
    ) async {
      archives.listing = buildListing();
      archives.hang = true;

      await pumpBrowser(tester);
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import 3 files'));
      await tester.pump();
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      // Three selected, three rows, none of them lost.
      expect(find.text('Stopped'), findsNWidgets(3));
      expect(find.textContaining('Not imported'), findsOneWidget);
    });

    testWidgets('Back during an import stops it rather than doing nothing', (
      tester,
    ) async {
      // The trap: Back was swallowed while importing, so a hung run left
      // force-closing from Recents as the only way out.
      archives.listing = buildListing();
      archives.hang = true;

      await pumpBrowser(tester);
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import 3 files'));
      await tester.pump();

      await pressSystemBack(tester);
      await tester.pumpAndSettle();

      expect(find.text('Import stopped'), findsOneWidget);
    });

    testWidgets('Back from the report returns to the archive', (tester) async {
      archives.listing = buildListing();
      archives.hang = true;

      await pumpBrowser(tester);
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import 3 files'));
      await tester.pump();
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();

      await pressSystemBack(tester);
      await tester.pumpAndSettle();

      expect(find.text('readme.md'), findsOneWidget);
    });

    testWidgets('a stopped run cannot report over the one after it', (
      tester,
    ) async {
      // The abandoned run eventually finishes. Its result must not overwrite
      // the screen the user is looking at by then.
      archives.listing = buildListing();
      archives.hang = true;

      await pumpBrowser(tester);
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Import 3 files'));
      await tester.pump();
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back to the archive'));
      await tester.pumpAndSettle();

      // Let the abandoned extraction complete.
      archives.release();
      await tester.pumpAndSettle();

      // Still the browser: the ghost run did not put a report back on screen.
      expect(find.text('readme.md'), findsOneWidget);
      expect(find.textContaining('imported'), findsNothing);
    });
  });
}

/// The Android back gesture, as the engine delivers it.
///
/// There is no `tester.pressBack()`. Back arrives as a platform message on the
/// navigation channel, and sending that is the only way to exercise a
/// `PopScope` — which is precisely what decides whether Back leaves a folder or
/// leaves the archive.
Future<void> pressSystemBack(WidgetTester tester) =>
    tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
      (_) {},
    );

/// An archive that is whatever the test says it is.
///
/// `extract` writes a real file, because everything downstream of it — the
/// importer, the reader — takes a path and opens it. A fake that returned a
/// path to nothing would pass this test and fail on a phone.
class _FakeArchiveRepository implements ArchiveRepository {
  _FakeArchiveRepository(this._workspace);

  final Directory _workspace;

  ArchiveListing? listing;
  Failure? failure;
  Failure? extractFailure;

  /// Fails for one named entry only, which is how a partial import is tested.
  String? failExtractFor;

  final List<String> extracted = <String>[];

  @override
  FutureResult<ArchiveListing> open(String archivePath) async {
    final problem = failure;
    if (problem != null) return Failed(problem);
    return Success(listing!);
  }

  /// When true, extraction never completes on its own — the stand-in for a
  /// multi-page PDF rasterising inside a platform call that Dart cannot
  /// interrupt. [release] lets it finish.
  bool hang = false;
  final List<Completer<void>> _held = <Completer<void>>[];

  void release() {
    for (final completer in _held) {
      if (!completer.isCompleted) completer.complete();
    }
    _held.clear();
  }

  @override
  FutureResult<String> extract({
    required String archivePath,
    required ArchiveEntry entry,
  }) async {
    if (hang) {
      final gate = Completer<void>();
      _held.add(gate);
      await gate.future;
    }

    final problem = extractFailure;
    if (problem != null) return Failed(problem);
    if (entry.path == failExtractFor) {
      return const Failed(ImportFailure('That entry is damaged.'));
    }

    extracted.add(entry.path);

    final file = File(p.join(_workspace.path, entry.name));
    file.writeAsStringSync('contents of ${entry.name}');
    return Success(file.path);
  }
}

/// Everything is text, so an import needs no renderer and no image codec.
///
/// The question these tests ask is whether the browser routes files into the
/// importer at all — what the importer then does with a PDF is
/// `file_import_test`'s business.
class _FakeFileImporter implements FileImportRepository {
  const _FakeFileImporter();

  @override
  FutureResult<ImportedFile> pickFile() async =>
      const Failed(ImportFailure('not used'));

  @override
  FutureResult<ImportedFile> readFile(
    String path, {
    bool Function()? isCancelled,
  }) async => Success(
    ImportedFile(
      name: p.basenameWithoutExtension(path),
      kind: ImportedFileKind.text,
      text: 'contents',
    ),
  );
}

/// Records what was handed out, and claims the chooser opened.
class _RecordingOpener implements ExternalOpener {
  final List<String> opened = <String>[];

  @override
  Future<bool> open({required String path, String? mimeType}) async {
    opened.add(path);
    return true;
  }
}
