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
}
