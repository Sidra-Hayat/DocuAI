import 'dart:async';

import 'package:docuai/src/features/scanner/presentation/providers/scan_controller.dart';
import 'package:docuai/src/features/scanner/presentation/screens/scan_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpScanScreen(
    WidgetTester tester, {
    required FutureOr<bool> available,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scannerAvailabilityProvider.overrideWith((ref) => available),
        ],
        child: const MaterialApp(home: ScanScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('offers to start when the scanner is available', (tester) async {
    await pumpScanScreen(tester, available: true);

    expect(find.text('Scan document'), findsOneWidget);
    expect(find.text('Ready to scan'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'Start scanning'),
      findsOneWidget,
    );
  });

  testWidgets('names the page limit so it is not discovered by hitting it', (
    tester,
  ) async {
    await pumpScanScreen(tester, available: true);

    expect(find.textContaining('up to 20 pages'), findsOneWidget);
  });

  testWidgets('explains itself when Play Services cannot provide the scanner', (
    tester,
  ) async {
    await pumpScanScreen(tester, available: false);

    expect(find.text('Scanning is not available here'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Start scanning'), findsNothing);
    expect(
      find.textContaining('works normally'),
      findsOneWidget,
      reason: 'a non-GMS device must not look like a broken app',
    );
  });

  testWidgets('shows a spinner while availability is being resolved', (
    tester,
  ) async {
    final completer = Completer<bool>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scannerAvailabilityProvider.overrideWith((ref) => completer.future),
        ],
        child: const MaterialApp(home: ScanScreen()),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(true);
    await tester.pumpAndSettle();

    expect(find.text('Ready to scan'), findsOneWidget);
  });

  testWidgets('keeps its app bar title while unavailable', (tester) async {
    await pumpScanScreen(tester, available: false);

    expect(find.text('Scan document'), findsOneWidget);
  });
}
