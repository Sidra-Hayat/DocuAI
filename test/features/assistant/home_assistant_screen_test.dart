import 'package:docuai/src/features/assistant/domain/entities/assistant_intent.dart';
import 'package:docuai/src/features/assistant/presentation/providers/assistant_providers.dart';
import 'package:docuai/src/features/assistant/presentation/screens/assistant_screen.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/documents/presentation/providers/document_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

/// The Assistant opened from the Home tab, as a screen.
///
/// The engine's own behaviour is covered against a real index in
/// `global_assistant_test.dart`. What can only be checked here is the wiring:
/// that an example prompt is a question the screen actually *asks*, and that the
/// actions offered are the ones the engine can carry out.
///
/// An example that looks like a button and does nothing is worse than no
/// example at all, and nothing below the widget layer can catch that.
void main() {
  late FakeAssistantRepository assistant;
  late FakeDocumentRepository documents;

  setUp(() {
    assistant = FakeAssistantRepository();
    documents = FakeDocumentRepository();

    // One readable document, so the screen shows its introduction rather than
    // the "nothing to ask about yet" state.
    documents.seed(
      buildDocument(
        id: 'bill',
        title: 'Electricity bill August',
        pages: <DocumentPage>[
          buildPage(
            id: 'bill-p0',
            index: 0,
            text: 'Total amount due: 248.60 EUR',
            ocrStatus: OcrStatus.completed,
          ),
        ],
      ),
    );
  });

  tearDown(() => documents.dispose());

  Future<void> pumpHomeAssistant(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        // Untyped on purpose: Riverpod 3 does not export its `Override` type,
        // so the list cannot be annotated. Same reason `bootstrap()` takes no
        // overrides parameter.
        overrides: [
          assistantRepositoryProvider.overrideWithValue(assistant),
          documentRepositoryProvider.overrideWithValue(documents),
        ],
        child: const MaterialApp(
          // No documentId: this is the library-wide conversation reached from
          // the Home tab, which is where every one of these questions failed.
          home: AssistantScreen(conversationId: 'library'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('the example prompts', () {
    testWidgets('tapping one asks that exact question', (tester) async {
      assistant.suggestions = <String>[
        'Who is mentioned in my documents?',
        'What is the Electricity bill August about?',
      ];

      await pumpHomeAssistant(tester);

      // Scrolled to first: the introduction is a scrolling column, and on a
      // test-sized screen the example chips sit below the fold.
      await tester.ensureVisible(find.text('Who is mentioned in my documents?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Who is mentioned in my documents?'));
      await tester.pumpAndSettle();

      expect(
        assistant.askedQuestions,
        <String>['Who is mentioned in my documents?'],
        reason: 'an example is only useful if tapping it runs it',
      );
      expect(
        assistant.lastScopedDocumentId,
        isNull,
        reason: 'asked from the Home tab, so the whole library is in scope',
      );
    });

    testWidgets('one that repeats a button is not shown twice', (tester) async {
      assistant.suggestions = <String>[
        'Summarize my latest document',
        'Who is mentioned in my documents?',
      ];

      await pumpHomeAssistant(tester);

      // The quick action carries this wording already, so the example chip for
      // it is dropped rather than printed underneath its own button.
      expect(find.text('Summarize my latest document'), findsOneWidget);
      expect(find.text('Who is mentioned in my documents?'), findsOneWidget);
    });

    testWidgets('none are shown when the engine has nothing to offer', (
      tester,
    ) async {
      assistant.suggestions = <String>[];

      await pumpHomeAssistant(tester);

      expect(find.text('FOR EXAMPLE'), findsNothing);
    });
  });

  group('the quick actions', () {
    testWidgets('Summarize and Explain are offered from the Home tab', (
      tester,
    ) async {
      await pumpHomeAssistant(tester);

      // Both were hidden here, because both could only answer "open a document
      // first". They now resolve to the document last worked on.
      expect(find.text('Summarize my latest document'), findsOneWidget);
      expect(find.text('Explain my latest document'), findsOneWidget);
      expect(find.text('Find important information'), findsOneWidget);
    });

    testWidgets('Summarize sends an intent, never a sentence to be parsed', (
      tester,
    ) async {
      await pumpHomeAssistant(tester);

      await tester.ensureVisible(find.text('Summarize my latest document'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Summarize my latest document'));
      await tester.pumpAndSettle();

      expect(assistant.intents.single, isA<SummarizeDocument>());
      expect(
        assistant.askedQuestions,
        isEmpty,
        reason: 'a button knows what it means and must not be re-read as text',
      );
    });

    testWidgets('Explain sends an intent from the Home tab too', (
      tester,
    ) async {
      await pumpHomeAssistant(tester);

      await tester.ensureVisible(find.text('Explain my latest document'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Explain my latest document'));
      await tester.pumpAndSettle();

      expect(assistant.intents.single, isA<ExplainDocument>());
    });
  });

  group('the introduction', () {
    testWidgets('says what can be asked, without retrieval vocabulary', (
      tester,
    ) async {
      await pumpHomeAssistant(tester);

      expect(find.textContaining('Ask in your own words'), findsOneWidget);

      final rendered = tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data ?? '')
          .join(' ')
          .toLowerCase();

      for (final jargon in <String>[
        'bm25',
        'index',
        'retrieval',
        'passage',
        'token',
        'ocr',
      ]) {
        expect(
          rendered,
          isNot(contains(jargon)),
          reason: 'the Home assistant showed the word "$jargon"',
        );
      }
    });

    testWidgets('an unreadable library says so instead of offering actions', (
      tester,
    ) async {
      documents.store.clear();

      await pumpHomeAssistant(tester);

      expect(find.text('Nothing to ask about yet'), findsOneWidget);
    });
  });
}
