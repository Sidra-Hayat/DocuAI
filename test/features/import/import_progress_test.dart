import 'dart:async';
import 'dart:io';

import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/core/router/app_routes.dart';
import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/features/documents/presentation/providers/document_providers.dart';
import 'package:docuai/src/features/documents/presentation/screens/documents_screen.dart';
import 'package:docuai/src/features/import/data/datasources/pdf_page_rasterizer.dart';
import 'package:docuai/src/features/import/domain/repositories/file_import_repository.dart';
import 'package:docuai/src/features/import/domain/repositories/image_import_repository.dart';
import 'package:docuai/src/features/import/presentation/providers/import_providers.dart';
import 'package:docuai/src/features/search/presentation/providers/search_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/fakes.dart';

/// What the user sees while an import is running.
///
/// Reported from a phone: tapping Import and then nothing. The photos were
/// being normalised and copied — hundreds of milliseconds each, on a background
/// isolate — with the library still on screen and no sign that anything had
/// begun. The complaint was not that it was slow; it was that it was silent.
void main() {
  late Directory tempDir;
  late FakeDocumentRepository documents;
  late _ControllableImageImport importer;
  late _ControllableFileImport files;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_import_progress');
  });

  tearDownAll(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  setUp(() {
    documents = FakeDocumentRepository();
    importer = _ControllableImageImport();
    files = _ControllableFileImport();
  });

  tearDown(() => documents.dispose());

  /// The library on a real router.
  ///
  /// A real one because the import resolves `GoRouter` before awaiting — the
  /// lifecycle-safe order — and because success ends in a push to the document
  /// it created, which a bare `MaterialApp` cannot host.
  Future<void> pumpLibrary(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) => const DocumentsScreen(),
          routes: <RouteBase>[
            GoRoute(
              path: 'document/:id',
              name: AppRoutes.documentDetailName,
              builder: (context, state) =>
                  const Scaffold(body: Text('the imported document')),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(documents),
          searchRepositoryProvider.overrideWithValue(FakeSearchRepository()),
          imageImportRepositoryProvider.overrideWithValue(importer),
          fileImportRepositoryProvider.overrideWithValue(files),
          storagePathsProvider.overrideWithValue(StoragePaths(tempDir)),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Taps the empty library's Import button and chooses a source from the sheet
  /// it opens, then lets the progress dialog appear.
  Future<void> tapImport(WidgetTester tester, {String source = 'Photo'}) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Import'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, source));
    await tester.pump();
  }

  /// Runs frames until the import has finished and the dialog is gone.
  ///
  /// Deliberately not `pumpAndSettle`: an indeterminate
  /// `CircularProgressIndicator` schedules a frame forever, so settling is
  /// impossible for as long as the dialog is up — including in the case these
  /// tests exist to catch, where it never goes away at all.
  Future<void> pumpUntilDone(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Finder progress() => find.byType(CircularProgressIndicator);

  testWidgets('importing says so as soon as it begins', (tester) async {
    await pumpLibrary(tester);
    await tapImport(tester);

    expect(progress(), findsOneWidget);
    expect(find.text('Importing your photos…'), findsOneWidget);
  });

  testWidgets('the progress dialog goes away once the import succeeds', (
    tester,
  ) async {
    await pumpLibrary(tester);
    await tapImport(tester);

    expect(progress(), findsOneWidget);

    importer.complete(const Success(ImportOutcome(imagePaths: ['/tmp/a.jpg'])));
    await pumpUntilDone(tester);

    expect(progress(), findsNothing);
    expect(find.text('Importing your photos…'), findsNothing);

    // And the import still does what it always did: a document is created from
    // the chosen photos, and the app opens it.
    expect(documents.lastSourceImagePaths, <String>['/tmp/a.jpg']);
    expect(find.text('the imported document'), findsOneWidget);
  });

  testWidgets('the progress dialog goes away when the import fails', (
    tester,
  ) async {
    documents.saveFailure = const StorageFailure(
      'The pages could not be saved.',
    );

    await pumpLibrary(tester);
    await tapImport(tester);

    importer.complete(const Success(ImportOutcome(imagePaths: ['/tmp/a.jpg'])));
    await pumpUntilDone(tester);

    expect(progress(), findsNothing);
    // A failure the user can read, rather than a screen that simply returns.
    expect(find.text('The pages could not be saved.'), findsOneWidget);
  });

  testWidgets('backing out of the picker clears it too', (tester) async {
    await pumpLibrary(tester);
    await tapImport(tester);

    // Cancelling is not an error and says nothing, but it must not leave the
    // dialog up over a library the user can no longer reach.
    importer.complete(const Success(ImportOutcome(imagePaths: <String>[])));
    await pumpUntilDone(tester);

    expect(progress(), findsNothing);
    expect(find.text('No documents yet'), findsOneWidget);
  });

  testWidgets('a second tap cannot start a second import', (tester) async {
    await pumpLibrary(tester);
    await tapImport(tester);

    // The button is still there behind the dialog; the modal barrier is what
    // stops the tap reaching it. Without one, an impatient second tap opens the
    // picker again and imports the same photos into a second document.
    await tester.tap(
      find.widgetWithText(FilledButton, 'Import'),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(importer.calls, 1);

    importer.complete(const Success(ImportOutcome(imagePaths: ['/tmp/a.jpg'])));
    await pumpUntilDone(tester);

    expect(importer.calls, 1);
  });

  group('the empty library imports both kinds', () {
    testWidgets('Import asks whether that means a photo or a file', (
      tester,
    ) async {
      await pumpLibrary(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Import'));
      await tester.pumpAndSettle();

      // The file importer used to be reachable only from the New document
      // sheet, which this screen hides — so a first-run user with a PDF had
      // nowhere to go.
      expect(find.widgetWithText(ListTile, 'Photo'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'File'), findsOneWidget);
      expect(find.text('Choose a photo from your gallery'), findsOneWidget);
      expect(find.text('Import a PDF, DOCX or text file'), findsOneWidget);
    });

    testWidgets('choosing Photo still opens the photo import', (tester) async {
      await pumpLibrary(tester);
      await tapImport(tester);

      expect(importer.calls, 1);
      expect(find.text('Importing your photos…'), findsOneWidget);
    });

    testWidgets('choosing File still opens the file import', (tester) async {
      await pumpLibrary(tester);
      await tapImport(tester, source: 'File');

      // A different importer, and its own message — the photo picker is not
      // touched by this route.
      expect(importer.calls, 0);
      expect(files.calls, 1);
      expect(find.text('Importing your document…'), findsOneWidget);
    });

    testWidgets('a PDF becomes a document', (tester) async {
      await pumpLibrary(tester);
      await tapImport(tester, source: 'File');

      files.complete(
        const Success(
          ImportedFile(
            name: 'Statement',
            kind: ImportedFileKind.pages,
            imagePaths: <String>['/tmp/p0.jpg', '/tmp/p1.jpg'],
          ),
        ),
      );
      await pumpUntilDone(tester);

      expect(documents.lastCreatedTitle, 'Statement');
      expect(documents.lastSourceImagePaths, hasLength(2));
      expect(find.text('the imported document'), findsOneWidget);
      expect(progress(), findsNothing);
    });

    testWidgets('a PDF past the page limit says so rather than truncating '
        'quietly', (tester) async {
      await pumpLibrary(tester);
      await tapImport(tester, source: 'File');

      files.complete(
        Success(
          ImportedFile(
            name: 'Long statement',
            kind: ImportedFileKind.pages,
            imagePaths: List<String>.generate(
              PdfPageRasterizer.maxPages,
              (i) => '/tmp/p$i.jpg',
            ),
            truncatedAt: PdfPageRasterizer.maxPages,
          ),
        ),
      );
      await pumpUntilDone(tester);

      // The document opens either way — sixty pages is worth keeping — but the
      // one thing the user cannot see for themselves is said out loud.
      expect(
        find.textContaining('The first ${PdfPageRasterizer.maxPages} pages'),
        findsOneWidget,
      );
      expect(find.text('the imported document'), findsOneWidget);
    });

    testWidgets('a PDF that fits says nothing about limits', (tester) async {
      await pumpLibrary(tester);
      await tapImport(tester, source: 'File');

      files.complete(
        const Success(
          ImportedFile(
            name: 'Short statement',
            kind: ImportedFileKind.pages,
            imagePaths: <String>['/tmp/p0.jpg'],
          ),
        ),
      );
      await pumpUntilDone(tester);

      expect(find.textContaining('pages were brought in'), findsNothing);
    });
  });
}

/// An import that does not finish until the test says so.
///
/// Stands in for the picker plus the normalisation behind it, which is the
/// whole window the progress dialog exists to cover.
class _ControllableImageImport implements ImageImportRepository {
  Completer<Result<ImportOutcome>>? _completer;

  int calls = 0;

  void complete(Result<ImportOutcome> outcome) => _completer!.complete(outcome);

  @override
  FutureResult<ImportOutcome> pickImages({int limit = 30}) {
    calls++;

    // Created on first use rather than in `setUp`, and that is not a style
    // choice. A `Future` captures the zone it was constructed in, `setUp` runs
    // outside `testWidgets`' fake-async zone, and a completer built there
    // resolves its listeners in the real zone — where `tester.pump()` cannot
    // reach them, so the import never moves and the dialog never closes.
    // Built here it belongs to the test. Same family of trap as the file-I/O
    // note in `test/app_smoke_test.dart`.
    return (_completer ??= Completer<Result<ImportOutcome>>()).future;
  }
}

/// The file importer, held open the same way and for the same reasons.
class _ControllableFileImport implements FileImportRepository {
  Completer<Result<ImportedFile>>? _completer;

  int calls = 0;

  void complete(Result<ImportedFile> outcome) => _completer!.complete(outcome);

  @override
  FutureResult<ImportedFile> pickFile() {
    calls++;
    // Built here, not in `setUp` — see the note on the photo importer above.
    return (_completer ??= Completer<Result<ImportedFile>>()).future;
  }
}
