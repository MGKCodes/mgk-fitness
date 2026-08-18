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
    this.valueWeight,
    this.shrinkToFit = false,
  });

  final String label;
  final String value;
  final StatSize size;
  final CrossAxisAlignment align;

  /// Overrides the weight [size] implies.
  ///
  /// Exists so a screen can set its own hierarchy without moving the scale for
  /// every other screen: a readout sitting under a hero numeral wants to be
  /// quieter than the same stat standing alone, because a bold supporting row
  /// out-shouts a thin 96pt figure and inverts the thing the layout is saying.
  final FontWeight? valueWeight;

  /// Scales the value down rather than letting it clip.
  ///
  /// Off by default, because shrinking is a lie about the type scale and most
  /// stats have room. On where the value is unbounded and the column is not —
  /// an elapsed time crossing an hour gains two characters, and a `Text` in a
  /// tight `Expanded` clips it **silently** (there is no overflow stripe inside
  /// a bounded box), so the run would simply appear to lose its hours.
  final bool shrinkToFit;

  /// Overrides the value colour — for a stat that signals status (on target,
  /// over limit), the only sanctioned use of colour (ADR-0009).
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _shrink(
          SectionLabel(
            label,
            emphasis: size.labelEmphasis,
            textAlign: align == CrossAxisAlignment.center
                ? TextAlign.center
                : null,
          ),
        ),
        SizedBox(height: size.gap),
        _value(),
      ],
    );
  }

  Widget _value() {
    final text = Text(
      value,
      maxLines: 1,
      softWrap: false,
      textAlign: align == CrossAxisAlignment.center ? TextAlign.center : null,
      style: TextStyle(
        color: valueColor ?? AppColors.textPrimary,
        fontSize: size.valueSize,
        fontWeight: valueWeight ?? size.valueWeight,
        height: 1.1,
        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
    return _shrink(text);
  }

  /// Scales a child down to fit rather than letting it overflow.
  ///
  /// Applied to the **label as well as the value**. Guarding only the number
  /// missed the narrower half of the problem: a label carrying its unit —
  /// `PACE /KM`, letterspaced — is wider than the figure under it, and three of
  /// them across a 320pt screen overflowed by 10px while every value fitted.
  Widget _shrink(Widget child) {
    if (!shrinkToFit) return child;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: align == CrossAxisAlignment.center
          ? Alignment.center
          : Alignment.centerLeft,
      child: child,
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
