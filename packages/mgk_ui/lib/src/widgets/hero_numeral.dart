import 'package:flutter/material.dart';

import '../motion/app_motion.dart';
import '../motion/count_up.dart';
import '../theme/app_colors.dart';
import 'section_label.dart';

/// The one number a screen exists to show: label above, huge thin numeral,
/// unit beside it.
///
/// This package's README has always specified a hero numeral at "Thin, 120–150"
/// and nothing implemented it — the largest thing available was
/// `StatSize.display` at 44, so the in-run distance, the number a runner reads
/// at arm's length while moving, was rendered at the size of a summary tile.
/// With no accent colour, the numerals *are* the interface (ADR-0009), and the
/// hero one was the size of a supporting figure.
///
/// Value and unit are separate rather than one formatted string, because at
/// this size `3.42 km` sets the unit in 112pt too and the number stops being
/// the thing you see. The caller still formats through the unit layer as usual.
class HeroNumeral extends StatelessWidget {
  const HeroNumeral({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    this.format = _twoPlaces,
    this.animate = true,
    this.size = 112,
    this.weight = FontWeight.w100,
    this.letterSpacing = -2,
  });

  /// The eyebrow: `DISTANCE`, `TOTAL`.
  final String label;

  /// The magnitude, already converted to [unit] by the caller.
  final double value;

  /// `km`, `mi` — set small beside the numeral, never scaled with it.
  final String unit;

  final String Function(double value) format;

  /// Counts up on first appearance and tweens between values afterwards, which
  /// is what ADR-0009 asks a hero numeral to do. Off for a value that is not
  /// live, where motion would be decoration.
  final bool animate;

  /// The target size. Shrinks to fit rather than overflowing — a run past
  /// 100 km, or an accessibility text scale, must not clip the one number the
  /// screen is for.
  final double size;

  /// How heavy the numeral is drawn.
  ///
  /// All eight Inter faces ship with the package, so every step here is a real
  /// cut rather than a synthetic one. Thin is the README's default and reads as
  /// premium at 112pt on a flat ground — but the decimal point is the thing to
  /// watch when changing it, because a `w100` period is a speck sitting in a
  /// full digit-width tabular cell, and at a glance `0.45` can read as two
  /// numbers rather than one.
  final FontWeight weight;

  /// Tracking. Negative tightens.
  ///
  /// Worth pairing with [weight]: the digits close up but the decimal point
  /// keeps its full tabular cell, so tightening the figures without adding mass
  /// to the point is what makes `0.45` separate into two numbers.
  final double letterSpacing;

  static String _twoPlaces(double value) => value.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: AppColors.textPrimary,
      fontSize: size,
      // Thin by default, per the README. At this scale weight reads as
      // shouting, and the design language is premium rather than loud.
      fontWeight: weight,
      height: 1,
      letterSpacing: letterSpacing,
      // A ticking figure must not shift the layout under it.
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SectionLabel(
          label,
          emphasis: LabelEmphasis.hero,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: <Widget>[
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: animate
                    ? CountUp(
                        value: value,
                        format: format,
                        duration: AppMotion.slow,
                        style: style,
                      )
                    : Text(format(value), style: style),
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              // Optically aligned to the numeral's baseline rather than its
              // box: a 112pt thin figure has a lot of air under it.
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                unit,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: (size * 0.16).clamp(12, 22),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
