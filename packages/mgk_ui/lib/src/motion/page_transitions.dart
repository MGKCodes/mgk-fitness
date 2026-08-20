import 'package:flutter/material.dart';

import 'app_motion.dart';

/// How routes enter and leave.
///
/// Flutter's default on iOS is a horizontal slide with the parent dimming. That
/// is Cupertino's language, not this suite's: these apps move vertically and
/// settle (see `Entrance`), and a screen that flies in from the side reads as
/// borrowed. A short rise plus a fade matches the rest of the motion vocabulary
/// and keeps the photographic backdrops from sliding across each other.
///
/// **Both directions, and both pages.** A transition involves two screens, and
/// this used to animate only one of them: `secondaryAnimation` — the page being
/// covered — was ignored, so pushing a screen left the one behind it perfectly
/// still while something slid over it, and popping did not bring it back so
/// much as uncover it. The arriving page had motion and the departing one had
/// none, which is what makes a push feel like a slide projector rather than a
/// stack.
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

    // The page being covered, or uncovered on the way back. Curved the other
    // way round from [entering]: it leaves promptly and returns by settling,
    // which is the same asymmetry AppMotion draws between exit and entrance.
    final leaving = CurvedAnimation(
      parent: secondaryAnimation,
      curve: AppMotion.exit,
      reverseCurve: AppMotion.entrance,
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
        // Continues the same upward direction rather than opposing it: new
        // content rises from below and carries the old up and out of the way,
        // so the two read as one movement instead of two screens passing.
        child: SlideTransition(
          position: Tween<Offset>(
            begin: Offset.zero,
            end: const Offset(0, -0.02),
          ).animate(leaving),
          child: FadeTransition(
            // Dimmed rather than faded out. The covered page is mostly hidden
            // on the way in, so this is really for the journey back, where it
            // should look like it is returning rather than switching on.
            opacity: Tween<double>(begin: 1, end: 0.4).animate(leaving),
            child: child,
          ),
        ),
      ),
    );
  }
}
