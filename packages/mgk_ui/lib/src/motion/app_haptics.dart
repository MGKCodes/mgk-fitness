import 'dart:async';

import 'package:flutter/services.dart';

/// Haptics named by **occasion**, so the same kind of event feels the same
/// everywhere in the suite.
///
/// The companion to [AppMotion], and built for the same reason: without a
/// shared vocabulary every screen picks its own `lightImpact` or
/// `mediumImpact`, and the app feels assembled rather than designed. Callers
/// should never reach for `HapticFeedback` directly — ask for the *occasion*
/// and let this decide how it feels.
///
/// ## The rule that keeps this from becoming noise
///
/// **Never fire a haptic the person did not cause, unless they cannot look.**
///
/// That single line does most of the work. A buzz for something you just tapped
/// is confirmation; a buzz for something that happened on its own is an
/// interruption, and an app that interrupts stops being trusted in a pocket.
/// The exception earns its place on exactly one surface: a runner mid-stride
/// cannot read a screen, so a kilometre ticking over or a signal dropping are
/// things they genuinely need told without looking. Everywhere else, a haptic
/// answers a finger.
///
/// ## Notes
///
/// Fire-and-forget by design — every call returns a future that callers are
/// free to drop, and none of them should ever be awaited on a frame boundary.
///
/// The platforms are not equally expressive. iOS maps these onto
/// `UIFeedbackGenerator` and respects the system haptics setting for free;
/// Android's are coarser and some OEM builds collapse the lighter ones to
/// nothing at all. Design so the haptic is a *reinforcement* of something
/// visible, never the only channel carrying the message.
abstract final class AppHaptics {
  /// A control acknowledging a finger. The lightest thing here, and by far the
  /// most common — see [PressScale], which fires it on press.
  static Future<void> tap() => HapticFeedback.selectionClick();

  /// A choice moved: a segment changing, a sheet snapping to a detent, a value
  /// stepping. Distinct from [tap] in meaning, identical in feel on purpose —
  /// the *event* is worth naming even where the platform gives one texture.
  static Future<void> selection() => HapticFeedback.selectionClick();

  /// Something committed that the person meant to commit: a run finished, a set
  /// logged, a plan accepted. Heavier than a tap because it is the end of
  /// something rather than the acknowledgement of a touch.
  static Future<void> commit() => HapticFeedback.mediumImpact();

  /// The exception to the rule: something the app did on its own that the
  /// person needs to know **without looking**.
  ///
  /// A kilometre ticking over on a run is the case this exists for. Reserve it
  /// for surfaces where the eyes are genuinely elsewhere; on a screen somebody
  /// is looking at, this is an interruption wearing a useful hat.
  static Future<void> milestone() => HapticFeedback.mediumImpact();

  /// Something has gone wrong, or stopped working, and carrying on as though it
  /// had not would mislead. The heaviest, and the rarest.
  static Future<void> problem() => HapticFeedback.heavyImpact();
}
