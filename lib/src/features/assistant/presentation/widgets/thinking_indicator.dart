import 'package:flutter/material.dart';

/// Shown while a question is being answered.
///
/// Three dots rising in sequence rather than a spinner. A spinner reads as
/// "waiting on something"; retrieval is the app doing work locally, and the
/// staggered rhythm says that without claiming stages the engine does not
/// actually report.
///
/// Deliberately does not narrate steps. Naming "Searching… Reading… Writing…"
/// would be theatre — the pipeline usually completes in well under a second,
/// and invented progress is a small lie the rest of this app does not tell.
class ThinkingIndicator extends StatefulWidget {
  const ThinkingIndicator({this.label = 'Reading your documents', super.key});

  final String label;

  @override
  State<ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // `disableAnimations` covers the accessibility setting and the widget
    // tests, both of which want a static indicator rather than a ticker that
    // never settles.
    final animate = !MediaQuery.of(context).disableAnimations;

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(4),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: animate
                  ? AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          for (var i = 0; i < 3; i++)
                            _Dot(
                              colour: theme.colorScheme.onSurfaceVariant,
                              // Each dot lags the one before it by a third of
                              // the cycle, so the row reads as a wave rather
                              // than a flash.
                              progress: (_controller.value + i / 3) % 1,
                            ),
                        ],
                      ),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        for (var i = 0; i < 3; i++)
                          _Dot(
                            colour: theme.colorScheme.onSurfaceVariant,
                            progress: 0.5,
                          ),
                      ],
                    ),
            ),
            const SizedBox(width: 12),
            Text(
              widget.label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.colour, required this.progress});

  final Color colour;

  /// 0–1 through this dot's own cycle.
  final double progress;

  @override
  Widget build(BuildContext context) {
    // A single rise and fall across the cycle, so the dot returns to where it
    // started and the loop has no visible seam.
    final lift = (progress < 0.5 ? progress : 1 - progress) * 2;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2.5),
      child: Transform.translate(
        offset: Offset(0, -3 * lift),
        child: Opacity(
          opacity: 0.45 + 0.55 * lift,
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}
