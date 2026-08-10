import 'package:flutter/material.dart';

/// The spacing scale.
///
/// A 4dp grid, named rather than typed out. Every gap in the app was a literal
/// before this, which is why `6`, `10` and `14` had crept in beside `8`, `12`
/// and `16` — differences too small to be deliberate and too visible to be
/// nothing. Naming them makes an off-grid value something you have to write on
/// purpose.
abstract final class AppSpacing {
  /// 4 — between an icon and its label.
  static const double xs = 4;

  /// 8 — between tightly related lines.
  static const double sm = 8;

  /// 12 — between elements inside one component.
  static const double md = 12;

  /// 16 — the default. Screen edges, card padding, list rows.
  static const double lg = 16;

  /// 24 — between distinct groups on a screen.
  static const double xl = 24;

  /// 32 — around an empty state, where the point is the breathing room.
  static const double xxl = 32;

  /// Clears a floating action button, so the last row of a list is reachable.
  static const double fabClearance = 88;

  static const EdgeInsets screen = EdgeInsets.all(lg);
  static const EdgeInsets screenHorizontal = EdgeInsets.symmetric(
    horizontal: lg,
  );

  /// A vertical gap. Reads better than a bare `SizedBox` at a call site.
  static const Widget gapXs = SizedBox(height: xs);
  static const Widget gapSm = SizedBox(height: sm);
  static const Widget gapMd = SizedBox(height: md);
  static const Widget gapLg = SizedBox(height: lg);
  static const Widget gapXl = SizedBox(height: xl);
  static const Widget gapXxl = SizedBox(height: xxl);

  static const Widget gapHorizontalXs = SizedBox(width: xs);
  static const Widget gapHorizontalSm = SizedBox(width: sm);
  static const Widget gapHorizontalMd = SizedBox(width: md);
  static const Widget gapHorizontalLg = SizedBox(width: lg);
}

/// Corner radii.
///
/// Public, unlike the private constants the theme used to hold — which is the
/// reason widgets had grown their own `circular(3)`, `(4)`, `(10)` and `(28)`.
/// A rounding that varies by a pixel or two between components does not read as
/// a choice; it reads as nobody having decided.
abstract final class AppRadius {
  /// 4 — chips and badges, where a rounder corner would look like a button.
  static const double xs = 4;

  /// 8 — inline controls: snackbars, small buttons.
  static const double sm = 8;

  /// 12 — the default. Cards, fields, list tiles, buttons.
  static const double md = 12;

  /// 16 — larger surfaces that sit on a page rather than in it.
  static const double lg = 16;

  /// 20 — floating action buttons.
  static const double xl = 20;

  /// 28 — dialogs and bottom sheets, per Material's own specification.
  static const double xxl = 28;

  static BorderRadius get chip => BorderRadius.circular(xs);
  static BorderRadius get small => BorderRadius.circular(sm);
  static BorderRadius get card => BorderRadius.circular(md);
  static BorderRadius get surface => BorderRadius.circular(lg);
  static BorderRadius get sheet =>
      const BorderRadius.vertical(top: Radius.circular(xxl));
}

/// Sizes that exist for reach and legibility rather than for looks.
abstract final class AppAccessibility {
  /// The smallest a tappable thing may be.
  ///
  /// Material and the Android accessibility guidelines both say 48dp. It is
  /// easy to lose without noticing: `VisualDensity.compact` on a chip or an
  /// icon button takes a control under it while looking tidier, which is a
  /// trade nobody would make deliberately.
  static const double minTouchTarget = 48;

  /// Ceiling on system text scaling.
  ///
  /// Applied in `app.dart`. Above this the app's own layouts break, which
  /// serves nobody — a screen that cannot be read because it has collapsed is
  /// worse than one whose text is slightly smaller than asked for.
  static const double maxTextScale = 1.4;
}
