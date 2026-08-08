import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';

/// A placeholder shaped like the content that is coming.
///
/// Used where the wait is short and the shape is known — a list of documents,
/// a row of pages. It beats a spinner in that case for one reason: the screen
/// does not change layout when the data lands, so nothing jumps under a thumb
/// already moving towards it. Where the shape is *not* known, or the wait is
/// long enough to need explaining, [AppStateView.busy] is the honest choice.
class AppSkeleton extends StatefulWidget {
  const AppSkeleton({
    required this.width,
    required this.height,
    this.borderRadius,
    super.key,
  });

  /// A rounded bar, for a line of text.
  const AppSkeleton.line({
    double width = double.infinity,
    double height = 14,
    Key? key,
  }) : this(width: width, height: height, key: key);

  final double width;
  final double height;
  final BorderRadius? borderRadius;

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colours = Theme.of(context).colorScheme;

    // A slow fade rather than a sweeping shimmer. A shimmer draws the eye to
    // the placeholder, which is the one thing on screen with nothing to say —
    // and `prefers reduced motion` users get the midpoint and no movement.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) => Opacity(
          opacity: reduceMotion ? 0.5 : 0.35 + (_pulse.value * 0.3),
          child: child,
        ),
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: colours.surfaceContainerHighest,
            borderRadius: widget.borderRadius ?? AppRadius.small,
          ),
        ),
      ),
    );
  }
}

/// A list of placeholder rows shaped like the document library.
class AppListSkeleton extends StatelessWidget {
  const AppListSkeleton({this.rows = 6, super.key});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      liveRegion: true,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        itemCount: rows,
        separatorBuilder: (context, index) => AppSpacing.gapLg,
        itemBuilder: (context, index) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppSkeleton(
              width: 48,
              height: 64,
              borderRadius: AppRadius.small,
            ),
            AppSpacing.gapHorizontalMd,
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // Varied widths, because a column of identical bars reads as
                  // a loading graphic rather than as text about to arrive.
                  AppSkeleton.line(width: index.isEven ? 190 : 140),
                  AppSpacing.gapSm,
                  const AppSkeleton.line(width: 110, height: 11),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
