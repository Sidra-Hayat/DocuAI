import 'package:docuai/src/features/documents/domain/entities/document.dart';
import 'package:docuai/src/features/documents/presentation/widgets/document_actions.dart';
import 'package:docuai/src/features/documents/presentation/widgets/page_edit_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Driving the app's menus from a test.
///
/// The overflow menus became bottom sheets — a popup is the wrong container for
/// a list that includes "Delete this permanently" — and every test that used to
/// reach for `PopupMenuButton<DocumentAction>` now goes through here instead.
/// One helper rather than the same three lines in eight files, so the next
/// change to how a menu opens is one edit.

/// Opens a document's overflow menu and waits for the sheet.
Future<void> openDocumentActions(WidgetTester tester, {int index = 0}) async {
  await tester.tap(find.byType(DocumentActionsButton).at(index));
  await tester.pumpAndSettle();
}

/// Opens a document's overflow menu and taps one of its actions.
Future<void> tapDocumentAction(
  WidgetTester tester,
  String label, {
  int index = 0,
}) async {
  await openDocumentActions(tester, index: index);
  await tapSheetAction(tester, label);
}

/// Opens a page's overflow menu and waits for the sheet.
Future<void> openPageActions(WidgetTester tester, {int index = 0}) async {
  await tester.tap(find.byType(PageEditActions).at(index));
  await tester.pumpAndSettle();
}

/// Taps a row in an open action sheet.
///
/// Scoped to the sheet's own rows: a sheet is titled with the document's name,
/// and a document called "Delete the shed" would otherwise make `find.text`
/// ambiguous.
Future<void> tapSheetAction(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(ListTile), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

/// Types into the field of an open dialog.
///
/// Scoped to the dialog rather than to the only `TextField` on screen, because
/// the library now has one of its own — the search bar that opens the Search
/// tab. A bare `find.byType(TextField)` behind an open rename dialog is
/// ambiguous, and ambiguously right until the day the layout changes.
Future<void> enterDialogText(WidgetTester tester, String text) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    ),
    text,
  );
}

/// The title a document's action sheet is headed with.
String actionSheetTitle(Document document) => document.title;
