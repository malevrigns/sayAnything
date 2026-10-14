import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Fade through the global background instead of sliding/scaling glass pages.
/// The outgoing page finishes fading before the incoming page is painted.
class QuietPageTransitionsBuilder extends PageTransitionsBuilder {
  final bool reduceMotion;
  const QuietPageTransitionsBuilder({this.reduceMotion = false});
  @override
  Duration get transitionDuration =>
      reduceMotion ? Duration.zero : const Duration(milliseconds: 160);
  @override
  Duration get reverseTransitionDuration => transitionDuration;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (reduceMotion || MediaQuery.disableAnimationsOf(context)) return child;
    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      child: child,
      builder: (context, child) {
        final enter = route.isFirst
            ? 1.0
            : const Interval(
                .35,
                1,
                curve: Curves.easeOutCubic,
              ).transform(animation.value);
        final leave =
            1 -
            const Interval(
              0,
              .35,
              curve: Curves.easeInQuad,
            ).transform(secondaryAnimation.value);
        final opacity = math.min(enter, leave).clamp(0.0, 1.0);
        return IgnorePointer(
          ignoring: !route.isCurrent || opacity < .05,
          child: Opacity(opacity: opacity, child: child),
        );
      },
    );
  }
}
