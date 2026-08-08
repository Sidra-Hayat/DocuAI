import 'package:docuai/src/core/theme/app_spacing.dart';
import 'package:docuai/src/core/theme/app_theme.dart';
import 'package:docuai/src/core/widgets/app_empty_state.dart';
import 'package:docuai/src/core/widgets/app_skeleton.dart';
import 'package:docuai/src/core/widgets/app_state_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The design system, and the states every screen shares.
///
/// Most of this is not about how things look — a test cannot judge that. It is
/// about the properties that quietly decay: touch targets shrinking under a
/// density setting, dark mode being an inversion rather than a design, a
/// loading panel that announces nothing to a screen reader.
void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Brightness brightness = Brightness.light,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light(),
        home: Scaffold(body: child),
      ),
    );
    await tester.pump();
  }

  group('tokens', () {
    test('spacing follows a 4dp grid', () {
      for (final step in <double>[
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xxl,
      ]) {
        expect(step % 4, 0, reason: '$step is off the grid');
      }
    });

    test('the scale ascends', () {
      expect(
        <double>[
          AppSpacing.xs,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.xxl,
        ],
        orderedEquals(<double>[4, 8, 12, 16, 24, 32]),
      );
    });

    test('radii ascend and stop where Material says', () {
      expect(AppRadius.xs, lessThan(AppRadius.sm));
      expect(AppRadius.sm, lessThan(AppRadius.md));
      expect(AppRadius.md, lessThan(AppRadius.lg));
      expect(
        AppRadius.xxl,
        28,
        reason: 'dialogs and sheets follow the Material specification',
      );
    });
  });

  group('theme', () {
    test('both brightnesses come from one seed', () {
      expect(AppTheme.light().colorScheme.brightness, Brightness.light);
      expect(AppTheme.dark().colorScheme.brightness, Brightness.dark);
    });

    test('dark mode is designed, not inverted', () {
      final dark = AppTheme.dark().colorScheme;

      // The page sits below its cards, so surfaces separate by tone rather
      // than needing a border — a shadow shows nothing on a dark screen.
      expect(
        dark.surface.computeLuminance(),
        lessThan(dark.surfaceContainerLow.computeLuminance()),
      );
      expect(
        dark.surfaceContainerLow.computeLuminance(),
        lessThan(dark.surfaceContainerHigh.computeLuminance()),
      );
    });

    test('body text meets contrast on both grounds', () {
      // 4.5:1 is the WCAG AA threshold for body text.
      double ratio(Color a, Color b) {
        final la = a.computeLuminance();
        final lb = b.computeLuminance();
        final lighter = la > lb ? la : lb;
        final darker = la > lb ? lb : la;
        return (lighter + 0.05) / (darker + 0.05);
      }

      for (final scheme in <ColorScheme>[
        AppTheme.light().colorScheme,
        AppTheme.dark().colorScheme,
      ]) {
        expect(
          ratio(scheme.onSurface, scheme.surface),
          greaterThanOrEqualTo(4.5),
          reason: 'body text on the page background',
        );
        expect(
          ratio(scheme.onSurface, scheme.surfaceContainerLow),
          greaterThanOrEqualTo(4.5),
          reason: 'body text on a card',
        );
      }
    });

    test('icon buttons keep a 48dp target whatever the density', () {
      final style = AppTheme.light().iconButtonTheme.style;
      final size = style?.minimumSize?.resolve(<WidgetState>{});

      expect(size?.width, AppAccessibility.minTouchTarget);
      expect(size?.height, AppAccessibility.minTouchTarget);
    });

    test('primary buttons are at least 48dp tall', () {
      final style = AppTheme.light().filledButtonTheme.style;
      final size = style?.minimumSize?.resolve(<WidgetState>{});

      expect(
        size?.height,
        greaterThanOrEqualTo(AppAccessibility.minTouchTarget),
      );
    });

    test('sheets are rounded at the top only', () {
      final shape =
          AppTheme.light().bottomSheetTheme.shape! as RoundedRectangleBorder;

      expect(shape.borderRadius, AppRadius.sheet);
    });
  });

  group('state panels', () {
    testWidgets('an empty state invites an action', (tester) async {
      await pump(
        tester,
        AppStateView(
          icon: Icons.folder_outlined,
          title: 'No documents yet',
          message: 'Scan a page or write a note.',
          action: FilledButton(onPressed: () {}, child: const Text('Scan')),
        ),
      );

      expect(find.text('No documents yet'), findsOneWidget);
      expect(find.text('Scan a page or write a note.'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Scan'), findsOneWidget);
      expect(find.bySemanticsLabel('Nothing here yet'), findsOneWidget);
    });

    testWidgets('a busy state shows a spinner and says so', (tester) async {
      await pump(tester, const AppStateView.busy(title: 'Reading pages…'));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Reading pages…'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Working'),
        findsOneWidget,
        reason: 'a wait that announces nothing is a wait nobody can follow',
      );
    });

    testWidgets('a determinate wait reports how far along it is', (
      tester,
    ) async {
      await pump(
        tester,
        const AppStateView.busy(title: 'Reading pages…', progress: 0.25),
      );

      final indicator = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );

      expect(indicator.value, 0.25);
      expect(find.text('25%'), findsOneWidget);
    });

    testWidgets('a problem state is coloured as one and offers a way out', (
      tester,
    ) async {
      await pump(
        tester,
        AppStateView.problem(
          icon: Icons.error_outline,
          title: 'Could not read this page',
          action: FilledButton(onPressed: () {}, child: const Text('Try again')),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
      final colours = AppTheme.light().colorScheme;

      expect(icon.color, colours.error);
      expect(find.bySemanticsLabel('Something went wrong'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
    });

    testWidgets('the old empty state still renders through the new one', (
      tester,
    ) async {
      // A dozen screens say `AppEmptyState`; replacing those call sites would
      // be churn, so it delegates instead.
      await pump(
        tester,
        const AppEmptyState(
          icon: Icons.search_off,
          title: 'No matches',
          message: 'Try a shorter word.',
        ),
      );

      expect(find.byType(AppStateView), findsOneWidget);
      expect(find.text('No matches'), findsOneWidget);
    });

    testWidgets('a long message stays readable rather than filling a tablet', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(2000, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pump(
        tester,
        const AppStateView(
          icon: Icons.info_outline,
          title: 'Title',
          message:
              'A message long enough that, unbounded, it would run the whole '
              'width of a tablet and become genuinely hard to read.',
        ),
      );

      // Measured on the text itself rather than on a ConstrainedBox found by
      // type — the Scaffold and the scroll view contribute their own, and the
      // first one found is not necessarily ours.
      final rendered = tester.renderObject<RenderBox>(
        find.textContaining('A message long enough'),
      );

      expect(
        rendered.size.width,
        lessThanOrEqualTo(420),
        reason: 'a line running the width of a tablet is hard to read',
      );
    });

    testWidgets('renders in dark mode without losing its text', (tester) async {
      await pump(
        tester,
        const AppStateView(icon: Icons.folder_outlined, title: 'Nothing here'),
        brightness: Brightness.dark,
      );

      expect(find.text('Nothing here'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('skeletons', () {
    testWidgets('the list placeholder has the shape of a list', (tester) async {
      await pump(tester, const AppListSkeleton(rows: 4));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(AppSkeleton), findsNWidgets(4 * 3));
      expect(find.bySemanticsLabel('Loading'), findsOneWidget);
    });

    testWidgets('placeholders are hidden from screen readers', (tester) async {
      // The list announces itself as loading; the bars inside it are shapes
      // with nothing to say, and reading them out would be noise.
      await pump(tester, const AppListSkeleton(rows: 2));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(ExcludeSemantics), findsWidgets);
    });

    testWidgets('the pulse stops when animations are disabled', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: const MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(body: AppSkeleton(width: 100, height: 20)),
          ),
        ),
      );
      await tester.pump();

      final before = tester.widget<Opacity>(find.byType(Opacity)).opacity;
      await tester.pump(const Duration(milliseconds: 550));
      final after = tester.widget<Opacity>(find.byType(Opacity)).opacity;

      expect(after, before, reason: 'reduced motion means no motion');
    });

    testWidgets('disposes its ticker without complaint', (tester) async {
      await pump(tester, const AppSkeleton(width: 80, height: 12));
      await tester.pumpWidget(const SizedBox.shrink());

      expect(tester.takeException(), isNull);
    });
  });
}
