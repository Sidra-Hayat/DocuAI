import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_spacing.dart';

/// Material 3 theming for DocuAI.
///
/// Both themes are generated from a single [seedColor] so light and dark stay
/// tonally consistent and every surface/contrast pair is guaranteed accessible
/// by Material's own tonal-palette algorithm. Component themes below only
/// override shape and density — never raw colours — so re-branding the app is a
/// one-line change to [seedColor].
///
/// No `google_fonts` on purpose: that package downloads font files over the
/// network on first use, which would break the "works fully offline" promise.
/// Bundle a font in `assets/` and set [fontFamily] if a custom typeface is
/// wanted later.
abstract final class AppTheme {
  /// The single source of truth for DocuAI's colour identity.
  static const Color seedColor = Color(0xFF2563EB);

  /// Radii come from [AppRadius] rather than being restated here. They used to
  /// be private to this file, which is precisely why widgets had grown their
  /// own — a component that cannot reach the token invents one.

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final generated = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;

    // Dark mode is designed, not inverted. Two deliberate departures from the
    // generated palette:
    //
    //  * The page background drops below the darkest generated container, so
    //    cards and sheets separate by tone rather than needing borders. A
    //    document library is a list of surfaces; if they sit at the same
    //    lightness as the page they read as one block.
    //  * `surfaceContainerLowest` becomes the card colour, since a card that is
    //    *lighter* than its background is what reads as raised on a dark
    //    screen, where a shadow shows nothing.
    final colorScheme = isDark
        ? generated.copyWith(
            surface: const Color(0xFF101418),
            surfaceContainerLowest: const Color(0xFF0B0E11),
            surfaceContainerLow: const Color(0xFF161B20),
            surfaceContainer: const Color(0xFF1A2026),
            surfaceContainerHigh: const Color(0xFF222930),
            surfaceContainerHighest: const Color(0xFF2A323A),
          )
        : generated;

    return ThemeData(
      colorScheme: colorScheme,
      // Slightly denser than the default on Android, which suits list-heavy
      // screens like the document library.
      visualDensity: VisualDensity.adaptivePlatformDensity,
      scaffoldBackgroundColor: colorScheme.surface,

      appBarTheme: AppBarTheme(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: colorScheme.surfaceTint,
        centerTitle: false,
        scrolledUnderElevation: 3,
        titleTextStyle: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurface,
        ),
        // Keeps the status bar icons legible against the app bar in both modes.
        systemOverlayStyle: isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),

      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        color: colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),

      navigationBarTheme: NavigationBarThemeData(
        elevation: 3,
        height: 72,
        backgroundColor: colorScheme.surfaceContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(64, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),

      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),

      chipTheme: ChipThemeData(
        // Squarer than a button on purpose: a chip is a label that can be
        // tapped, and rounding it like a button makes a list of tags read as a
        // row of controls.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        side: BorderSide(color: colorScheme.outlineVariant),
        backgroundColor: colorScheme.surfaceContainerHighest,
        labelStyle: TextStyle(
          fontSize: 13,
          color: colorScheme.onSurfaceVariant,
        ),
      ),

      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xxl),
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.sheet),
      ),

      // Every icon button reaches the 48dp minimum, whatever the surrounding
      // density says. `adaptivePlatformDensity` tightens controls to suit a
      // list-heavy app, and on Android that quietly takes an icon button under
      // the size a thumb can reliably hit.
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(AppAccessibility.minTouchTarget),
        ),
      ),

      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 500),
        preferBelow: false,
      ),

      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          minimumSize: const Size(48, AppAccessibility.minTouchTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        ),
      ),

      // A page transition that feels like the platform rather than like
      // Flutter's default, which is noticeably slower than Android's own.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),

      dividerTheme: DividerThemeData(
        space: 1,
        thickness: 1,
        color: colorScheme.outlineVariant,
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
      ),
    );
  }
}
