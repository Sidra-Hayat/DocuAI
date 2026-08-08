import 'package:docuai/src/core/router/app_routes.dart';
import 'package:docuai/src/features/assistant/domain/usecases/suggest_questions.dart';
import 'package:docuai/src/features/assistant/presentation/widgets/summarise_button.dart';
import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/fakes.dart';

/// The Summarise button on the document screen.
///
/// It runs no summariser of its own — it opens this document's conversation
/// with the question already asked. These tests hold that wiring, because the
/// moment the button grows a private path to an answer there are two
/// summarisers to keep in step, and the answer stops arriving with citations.
void main() {
  String? askedDocumentId;
  Map<String, String>? askedQuery;

  Future<void> pumpButton(WidgetTester tester, Document document) async {
    askedDocumentId = null;
    askedQuery = null;

    final router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (context, state) =>
              Scaffold(body: SummariseButton(document: document)),
          routes: <RouteBase>[
            GoRoute(
              path: 'documents/:id/ask',
              name: AppRoutes.askDocumentName,
              builder: (context, state) {
                askedDocumentId = state.pathParameters['id'];
                askedQuery = state.uri.queryParameters;
                return const Scaffold(body: Text('conversation'));
              },
            ),
          ],
        ),
      ],
    );

    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  Document documentWith({required bool recognised, bool hasPages = true}) =>
      buildDocument(
        id: 'bill',
        title: 'Electricity bill',
        pages: hasPages
            ? <DocumentPage>[
                buildPage(
                  id: 'bill-p0',
                  index: 0,
                  text: recognised ? 'Total amount due: £248.60' : '',
                  ocrStatus: recognised
                      ? OcrStatus.completed
                      : OcrStatus.pending,
                ),
              ]
            : const <DocumentPage>[],
      );

  testWidgets('it opens this document’s conversation with the question asked', (
    tester,
  ) async {
    await pumpButton(tester, documentWith(recognised: true));

    await tester.tap(find.text('Summarise'));
    await tester.pumpAndSettle();

    expect(askedDocumentId, 'bill');
    expect(
      askedQuery?['ask'],
      DocumentQuestions.summarise,
      reason: 'the button and someone typing it must reach the same analyser',
    );
    expect(
      askedQuery?['title'],
      'Electricity bill',
      reason: 'so the bar is titled on the first frame, not after a stream',
    );
  });

  testWidgets('unrecognised text does not disable it', (tester) async {
    // Recognition runs when a document is opened, so a document that has just
    // been scanned may still be mid-read. The assistant explains that wait
    // better than a button that does nothing and says nothing.
    await pumpButton(tester, documentWith(recognised: false));

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });

  testWidgets('a document with no pages has nothing to summarise', (
    tester,
  ) async {
    await pumpButton(
      tester,
      documentWith(recognised: false, hasPages: false),
    );

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });
}
