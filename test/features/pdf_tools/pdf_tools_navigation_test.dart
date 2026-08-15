import 'dart:async';
import 'dart:io';

import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/core/router/app_router.dart';
import 'package:docuai/src/core/router/app_routes.dart';
import 'package:docuai/src/core/storage/storage_paths.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/documents/presentation/providers/document_providers.dart';
import 'package:docuai/src/features/pdf_tools/domain/entities/pdf_tool_models.dart';
import 'package:docuai/src/features/pdf_tools/domain/repositories/pdf_tools_repository.dart';
import 'package:docuai/src/features/pdf_tools/presentation/providers/pdf_tools_providers.dart';
import 'package:docuai/src/features/pdf_tools/presentation/screens/compress_pdf_screen.dart';
import 'package:docuai/src/features/pdf_tools/presentation/screens/merge_pdfs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/fakes.dart';

/// The PDF tools driven through the **real router**.
///
/// This file exists for one defect found on a physical phone: finishing a merge
/// threw
///
/// ```
/// 'package:flutter/src/widgets/navigator.dart':
/// Failed assertion: line 4049 pos 18: '!keyReservation.contains(key)'
/// ```
///
/// while the merged document was created successfully and appeared in Recents.
///
/// The assertion is `Navigator._debugCheckDuplicatedPageKeys` — two pages in
/// one `Navigator.pages` list carrying the same key. The merge screen is pushed
/// on the **root** navigator; the document detail route lives inside the
/// documents branch of the `StatefulShellRoute`. Replacing the former with the
/// latter left GoRouter building a page list holding `/documents` twice: once
/// as the shell branch already underneath, once as the parent of the detail
/// page going on top.
///
/// **A fake router would not have caught this**, because the bug is entirely in
/// how GoRouter composes the real route tree. So these tests build the app's
/// own `appRouterProvider` and reach the tools the way the app does — from the
/// library, by pushing — which is the only arrangement in which the stack has a
/// `/documents` page for the new one to collide with.
void main() {
  late Directory tempDir;
  late FakeDocumentRepository documents;
  late _FakePdfTools tools;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('docuai_pdf_nav');
    documents = FakeDocumentRepository();
    tools = _FakePdfTools();

    documents.seed(
      buildDocument(
        id: 'seed',
        title: 'A scan',
        pages: <DocumentPage>[
          buildPage(id: 'seed-p0', index: 0, ocrStatus: OcrStatus.completed),
        ],
      ),
    );
  });

  tearDown(() async {
    documents.dispose();
    if (tempDir.existsSync()) {
      try {
        await tempDir.delete(recursive: true);
      } on FileSystemException {
        // Windows may still hold a handle; the OS reclaims it.
      }
    }
  });

  /// Boots the app on its real router, with only the edges faked.
  Future<GoRouter> pumpApp(WidgetTester tester) async {
    late GoRouter router;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storagePathsProvider.overrideWithValue(StoragePaths(tempDir)),
          documentRepositoryProvider.overrideWithValue(documents),
          pdfToolsRepositoryProvider.overrideWithValue(tools),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            router = ref.watch(appRouterProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    return router;
  }

  /// Reaches the merge screen the way the app does: from the library, pushed.
  ///
  /// Deliberately not `go('/pdf-tools/merge')`, which would build a stack with
  /// no `/documents` page in it and quietly make the very collision under test
  /// impossible.
  Future<GoRouter> openMergeScreen(WidgetTester tester) async {
    final router = await pumpApp(tester);

    unawaited(router.pushNamed(AppRoutes.pdfToolsName));
    await tester.pumpAndSettle();
    unawaited(router.pushNamed(AppRoutes.mergePdfsName));
    await tester.pumpAndSettle();

    expect(find.byType(MergePdfsScreen), findsOneWidget);
    return router;
  }

  Future<void> addTwoPdfs(WidgetTester tester) async {
    await tester.tap(find.text('Add a PDF'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
  }

  group('finishing a merge', () {
    testWidgets('does not trip the duplicated-page-key assertion', (
      tester,
    ) async {
      await openMergeScreen(tester);
      await addTwoPdfs(tester);

      await tester.tap(find.textContaining('Merge 2 PDFs'));
      await tester.pumpAndSettle();

      expect(
        tester.takeException(),
        isNull,
        reason: 'this is the crash reported from the phone',
      );
    });

    testWidgets('shows the result instead of navigating away', (tester) async {
      await openMergeScreen(tester);
      await addTwoPdfs(tester);

      await tester.tap(find.textContaining('Merge 2 PDFs'));
      await tester.pumpAndSettle();

      // Still on the merge screen. The result is a state of it, which is what
      // removes the cross-navigator replacement that caused the assertion.
      expect(find.byType(MergePdfsScreen), findsOneWidget);
      expect(find.text('Merged into one document'), findsOneWidget);
      expect(find.text('View'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
    });

    testWidgets('never reports failure for a merge that succeeded', (
      tester,
    ) async {
      await openMergeScreen(tester);
      await addTwoPdfs(tester);

      await tester.tap(find.textContaining('Merge 2 PDFs'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('could not'), findsNothing);
    });

    testWidgets('reaching the document from the result stays clean', (
      tester,
    ) async {
      final router = await openMergeScreen(tester);
      await addTwoPdfs(tester);

      await tester.tap(find.textContaining('Merge 2 PDFs'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(
        router.state.matchedLocation,
        AppRoutes.documentDetailPath('merged-1'),
      );
    });

    testWidgets('Done returns the screen to its list', (tester) async {
      await openMergeScreen(tester);
      await addTwoPdfs(tester);

      await tester.tap(find.textContaining('Merge 2 PDFs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Back to an empty list, ready for another merge, still on the screen the
      // user chose to be on.
      expect(find.text('Add the PDFs to join'), findsOneWidget);
    });

    testWidgets('a genuine failure is reported', (tester) async {
      tools.mergeFails = true;

      await openMergeScreen(tester);
      await addTwoPdfs(tester);

      await tester.tap(find.textContaining('Merge 2 PDFs'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Merged into one document'), findsNothing);
    });
  });

  group('finishing a compression', () {
    Future<GoRouter> openCompressScreen(WidgetTester tester) async {
      final router = await pumpApp(tester);

      unawaited(router.pushNamed(AppRoutes.pdfToolsName));
      await tester.pumpAndSettle();
      unawaited(router.pushNamed(AppRoutes.compressPdfName));
      await tester.pumpAndSettle();

      expect(find.byType(CompressPdfScreen), findsOneWidget);
      return router;
    }

    Future<void> compressAFile(WidgetTester tester) async {
      await tester.tap(find.text('Choose a PDF or document'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('A PDF on this phone'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Compress'));
      await tester.pumpAndSettle();
    }

    testWidgets('an external PDF can be chosen and compressed', (tester) async {
      await openCompressScreen(tester);
      await compressAFile(tester);

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Original'), findsOneWidget);
      expect(find.text('View'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
    });

    testWidgets('the picker is described as files, not a photo gallery', (
      tester,
    ) async {
      await openCompressScreen(tester);

      await tester.tap(find.text('Choose a PDF or document'));
      await tester.pumpAndSettle();

      // The sheet has to say which of the two places it opens. A label reading
      // "choose a file" over a phone showing a document browser is the
      // difference between finding your PDF and hunting for it in Photos.
      expect(find.text('A PDF on this phone'), findsOneWidget);
      expect(find.text('A document in DocuAI'), findsOneWidget);
      expect(
        find.textContaining('Downloads'),
        findsOneWidget,
        reason: 'the user is told this opens their files',
      );
    });

    testWidgets('a result that saved nothing says so and offers no copy', (
      tester,
    ) async {
      // The case reported from a phone: 742 KB in, 765 KB out, and the larger
      // copy saved into the library anyway.
      tools.compressedBytes = 9000;
      tools.originalBytes = 4000;

      await openCompressScreen(tester);
      await compressAFile(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.text('This document is already optimized'),
        findsOneWidget,
      );
      expect(
        find.textContaining('would not be smaller'),
        findsOneWidget,
      );

      // Nothing was written, so there is nothing to view, send or throw away.
      expect(find.text('View'), findsNothing);
      expect(find.text('Share'), findsNothing);
      expect(find.text('Delete this copy'), findsNothing);
      expect(find.text('Done'), findsOneWidget);
    });

    testWidgets('an equal-size result is treated the same way', (tester) async {
      // The boundary: "smaller" means strictly smaller.
      tools.originalBytes = 5000;
      tools.compressedBytes = 5000;

      await openCompressScreen(tester);
      await compressAFile(tester);

      expect(
        find.text('This document is already optimized'),
        findsOneWidget,
      );
      expect(find.text('View'), findsNothing);
    });

    testWidgets('a smaller result is still saved and offered', (tester) async {
      tools.originalBytes = 8000;
      tools.compressedBytes = 2000;

      await openCompressScreen(tester);
      await compressAFile(tester);

      expect(find.textContaining('Saved 75%'), findsOneWidget);
      expect(find.text('View'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Delete this copy'), findsOneWidget);
    });

    testWidgets('both sizes are shown, as sizes', (tester) async {
      tools.originalBytes = 8000;
      tools.compressedBytes = 2000;

      await openCompressScreen(tester);
      await compressAFile(tester);

      // The figures themselves, not just the words: "Original" alone would
      // pass against a label with nothing beside it.
      expect(find.textContaining('Original 7.8 KB'), findsOneWidget);
      expect(find.textContaining('Compressed 2.0 KB'), findsOneWidget);
    });
  });

  group('PDF tools information architecture', () {
    testWidgets('does not offer a second way to share a document', (
      tester,
    ) async {
      final router = await pumpApp(tester);
      unawaited(router.pushNamed(AppRoutes.pdfToolsName));
      await tester.pumpAndSettle();

      // Sharing a library document belongs to the document screen, which
      // already knows which document is meant. A tile here made the user pick
      // one twice.
      expect(find.text('Share as PDF'), findsNothing);
      expect(find.text('Merge PDFs'), findsOneWidget);
      expect(find.text('Compress a PDF'), findsOneWidget);
      expect(
        find.textContaining('Open the document you want'),
        findsOneWidget,
        reason: 'a removed action should say where it went',
      );
    });
  });
}

/// The tools, without a file picker or a PDF renderer.
class _FakePdfTools implements PdfToolsRepository {
  int _picked = 0;

  bool mergeFails = false;
  int originalBytes = 8000;
  int compressedBytes = 2000;

  @override
  FutureResult<PdfSource> pickPdf() async {
    _picked++;
    return Success(
      PdfSource(
        id: 'picked-$_picked',
        path: '/tmp/picked-$_picked.pdf',
        name: 'Statement $_picked',
        sizeBytes: 1024 * _picked,
      ),
    );
  }

  @override
  FutureResult<MergeOutcome> merge({
    required List<PdfSource> sources,
    required String title,
    ToolProgressCallback? onProgress,
  }) async {
    if (mergeFails) {
      return Failed(
        const ImportFailure('That PDF could not be opened.'),
      );
    }

    return Success(
      MergeOutcome(
        document: buildDocument(id: 'merged-1', title: 'Merged'),
        pageCount: sources.length * 2,
        sourceCount: sources.length,
      ),
    );
  }

  @override
  FutureResult<CompressionOutcome> compress({
    required Document document,
    required CompressionLevel level,
    ToolProgressCallback? onProgress,
  }) async => _outcome(level, document.title);

  @override
  FutureResult<CompressionOutcome> compressPdfFile({
    required PdfSource source,
    required CompressionLevel level,
    ToolProgressCallback? onProgress,
  }) async => _outcome(level, source.name);

  Result<CompressionOutcome> _outcome(CompressionLevel level, String label) =>
      Success(
        CompressionOutcome(
          originalBytes: originalBytes,
          compressedBytes: compressedBytes,
          level: level,
          // Null exactly when the real repository would have written nothing,
          // so a screen that mishandled the no-saving case could not pass here.
          document: compressedBytes < originalBytes
              ? buildDocument(id: 'compressed-1', title: '$label (small)')
              : null,
          sourceLabel: label,
        ),
      );
}

