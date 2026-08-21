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
  /// premium at 112pt on a flat ground, but it does not survive being read at
  /// arm's length while moving: the in-run screen sets `w300`, picked off a
  /// side-by-side plate (`?screen=hero-weights`) as the lightest cut that still
  /// holds outdoors. Treat this default as the showcase value, not the
  /// legibility one.
  final FontWeight weight;

  /// Tracking. Negative tightens.
  final double letterSpacing;

  static String _twoPlaces(double value) => value.toStringAsFixed(2);

  /// Digits keep tabular figures; everything between them does not.
  ///
  /// Tabular figures exist so that a *ticking digit* cannot shift the layout
  /// under it — 1 must occupy what 8 occupies. A separator never ticks: there
  /// is always exactly one decimal point, and always the same thousands comma.
  /// The feature nonetheless hands each of them a full digit-width cell, and
  /// that gap is what makes `0.45` read as two numbers with a speck between
  /// them — the effect blamed on weight, which weight can only ever mask by
  /// drawing a bigger speck in the same oversized cell.
  ///
  /// Splitting the run fixes the cause: the digits stay locked to their grid,
  /// the point closes up to its natural width, and nothing that varies has been
  /// allowed to move.
  static List<TextSpan> _spans(String text, TextStyle style) {
    final TextStyle proportional = style.copyWith(
      fontFeatures: const <FontFeature>[],
    );

    final List<TextSpan> spans = <TextSpan>[];
    final StringBuffer run = StringBuffer();
    bool? runIsDigits;

    void flush() {
      if (run.isEmpty) return;
      spans.add(
        TextSpan(
          text: run.toString(),
          style: runIsDigits! ? style : proportional,
        ),
      );
      run.clear();
    }

    for (final int rune in text.runes) {
      final bool isDigit = rune >= 0x30 && rune <= 0x39;
      if (runIsDigits != isDigit) {
        flush();
        runIsDigits = isDigit;
      }
      run.writeCharCode(rune);
    }
    flush();

    return spans;
  }

  static Widget _numeral(String text, TextStyle style) =>
      Text.rich(TextSpan(children: _spans(text, style)));

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
      // A ticking figure must not shift the layout under it. Applied per-run by
      // [_spans], so the separators are spared the digit-width cell.
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
                        builder: _numeral,
                      )
                    : _numeral(format(value), style),
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
