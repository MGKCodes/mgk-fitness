import 'package:flutter/material.dart';

import 'app_motion.dart';

/// How routes enter and leave.
///
/// Flutter's default on iOS is a horizontal slide with the parent dimming. That
/// is Cupertino's language, not this suite's: these apps move vertically and
/// settle (see `Entrance`), and a screen that flies in from the side reads as
/// borrowed. A short rise plus a fade matches the rest of the motion vocabulary
/// and keeps the photographic backdrops from sliding across each other.
class MgkPageTransitions extends PageTransitionsBuilder {
  const MgkPageTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final entering = CurvedAnimation(
      parent: animation,
      curve: AppMotion.entrance,
      reverseCurve: AppMotion.exit,
    );

    return FadeTransition(
      opacity: entering,
      child: SlideTransition(
        position: Tween<Offset>(
          // A small rise. Enough to give direction, not so much that the screen
          // appears to be thrown.
          begin: const Offset(0, 0.035),
          end: Offset.zero,
        ).animate(entering),
        child: child,
      ),
    );
  }
}
