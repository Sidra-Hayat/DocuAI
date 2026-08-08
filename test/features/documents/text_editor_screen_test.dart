import 'package:docuai/src/core/error/failure.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/documents/presentation/providers/document_providers.dart';
import 'package:docuai/src/features/documents/presentation/screens/text_editor_screen.dart';
import 'package:docuai/src/features/search/presentation/providers/search_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

/// The editor screen.
///
/// Driven against the in-memory fakes rather than Hive: a Hive write inside a
/// `testWidgets` body hangs the run in `tearDownAll` — the test passes and the
/// suite never finishes. The repository contract is what this screen talks to,
/// and the fake honours it.
void main() {
  late FakeDocumentRepository documents;
  late FakeSearchRepository search;

  Document noteWith(String text) => buildDocument(
    id: 'note',
    title: 'Tenancy notes',
    source: DocumentSource.created,
    pages: <DocumentPage>[buildTextPage(id: 'page-0', index: 0, text: text)],
  );

  setUp(() {
    documents = FakeDocumentRepository();
    search = FakeSearchRepository();
  });

  tearDown(() => documents.dispose());

  Future<void> pumpEditor(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(documents),
          searchRepositoryProvider.overrideWithValue(search),
        ],
        child: const MaterialApp(
          home: TextEditorScreen(documentId: 'note', pageId: 'page-0'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('opens on the page as it was last written', (tester) async {
    documents.seed(noteWith('The deposit is 500.00 EUR.'));

    await pumpEditor(tester);

    expect(find.text('The deposit is 500.00 EUR.'), findsOneWidget);
    expect(find.text('Tenancy notes'), findsOneWidget);
  });

  testWidgets('the save action is inert until something is typed', (
    tester,
  ) async {
    documents.seed(noteWith('Already written.'));
    await pumpEditor(tester);

    expect(find.text('Saved'), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNull,
      reason: 'nothing has changed, so there is nothing to save',
    );

    await tester.enterText(find.byType(TextField), 'Now edited.');
    await tester.pump();

    expect(find.text('Save'), findsOneWidget);
    expect(
      tester.widget<TextButton>(find.byType(TextButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('saving stores the text and re-indexes it', (tester) async {
    documents.seed(noteWith(''));
    await pumpEditor(tester);

    await tester.enterText(find.byType(TextField), 'The boiler is serviced.');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      documents.store['note']!.pages.single.text,
      'The boiler is serviced.',
    );
    expect(
      search.indexedIds,
      contains('note'),
      reason: 'an edit that is not indexed looks saved but is unfindable',
    );
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('a stream update does not overwrite what is being typed', (
    tester,
  ) async {
    // The document stream re-emits on every write, including this screen's own
    // save. Reloading the field from it would delete whatever was typed in the
    // meantime.
    documents.seed(noteWith('Original.'));
    await pumpEditor(tester);

    await tester.enterText(find.byType(TextField), 'Half-typed thought');
    await tester.pump();

    documents.seed(noteWith('Changed underneath.'));
    await tester.pumpAndSettle();

    expect(find.text('Half-typed thought'), findsOneWidget);
  });

  testWidgets('leaving saves rather than asking whether to', (tester) async {
    documents.seed(noteWith(''));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(documents),
          searchRepositoryProvider.overrideWithValue(search),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => const TextEditorScreen(
                      documentId: 'note',
                      pageId: 'page-0',
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Written on the way out.');
    await tester.pump();

    // The system back gesture, which is what a user actually does.
    final dynamic state = tester.state(find.byType(Navigator));
    // ignore: avoid_dynamic_calls
    await state.maybePop();
    await tester.pumpAndSettle();

    expect(
      documents.store['note']!.pages.single.text,
      'Written on the way out.',
      reason: 'a note-taking screen must not lose work to a back gesture',
    );
    expect(find.byType(TextEditorScreen), findsNothing);
  });

  testWidgets('a failed save keeps the user on the page', (tester) async {
    documents.seed(noteWith(''));
    await pumpEditor(tester);

    await tester.enterText(find.byType(TextField), 'Will not save.');
    await tester.pump();

    documents.saveFailure = const StorageFailure('The disk is full.');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(TextEditorScreen), findsOneWidget);
    expect(find.text('Save'), findsOneWidget, reason: 'still unsaved');
  });

  testWidgets('a deleted page says so instead of rendering an editor', (
    tester,
  ) async {
    documents.seed(buildDocument(id: 'note', title: 'Tenancy notes'));

    await pumpEditor(tester);

    expect(find.text('This page is no longer here'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
