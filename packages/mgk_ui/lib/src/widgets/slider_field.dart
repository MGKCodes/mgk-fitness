import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import 'section_label.dart';

/// A number chosen by dragging, with the value as the hero.
///
/// **A slider rather than a text field, because none of these are typed.** A
/// height, a weight and a year of birth are all things somebody knows
/// approximately and adjusts until it looks right — and a keyboard over a
/// conversation is the single most expensive thing you can put in front of a
/// person who has not yet decided the app is worth the effort.
///
/// The value uses tabular figures and sits at [StatBlock] weight on purpose:
/// numerals are the hero of this design language, and the number being dragged
/// is the whole content of the control. The label above it is the same
/// [SectionLabel] every other stat carries, so this reads as one of them rather
/// than as a form input that wandered in.
///
/// Skipping is a first-class outcome, not a cancel. See [onSkip].
class SliderField extends StatelessWidget {
  const SliderField({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.format,
    this.divisions,
    this.onSkip,
    this.skipLabel = 'Prefer not to say',
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  /// How the number reads. Defaults to a plain integer; pass one that carries
  /// the unit, because a number with no unit is a number somebody has to guess
  /// at — and guessing wrong about a height is how 180 becomes a shoe size.
  final String Function(double)? format;

  final int? divisions;

  /// **Every one of these questions may be declined.** Age, height and weight
  /// are health data collected to build a plan, and a plan can be built without
  /// any of them — worse, but built. A control that can only be answered turns
  /// an optional disclosure into a wall, and somebody who cannot get past it
  /// either lies or leaves.
  ///
  /// Null hides the affordance, for the rare field that genuinely has no
  /// meaningful absent state.
  final VoidCallback? onSkip;

  final String skipLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = (format ?? (v) => v.round().toString())(value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SectionLabel(label),
        const SizedBox(height: 4),
        Text(
          text,
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 34,
            fontWeight: FontWeight.w700,
            height: 1.05,
            // The number changes under a moving thumb. Without tabular figures
            // the whole row shifts sideways as digits swap width, which reads
            // as the control fighting the drag.
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 3,
            activeTrackColor: AppColors.textPrimary,
            inactiveTrackColor: AppColors.elevated,
            thumbColor: AppColors.textPrimary,
            overlayColor: AppColors.textPrimary.withValues(alpha: 0.10),
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 22),
            showValueIndicator: ShowValueIndicator.never,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
        if (onSkip != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onSkip,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textTertiary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(skipLabel, style: theme.textTheme.bodySmall),
            ),
          ),
      ],
    );
  }
}

/// The options the coach offered, one per row.
///
/// Replaces the wrapping chip row. Wrapped, five options broke three-and-two
/// with a hole under the first row, and each one was a different width — so the
/// eye had to find every target separately instead of running down a column.
///
/// **One per row, full width, in the order the coach offered them.** That order
/// is meaningful: the coach puts the likeliest first, and a Wrap reflows it by
/// string length, which quietly reorders the recommendation by how long its
/// words are.
class OptionStack extends StatelessWidget {
  const OptionStack({
    super.key,
    required this.options,
    required this.onSelected,
    this.dense = false,
  });

  final List<String> options;

  /// Given the exact text that was offered — the caller sends that, not a
  /// paraphrase, or the transcript stops matching what was said.
  final ValueChanged<String> onSelected;

  /// Tighter rows, for a stack that has to share the screen with a slider.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final o in options)
          Padding(
            padding: EdgeInsets.only(top: dense ? 6 : 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSelected(o),
                borderRadius: BorderRadius.circular(AppRadius.control),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: dense ? 11 : 14,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.control),
                    border: Border.all(color: AppColors.elevated),
                    // A fill as well as an edge. Over glass an outline alone
                    // loses its bottom half against a bright patch of the photo
                    // behind it, and the row stops looking tappable.
                    color: AppColors.surface.withValues(alpha: 0.55),
                  ),
                  child: Text(
                    o,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
