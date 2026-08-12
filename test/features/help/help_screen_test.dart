import 'package:docuai/src/core/theme/app_theme.dart';
import 'package:docuai/src/features/help/presentation/screens/help_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The beginner's guide.
///
/// The one screen in the app written for somebody who has not used it yet,
/// which is what makes its vocabulary the whole point: a guide that explains
/// "OCR" and "retrieval" is a guide for the person who built the thing.
void main() {
  Future<void> pumpHelp(WidgetTester tester, {Brightness? brightness}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.dark
            ? AppTheme.dark()
            : AppTheme.light(),
        home: const HelpScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('covers every way into and out of a document', (tester) async {
    await pumpHelp(tester);

    for (final section in <String>[
      'Scan',
      'Import',
      'Create a document',
      'Assistant',
      'Search',
      'PDF and sharing',
    ]) {
      // Scrolled to rather than assumed visible: the guide is longer than a
      // phone screen, which is the point of it being a scrolling page.
      await tester.scrollUntilVisible(
        find.text(section),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(section), findsOneWidget, reason: 'missing $section');
    }
  });

  testWidgets('leads with the privacy promise', (tester) async {
    await pumpHelp(tester);

    // It is the reason to keep a payslip in this app rather than another one,
    // and it was previously written down only in Settings.
    expect(find.text('Everything stays on your phone'), findsOneWidget);
  });

  testWidgets('explains without technical language', (tester) async {
    await pumpHelp(tester);

    final rendered = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? '')
        .join(' ')
        .toLowerCase();

    expect(rendered, isNotEmpty);

    for (final jargon in <String>[
      'ocr',
      'bm25',
      'retrieval',
      'index',
      'hive',
      'passage',
      'token',
      'metadata',
      'parse',
    ]) {
      expect(
        rendered,
        isNot(contains(jargon)),
        reason: 'the beginner guide used the word "$jargon"',
      );
    }
  });

  testWidgets('fits a narrow phone without overflowing', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpHelp(tester);

    expect(tester.takeException(), isNull);
  });

  testWidgets('the last section clears the system navigation bar', (
    tester,
  ) async {
    // The bug reported from a phone: the guide scrolled, but its content ended
    // at its own padding — and `bootstrap()` puts the app in edge-to-edge, so
    // the window runs *under* the gesture bar. The final section could be
    // scrolled to and still not be readable.
    const gestureBar = 48.0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const MediaQuery(
          data: MediaQueryData(
            padding: EdgeInsets.only(bottom: gestureBar),
          ),
          child: HelpScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('PDF and sharing'),
      300,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();

    // Scroll to the very end and check the last words of the guide sit above
    // where the system bar starts, rather than behind it.
    await tester.fling(scrollable, const Offset(0, -2000), 2000);
    await tester.pumpAndSettle();

    final lastText = find.textContaining('sent as a Word file');
    expect(lastText, findsOneWidget);

    final bottomOfText = tester.getBottomLeft(lastText).dy;
    final screenBottom = tester.getSize(find.byType(HelpScreen)).height;

    expect(
      bottomOfText,
      lessThanOrEqualTo(screenBottom - gestureBar),
      reason: 'the last paragraph is underneath the system navigation bar',
    );
  });

  testWidgets('renders in dark mode', (tester) async {
    await pumpHelp(tester, brightness: Brightness.dark);

    expect(find.text('How DocuAI works'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
