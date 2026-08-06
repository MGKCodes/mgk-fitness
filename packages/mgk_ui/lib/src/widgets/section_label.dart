import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The small letter-spaced eyebrow above a section or a value —
/// `DISTANCE`, `SPLITS`, `YOUR DATA`, `TODAY · BUILD`.
///
/// It existed in twelve places with five different letter-spacings (0.2, 1.2,
/// 1.5, 2 and 3) because each screen re-derived it from the design system's
/// prose. One component means the tracking is a decision made once.
///
/// [emphasis] covers the only real variation: a label sitting directly above a
/// value wants to recede, while a label heading a whole section carries more
/// weight.
class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.text, {
    super.key,
    this.emphasis = LabelEmphasis.section,
    this.color,
    this.textAlign,
  });

  final String text;
  final LabelEmphasis emphasis;

  /// Overrides the colour — for a label that has to signal status, which is the
  /// only sanctioned reason to leave greyscale (ADR-0009).
  final Color? color;

  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      textAlign: textAlign,
      style: TextStyle(
        color: color ?? AppColors.textSecondary,
        fontSize: emphasis.fontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: emphasis.letterSpacing,
        height: 1.2,
      ),
    );
  }
}

/// How much presence an eyebrow label has.
enum LabelEmphasis {
  /// Heads a section of the screen. The default.
  section(fontSize: 11, letterSpacing: 1.2),

  /// Sits directly above a value, where the number is the hero and the label
  /// should not compete with it.
  stat(fontSize: 11, letterSpacing: 1.5),

  /// Full-width, widely tracked — a readout taken in at a glance mid-activity,
  /// where air between letters is what makes it legible.
  hero(fontSize: 12, letterSpacing: 3);

  const LabelEmphasis({required this.fontSize, required this.letterSpacing});

  final double fontSize;
  final double letterSpacing;
}
