import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'section_label.dart';

/// A labelled value — the design system's **Stat**: the number is the hero, the
/// label sits quietly above it.
///
/// There were three copies of this (history totals, the in-activity readout, the
/// summary grid) differing only in tracking, weight, gap and alignment.
/// [StatSize] keeps the one real difference — how loud the number is — and drops
/// the accidental ones.
///
/// Numerals carry every screen in this design language, so the value uses
/// tabular figures: a pace ticking 5:18 → 5:19 mid-run must not shift the layout.
class StatBlock extends StatelessWidget {
  const StatBlock({
    super.key,
    required this.label,
    required this.value,
    this.size = StatSize.standard,
    this.align = CrossAxisAlignment.start,
    this.valueColor,
  });

  final String label;
  final String value;
  final StatSize size;
  final CrossAxisAlignment align;

  /// Overrides the value colour — for a stat that signals status (on target,
  /// over limit), the only sanctioned use of colour (ADR-0009).
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SectionLabel(
          label,
          emphasis: size.labelEmphasis,
          textAlign: align == CrossAxisAlignment.center
              ? TextAlign.center
              : null,
        ),
        SizedBox(height: size.gap),
        Text(
          value,
          textAlign: align == CrossAxisAlignment.center
              ? TextAlign.center
              : null,
          style: TextStyle(
            color: valueColor ?? AppColors.textPrimary,
            fontSize: size.valueSize,
            fontWeight: size.valueWeight,
            height: 1.1,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// How loud the number is.
enum StatSize {
  /// A supporting figure in a grid or a row.
  standard(
    valueSize: 22,
    valueWeight: FontWeight.w600,
    gap: 6,
    labelEmphasis: LabelEmphasis.stat,
  ),

  /// A headline total — the top of the training log.
  large(
    valueSize: 26,
    valueWeight: FontWeight.w700,
    gap: 4,
    labelEmphasis: LabelEmphasis.stat,
  ),

  /// An in-activity readout, read at arm's length while moving.
  hero(
    valueSize: 32,
    valueWeight: FontWeight.w600,
    gap: 6,
    labelEmphasis: LabelEmphasis.hero,
  ),

  /// The one number a screen is *about* — in-run distance, the working set.
  /// Numerals are the hero of this design language, so the primary metric
  /// outranks the supporting ones rather than matching them.
  display(
    valueSize: 44,
    valueWeight: FontWeight.w700,
    gap: 8,
    labelEmphasis: LabelEmphasis.hero,
  );

  const StatSize({
    required this.valueSize,
    required this.valueWeight,
    required this.gap,
    required this.labelEmphasis,
  });

  final double valueSize;
  final FontWeight valueWeight;
  final double gap;
  final LabelEmphasis labelEmphasis;
}
