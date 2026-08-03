import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  static const double _radiusSm = 8;
  static const double _radiusMd = 12;
  static const double _radiusLg = 20;

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    final isDark = brightness == Brightness.dark;

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
          borderRadius: BorderRadius.circular(_radiusMd),
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
          borderRadius: BorderRadius.circular(_radiusLg),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radiusMd),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radiusMd),
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(64, 44),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_radiusSm),
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
          borderRadius: BorderRadius.circular(_radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
          borderSide: BorderSide(color: colorScheme.primary, width: 2),
        ),
      ),

      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusMd),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),

      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusSm),
        ),
      ),

      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusSm),
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
