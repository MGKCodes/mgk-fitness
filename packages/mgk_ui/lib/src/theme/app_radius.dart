import 'package:flutter/rendering.dart';

/// Corner radii, as a scale rather than a number per call site.
///
/// The design system specifies ~16 for controls and ~18–22 for cards, but
/// before this existed the screens had drifted across 3, 4, 12, 14, 16, 18 and
/// 20 — each author picking a plausible value. A scale makes the documented
/// system enforceable instead of aspirational.
abstract final class AppRadius {
  /// Small chips, tags and inline markers.
  static const double chip = 12;

  /// Buttons, inputs and other controls.
  static const double control = 16;

  /// Cards and panels — the top of the documented 18–22 band, kept at its floor
  /// so cards read as calm rather than pill-like.
  static const double card = 18;

  /// Sheets and modals, which want a softer edge than a card.
  static const double sheet = 20;

  /// Fully rounded ends. Large rather than computed, so it does not need the
  /// height it is applied to — the corner clamps at half the shorter side.
  ///
  /// Deliberately the one radius the scale does not moderate: a pill is a
  /// shape, not a softness, and picking 28 or 32 by eye is how the drift this
  /// class exists to stop begins again.
  static const double pill = 999;

  static const BorderRadius chipAll = BorderRadius.all(Radius.circular(chip));
  static const BorderRadius controlAll = BorderRadius.all(
    Radius.circular(control),
  );
  static const BorderRadius cardAll = BorderRadius.all(Radius.circular(card));
}

/// Spacing steps, so gaps are chosen from a scale rather than by eye.
///
/// A 4-point base: everything in the UI is a multiple, which is what makes
/// unrelated screens — and unrelated apps — feel like one product.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 32;
}
