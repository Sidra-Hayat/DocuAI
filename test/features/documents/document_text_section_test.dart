import 'package:docuai/src/features/documents/domain/entities/document_page.dart';
import 'package:docuai/src/features/documents/presentation/widgets/document_text_section.dart';
import 'package:docuai/src/features/ocr/presentation/providers/ocr_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

/// Fixes the controller in one state so each rendering branch can be checked
/// without driving a real recognition run.
class _StubOcrController extends OcrController {
  _StubOcrController(this._initial);

  final OcrState _initial;

  @override
  OcrState build() => _initial;
}

void main() {
  Future<void> pumpSection(
    WidgetTester tester, {
    required List<DocumentPage> pages,
    OcrState ocrState = const OcrIdle(),
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ocrControllerProvider.overrideWith(() => _StubOcrController(ocrState)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DocumentTextSection(document: buildDocument(pages: pages)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the recognised text once pages are read', (tester) async {
    await pumpSection(
      tester,
      pages: <DocumentPage>[
        buildPage(
          id: 'a',
          index: 0,
          text: 'Total due: 42.00 EUR',
          ocrStatus: OcrStatus.completed,
        ),
      ],
    );

    expect(find.text('Recognised text'), findsOneWidget);
    expect(find.text('Total due: 42.00 EUR'), findsOneWidget);
    expect(find.byIcon(Icons.refresh), findsOneWidget);
  });

  testWidgets('offers to start when nothing has been read yet', (tester) async {
    await pumpSection(tester, pages: <DocumentPage>[buildPage()]);

    expect(
      find.widgetWithText(FilledButton, 'Recognise text'),
      findsOneWidget,
    );
    expect(find.textContaining('searchable'), findsOneWidget);
  });

  testWidgets('says so plainly when the pages held no text', (tester) async {
    await pumpSection(
      tester,
      pages: <DocumentPage>[
        buildPage(id: 'a', index: 0, ocrStatus: OcrStatus.completed),
      ],
    );

    expect(find.textContaining('No text was found'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Read again'), findsOneWidget);
  });

  testWidgets('explains a failed run and offers a retry', (tester) async {
    await pumpSection(
      tester,
      pages: <DocumentPage>[
        buildPage(id: 'a', index: 0, ocrStatus: OcrStatus.failed),
      ],
    );

    expect(find.textContaining('could not be read'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
  });

  testWidgets('keeps partial text and flags the pages that failed', (
    tester,
  ) async {
    await pumpSection(
      tester,
      pages: <DocumentPage>[
        buildPage(
          id: 'a',
          index: 0,
          text: 'Page one text',
          ocrStatus: OcrStatus.completed,
        ),
        buildPage(id: 'b', index: 1, ocrStatus: OcrStatus.failed),
      ],
    );

    expect(find.text('Page one text'), findsOneWidget);
    expect(find.textContaining('One page could not be read'), findsOneWidget);
  });

  testWidgets('pluralises the failed-page count', (tester) async {
    await pumpSection(
      tester,
      pages: <DocumentPage>[
        buildPage(id: 'a', index: 0, text: 'ok', ocrStatus: OcrStatus.completed),
        buildPage(id: 'b', index: 1, ocrStatus: OcrStatus.failed),
        buildPage(id: 'c', index: 2, ocrStatus: OcrStatus.failed),
      ],
    );

    expect(find.textContaining('2 pages could not be read'), findsOneWidget);
  });

  testWidgets('shows determinate progress while reading', (tester) async {
    await pumpSection(
      tester,
      pages: <DocumentPage>[buildPage()],
      ocrState: const OcrRunning(documentId: 'doc-1', done: 1, total: 3),
    );

    expect(find.text('Reading page 1 of 3…'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, closeTo(1 / 3, 0.001));
  });

  testWidgets('ignores a run belonging to a different document', (
    tester,
  ) async {
    await pumpSection(
      tester,
      pages: <DocumentPage>[buildPage()],
      ocrState: const OcrRunning(documentId: 'other', done: 1, total: 3),
    );

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Recognise text'), findsOneWidget);
  });
}
