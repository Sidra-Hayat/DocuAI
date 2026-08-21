import 'dart:async';

import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/core/error/result.dart';
import 'package:docuai/src/features/archives/domain/entities/zip_build.dart';
import 'package:docuai/src/features/archives/domain/repositories/zip_builder_repository.dart';
import 'package:docuai/src/features/archives/presentation/providers/zip_create_providers.dart';
import 'package:docuai/src/features/archives/presentation/screens/create_zip_screen.dart';
import 'package:docuai/src/features/documents/presentation/providers/document_providers.dart';
import 'package:docuai/src/features/pdf_tools/domain/entities/pdf_tool_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

/// Creating a ZIP, as a user meets it.
///
/// The behaviour worth pinning here is not that a button exists. It is that
/// **Stop works the instant it is pressed** — the screen must not sit waiting
/// on an encoder it has already given up on, which is the exact failure the
/// archive browser's import had and had to be rewritten for. The build in these
/// tests is deliberately held open so the test can press Stop while it is
/// genuinely still running.
void main() {
  late FakeDocumentRepository documents;
  late _FakeZipBuilder builder;

  setUp(() {
    documents = FakeDocumentRepository();
    builder = _FakeZipBuilder();
  });

  tearDown(() => documents.dispose());

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        // Untyped, because Riverpod 3 does not export its `Override` type.
        overrides: [
          zipBuilderRepositoryProvider.overrideWithValue(builder),
          documentRepositoryProvider.overrideWithValue(documents),
        ],
        child: const MaterialApp(home: CreateZipScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Puts one library document in the list, through the sheet the user uses.
  Future<void> addOneDocument(WidgetTester tester) async {
    documents.seed(buildDocument(id: 'doc-a', title: 'Rent receipt'));

    await tester.tap(find.text('Add documents'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rent receipt'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add 1 document'));
    await tester.pumpAndSettle();
  }

  group('before anything is chosen', () {
    testWidgets('offers both places files can come from', (tester) async {
      await pumpScreen(tester);

      expect(find.text('Choose what to put in the ZIP'), findsOneWidget);
      // Neither is the secondary one in spirit — archiving scans together with
      // downloads is the case this screen exists for.
      expect(find.text('Add documents'), findsOneWidget);
      expect(find.text('Add files from phone'), findsOneWidget);
    });

    testWidgets('offers nothing to create yet', (tester) async {
      await pumpScreen(tester);

      expect(find.byType(FloatingActionButton), findsNothing);
    });
  });

  group('choosing', () {
    testWidgets('a document from the library appears in the list', (
      tester,
    ) async {
      await pumpScreen(tester);
      await addOneDocument(tester);

      expect(find.text('Rent receipt'), findsOneWidget);
      expect(find.textContaining('Document ·'), findsOneWidget);
      expect(find.textContaining('Create ZIP of 1 item'), findsOneWidget);
    });

    testWidgets('a document already added cannot be added twice', (
      tester,
    ) async {
      await pumpScreen(tester);
      await addOneDocument(tester);

      await tester.tap(find.text('Documents'));
      await tester.pumpAndSettle();

      // Shown rather than hidden: somebody looking for a document they cannot
      // find would otherwise assume the app had lost it.
      expect(find.text('Already added'), findsOneWidget);
    });

    testWidgets('files picked from the phone appear alongside documents', (
      tester,
    ) async {
      builder.picked = ZipSourceSelection(
        sources: <ZipSource>[
          ZipSource.file(path: '/cache/a.pdf', name: 'a.pdf', sizeBytes: 2048),
        ],
      );

      await pumpScreen(tester);
      await addOneDocument(tester);

      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();

      expect(find.text('a.pdf'), findsOneWidget);
      expect(find.textContaining('File ·'), findsOneWidget);
      expect(find.textContaining('Create ZIP of 2 items'), findsOneWidget);
    });

    testWidgets('says when a picked file could not be read', (tester) async {
      // Counted rather than dropped. Ticking three files and seeing two rows
      // appear reads as the app being unreliable.
      builder.picked = const ZipSourceSelection(
        sources: <ZipSource>[],
        rejected: 2,
      );

      await pumpScreen(tester);
      await tester.tap(find.text('Add files from phone'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('2 files could not be read'),
        findsOneWidget,
      );
    });

    testWidgets('a row can be taken back out', (tester) async {
      await pumpScreen(tester);
      await addOneDocument(tester);

      await tester.tap(find.byTooltip('Remove "Rent receipt"'));
      await tester.pumpAndSettle();

      expect(find.text('Choose what to put in the ZIP'), findsOneWidget);
    });
  });

  group('creating', () {
    testWidgets('shows the archive and offers to share it', (tester) async {
      await pumpScreen(tester);
      await addOneDocument(tester);

      builder.completeWith(
        const Success(
          ZipBuildOutcome(
            path: '/cache/docuai_zip/run/Bundle.zip',
            fileName: 'Bundle.zip',
            entryCount: 1,
            sizeBytes: 1024,
            sourceBytes: 4096,
          ),
        ),
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('Archive ready'), findsOneWidget);
      expect(find.textContaining('Bundle.zip'), findsOneWidget);
      expect(find.text('Share archive'), findsOneWidget);
    });

    testWidgets('accounts for anything left out', (tester) async {
      await pumpScreen(tester);
      await addOneDocument(tester);

      builder.completeWith(
        const Success(
          ZipBuildOutcome(
            path: '/cache/docuai_zip/run/Bundle.zip',
            fileName: 'Bundle.zip',
            entryCount: 1,
            sizeBytes: 1024,
            sourceBytes: 4096,
            skipped: <ZipSkippedSource>[
              ZipSkippedSource(
                name: 'holiday.jpg',
                reason: 'That file is no longer on this device.',
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(find.text('One thing was left out'), findsOneWidget);
      expect(find.text('holiday.jpg'), findsOneWidget);
    });

    testWidgets('sharing hands the built archive to the repository', (
      tester,
    ) async {
      await pumpScreen(tester);
      await addOneDocument(tester);

      builder.completeWith(
        const Success(
          ZipBuildOutcome(
            path: '/cache/docuai_zip/run/Bundle.zip',
            fileName: 'Bundle.zip',
            entryCount: 1,
            sizeBytes: 1024,
            sourceBytes: 4096,
          ),
        ),
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Share archive'));
      await tester.pumpAndSettle();

      expect(builder.shared, <String>['/cache/docuai_zip/run/Bundle.zip']);
    });

    testWidgets('Share recovers when the sheet never reports back', (
      tester,
    ) async {
      // Found on a device, and it left the user stuck. `SharePlus.share`
      // returns a future that resolves when the chooser reports its result, and
      // choosing DocuAI out of DocuAI's own share sheet means the chooser hands
      // the file back to this app instead — the future never resolves. The
      // button sat disabled on "Opening…" and the finished archive could not be
      // sent at all.
      await pumpScreen(tester);
      await addOneDocument(tester);

      builder.completeWith(
        const Success(
          ZipBuildOutcome(
            path: '/cache/docuai_zip/run/Bundle.zip',
            fileName: 'Bundle.zip',
            entryCount: 1,
            sizeBytes: 1024,
            sourceBytes: 4096,
          ),
        ),
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      builder.holdShare = true;
      await tester.tap(find.text('Share archive'));
      await tester.pump();

      expect(find.text('Opening…'), findsOneWidget);

      // The app goes away for the chooser and comes back. Whatever the share
      // future is doing, this screen being in front of the user again means the
      // sheet is not.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.text('Opening…'), findsNothing);
      expect(find.text('Share archive'), findsOneWidget);

      // And it can genuinely be pressed again, rather than merely looking able.
      await tester.tap(find.text('Share archive'));
      await tester.pump();
      expect(builder.shared.length, 2);
    });

    testWidgets('a failure is reported without losing the selection', (
      tester,
    ) async {
      await pumpScreen(tester);
      await addOneDocument(tester);

      builder.completeWith(
        const Failed<ZipBuildOutcome>(
          ExportFailure('There is not enough free space on this phone.'),
        ),
      );

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      expect(
        find.text('There is not enough free space on this phone.'),
        findsOneWidget,
      );
      // Still there to try again with, rather than cleared out from under them.
      expect(find.text('Rent receipt'), findsOneWidget);
    });
  });

  group('stopping', () {
    testWidgets('Stop is offered while the archive is being built', (
      tester,
    ) async {
      await pumpScreen(tester);
      await addOneDocument(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();

      expect(find.text('Stop'), findsOneWidget);
      expect(find.text('Nothing is saved until it is finished.'), findsOneWidget);
    });

    testWidgets('Stop takes effect in the frame it is pressed', (tester) async {
      await pumpScreen(tester);
      await addOneDocument(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();

      // The build is still running and will never be allowed to finish. If the
      // screen waited for it — which is the bug the archive browser had — this
      // is where the test would hang on a progress bar with no way out.
      await tester.tap(find.text('Stop'));
      await tester.pump();

      expect(find.text('Stop'), findsNothing);
      expect(find.text('Rent receipt'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.text('Stopped. No archive was created.'), findsOneWidget);
    });

    testWidgets('the build is told to stop, not merely abandoned', (
      tester,
    ) async {
      // Letting go of the result is what makes Stop instant; asking the run to
      // stop is what keeps it from writing an archive nobody wants.
      await pumpScreen(tester);
      await addOneDocument(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.tap(find.text('Stop'));
      await tester.pump();

      expect(builder.wasCancelled, isTrue);
    });

    testWidgets('a result arriving after Stop is ignored', (tester) async {
      await pumpScreen(tester);
      await addOneDocument(tester);

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.tap(find.text('Stop'));
      await tester.pump();

      // The abandoned run finishes anyway, as a real one winding down would.
      builder.completeWith(
        const Success(
          ZipBuildOutcome(
            path: '/cache/docuai_zip/run/Late.zip',
            fileName: 'Late.zip',
            entryCount: 1,
            sizeBytes: 1,
            sourceBytes: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // It must not surface: the user stopped, and an archive appearing after
      // they said no would be the screen contradicting them.
      expect(find.text('Archive ready'), findsNothing);
      expect(find.text('Rent receipt'), findsOneWidget);
    });
  });
}

/// A builder whose run finishes when the test says so.
///
/// The screen's contract is about *timing* — what it does while a build is
/// still going — so the fake hands back a future the test controls rather than
/// one that has already completed.
class _FakeZipBuilder implements ZipBuilderRepository {
  Completer<Result<ZipBuildOutcome>>? _pending;

  ZipSourceSelection picked = const ZipSourceSelection.none();
  final List<String> shared = <String>[];

  /// Read through the `isCancelled` the screen supplied, so a test can tell
  /// "let go of the result" apart from "asked the run to stop".
  bool Function()? _isCancelled;

  bool get wasCancelled => _isCancelled?.call() ?? false;

  void completeWith(Result<ZipBuildOutcome> result) {
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.complete(result);
      _pending = null;
      return;
    }
    // Queued for a build that has not started yet, which is how the tests that
    // set an outcome before tapping Create are written.
    _queued = result;
  }

  Result<ZipBuildOutcome>? _queued;

  @override
  FutureResult<ZipBuildOutcome> build({
    required List<ZipSource> sources,
    required String archiveName,
    ToolProgressCallback? onProgress,
    bool Function()? isCancelled,
  }) {
    _isCancelled = isCancelled;

    final queued = _queued;
    if (queued != null) {
      _queued = null;
      return Future<Result<ZipBuildOutcome>>.value(queued);
    }

    final completer = Completer<Result<ZipBuildOutcome>>();
    _pending = completer;
    return completer.future;
  }

  @override
  FutureResult<ZipSourceSelection> pickFiles() async => Success(picked);

  /// When true, [share] returns a future that never completes — a chooser that
  /// never reports back, which is what a real one does when it hands the file
  /// to this same app.
  bool holdShare = false;

  @override
  FutureResult<void> share(String archivePath) {
    shared.add(archivePath);
    if (holdShare) return Completer<Result<void>>().future;
    return Future<Result<void>>.value(const Success<void>(null));
  }
}
