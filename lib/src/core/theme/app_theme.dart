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

  /// The supporting accent, reachable through `colorScheme.secondary`.
  ///
  /// Teal reads as the same *kind* of colour as the indigo primary — both cool,
  /// both technical — which is what lets the two sit together without the app
  /// looking like it has two brands. It marks things that are informational
  /// rather than actionable: the assistant's own chrome, a document's type, the
  /// tools that are not the main path through a screen.
  ///
  /// Two values for the same reason the gold has two. A teal bright enough to
  /// read on navy is close to illegible on paper, so light mode gets a deep one
  /// and dark mode a bright one; each is chosen against the ground it appears
  /// on rather than one hex being reused and hoped for.
  static const Color tealDark = Color(0xFF4DD0C7);
  static const Color tealLight = Color(0xFF00696B);

  /// The brand gold, reachable through `colorScheme.tertiary`.
  ///
  /// Deliberately *not* a colour widgets import. Gold arrives through the
  /// scheme so that no widget can hard-code a hex, and so both brightnesses get
  /// a value chosen for their own ground rather than one colour used twice —
  /// the light-mode gold is considerably deeper, because a gold that reads as
  /// premium on charcoal is illegible on paper.
  ///
  /// It is an accent, not an action colour. Reserved for the brand mark, the
  /// favourite star, and the small labels that mark a section as DocuAI's own.
  /// Every button, link and other primary action stays [seedColor] indigo — a
  /// second action colour would leave nothing saying which one to press.
  static const Color goldDark = Color(0xFFE3BE6E);
  static const Color goldLight = Color(0xFF7A5C10);

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
    //
    // The tertiary ramp is replaced outright in both brightnesses. Material
    // derives a tertiary from the seed, and what it derives from a blue seed is
    // a muted violet — a colour DocuAI's identity has no use for, and the only
    // slot in the scheme where the brand's gold can live without a widget
    // reaching for a raw hex.
    final colorScheme = isDark
        ? generated.copyWith(
            // Navy rather than neutral charcoal, and never flat black. Black
            // gives an OLED panel nothing to separate a card from the page
            // with, so every surface needs a border to exist; a navy ground
            // lets the tonal steps below do that work instead. The blue channel
            // runs about twice the red at every step, which is what keeps a
            // scan of white paper reading as warm against it.
            surface: const Color(0xFF0E1320),
            surfaceContainerLowest: const Color(0xFF090D17),
            surfaceContainerLow: const Color(0xFF141A2A),
            surfaceContainer: const Color(0xFF181F31),
            surfaceContainerHigh: const Color(0xFF202940),
            surfaceContainerHighest: const Color(0xFF2A3450),
            // Off-white, not white. Pure white on a dark ground haloes and is
            // tiring over a page of recognised text; this keeps the contrast
            // well past AA while taking the glare off.
            onSurface: const Color(0xFFE8ECF4),
            // The muted voice: timestamps, page counts, captions. Distinctly
            // quieter than the body text and still comfortably readable, which
            // is the whole difference between hierarchy and a contrast bug.
            onSurfaceVariant: const Color(0xFFA3AEC6),
            outlineVariant: const Color(0xFF2C3752),
            secondary: tealDark,
            onSecondary: const Color(0xFF00332F),
            secondaryContainer: const Color(0xFF1F4E4C),
            onSecondaryContainer: const Color(0xFFB8EDE8),
            tertiary: goldDark,
            onTertiary: const Color(0xFF3D2E00),
            tertiaryContainer: const Color(0xFF574314),
            onTertiaryContainer: const Color(0xFFFFDFA0),
          )
        : generated.copyWith(
            secondary: tealLight,
            onSecondary: const Color(0xFFFFFFFF),
            secondaryContainer: const Color(0xFFCFEFEA),
            onSecondaryContainer: const Color(0xFF00201F),
            tertiary: goldLight,
            onTertiary: const Color(0xFFFFFFFF),
            tertiaryContainer: const Color(0xFFF6E7BF),
            onTertiaryContainer: const Color(0xFF261A00),
          );

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
        // The generated indicator is `secondaryContainer`, which is now teal —
        // and teal is this app's *informational* colour, so the current tab
        // would have been marked in the one colour that means "not an action".
        // Indigo says which destination you are on in the same voice every
        // other active control uses.
        indicatorColor: colorScheme.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? colorScheme.onPrimaryContainer
                : colorScheme.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
          (states) => TextStyle(
            fontSize: 12,
            // The selected label carries the weight, not a second colour: two
            // signals for one state is how a navigation bar starts to shout.
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? colorScheme.onSurface
                : colorScheme.onSurfaceVariant,
          ),
        ),
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
