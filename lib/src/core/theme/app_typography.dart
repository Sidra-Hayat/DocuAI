import '../text/markup.dart';

/// The type scale a document is set in.
///
/// One place, because the same six block kinds are drawn by three different
/// things — the editor's own controller, the reader, and the PDF composer — and
/// a heading that is 1.5x the body in one and 1.28x in another is a document
/// that changes size on its way to being read.
///
/// Sizes rather than multipliers at the call site: "Heading 1 is 24" is a
/// decision somebody can check against a design, and `size * 1.28` is not.
abstract final class AppTypography {
  /// Body text. Matches Material's `bodyLarge`, which is what the editor and
  /// the reader were already using.
  static const double body = 16;

  static const double heading1 = 24;
  static const double heading2 = 20;

  /// Present because the markup format has three heading levels, even though
  /// the toolbar only offers two — a document imported or typed with `###`
  /// still has to render as something between a heading and a paragraph.
  static const double heading3 = 18;

  /// Line height for running text. Generous on purpose: recognised text has no
  /// typographic structure of its own, and leading is what stops a page of it
  /// reading as a wall.
  static const double bodyHeight = 1.6;

  /// Headings sit tighter than body text — a two-line heading set at 1.6 reads
  /// as two separate lines rather than as one heading.
  static const double headingHeight = 1.25;

  /// The size one block kind is set at, before any reader scaling.
  static double sizeFor(MarkupBlockKind kind) => switch (kind) {
    MarkupBlockKind.heading1 => heading1,
    MarkupBlockKind.heading2 => heading2,
    MarkupBlockKind.heading3 => heading3,
    MarkupBlockKind.paragraph ||
    MarkupBlockKind.bullet ||
    MarkupBlockKind.numbered ||
    MarkupBlockKind.quote ||
    // A picture has no text to set. Callers draw it rather than measuring it;
    // this keeps the switch exhaustive without a default that would swallow a
    // kind added later.
    MarkupBlockKind.image => body,
  };

  static bool isHeading(MarkupBlockKind kind) =>
      kind == MarkupBlockKind.heading1 ||
      kind == MarkupBlockKind.heading2 ||
      kind == MarkupBlockKind.heading3;
}
