import 'dart:math' as math;

import 'package:flutter/animation.dart';

/// Durations and curves, so motion across the suite reads as one hand.
///
/// ADR-0009 makes motion first-class rather than a polish pass. Without a shared
/// vocabulary every screen picks its own 200ms/300ms and its own curve, and the
/// app feels assembled rather than designed — the same drift the colour and
/// radius tokens exist to prevent.
abstract final class AppMotion {
  /// A control acknowledging a tap. Fast enough to feel instant.
  static const Duration fast = Duration(milliseconds: 140);

  /// The default: content entering, a card changing state.
  static const Duration base = Duration(milliseconds: 260);

  /// A full screen or a hero element settling.
  static const Duration slow = Duration(milliseconds: 420);

  /// Content arriving. Decelerating — it flies in and settles, never bounces.
  static const Curve entrance = Curves.easeOutCubic;

  /// Content leaving, which should get out of the way promptly.
  static const Curve exit = Curves.easeInCubic;

  /// State changes within a control.
  static const Curve standard = Curves.easeInOut;

  /// The gap between successive items in a staggered list.
  ///
  /// Deliberately short: the point is a sense of the list assembling itself, not
  /// a queue the user waits on. Ten rows finish within [slow].
  static const Duration stagger = Duration(milliseconds: 40);

  /// Beyond this many items a stagger stops reading as choreography and starts
  /// reading as lag, so later items simply arrive together.
  static const int maxStaggered = 8;

  /// A spring that answers at once and settles with the smallest overshoot —
  /// a button coming back up, a tick landing, the dock changing shape. Run it
  /// over [base]; over [fast] there is no room for the settle to be felt.
  static const Curve snappy = SpringCurve(damping: 0.7, frequency: 13);

  /// A softer spring, for bigger things arriving — a sheet, a card taking its
  /// place. Over [slow].
  static const Curve gentle = SpringCurve(damping: 0.84, frequency: 9);
}

/// A damped spring as a [Curve], for the implicit animations that take a
/// curve rather than a simulation.
///
/// Curves stay for fades and entrances, where an overshoot would read as a
/// wobble. Springs are for things the finger moved: they carry a little of
/// the motion past where they stop and come back, which is what makes a
/// control feel physical rather than tweened.
///
/// [damping] is the ratio (1 is critical, no overshoot); [frequency] is the
/// natural frequency in radians per unit of the animation, which decides how
/// much of the duration the settle takes.
class SpringCurve extends Curve {
  const SpringCurve({this.damping = 0.75, this.frequency = 12});

  final double damping;
  final double frequency;

  @override
  double transformInternal(double t) {
    final z = damping;
    final w = frequency;
    if (z >= 1) return 1 - math.exp(-w * t) * (1 + w * t);
    final wd = w * math.sqrt(1 - z * z);
    return 1 -
        math.exp(-z * w * t) *
            (math.cos(wd * t) + (z * w / wd) * math.sin(wd * t));
  }
}
