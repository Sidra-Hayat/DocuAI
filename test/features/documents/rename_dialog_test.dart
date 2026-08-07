import 'package:docuai/src/features/documents/presentation/providers/document_providers.dart';
import 'package:docuai/src/features/documents/presentation/widgets/document_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeDocumentRepository documents;

  setUp(() {
    documents = FakeDocumentRepository()..seed(buildDocument());
  });

  tearDown(() => documents.dispose());

  Future<void> pumpMenu(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          documentRepositoryProvider.overrideWithValue(documents),
        ],
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: [DocumentActionsMenu(document: buildDocument())],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openRenameDialog(WidgetTester tester) async {
    await tester.tap(find.byType(PopupMenuButton<DocumentAction>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
  }

  testWidgets('renaming from the menu does not throw', (tester) async {
    await pumpMenu(tester);
    await openRenameDialog(tester);

    await tester.enterText(find.byType(TextField), 'Water bill');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();

    expect(
      tester.takeException(),
      isNull,
      reason: 'confirming a rename must not leave the framework in a bad state',
    );
    expect(documents.savedDocuments.single.title, 'Water bill');
  });

  testWidgets('submitting from the keyboard does not throw', (tester) async {
    await pumpMenu(tester);
    await openRenameDialog(tester);

    await tester.enterText(find.byType(TextField), 'Passport');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(documents.savedDocuments.single.title, 'Passport');
  });

  testWidgets('the text controller outlives the dismiss animation', (
    tester,
  ) async {
    await pumpMenu(tester);
    await openRenameDialog(tester);
    await tester.enterText(find.byType(TextField), 'Rental agreement');

    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));

    // `showDialog`'s future completes the moment `Navigator.pop` runs, not
    // when the dismiss animation ends — `Route.didPop` completes the popped
    // completer immediately. For these frames the dialog is still mounted and
    // still rebuilding, which is precisely where a controller disposed at the
    // await site was reattached after disposal.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      tester.takeException(),
      isNull,
      reason: 'the controller must still be alive mid-transition',
    );

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(documents.savedDocuments.single.title, 'Rental agreement');
  });

  testWidgets('cancelling does not throw', (tester) async {
    await pumpMenu(tester);
    await openRenameDialog(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(documents.savedDocuments, isEmpty);
  });
}
