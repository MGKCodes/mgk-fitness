import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import 'section_label.dart';

/// A value chosen by spinning a drum, the way iOS asks for a date.
///
/// **Replaces a horizontal slider, and the difference is precision.** A slider
/// spanning 1940–2012 gives each year about four logical pixels, so choosing
/// your own birth year is a fiddle against the width of the screen. A wheel
/// gives every value the same fixed extent no matter how many there are, and
/// the neighbours stay legible either side of the choice — you can see 1993 and
/// 1995 while sitting on 1994, which is what makes it feel accurate rather than
/// approximate.
///
/// It also solves a problem the slider had quietly: a slider's thumb sits under
/// the thumb that is dragging it, so the value being chosen is the one thing
/// hidden by your own hand. A wheel is read at the centre and driven from
/// anywhere on it.
///
/// **Reduced motion is respected by the platform here**, not by this widget:
/// the drum is a scroll, and a scroll is direct manipulation rather than
/// animation, so there is nothing to disable.
class WheelPicker extends StatefulWidget {
  const WheelPicker({
    super.key,
    required this.label,
    required this.min,
    required this.max,
    required this.initial,
    required this.onChanged,
    this.format,
    this.onSkip,
    this.skipLabel = 'Prefer not to say',
  });

  final String label;
  final int min;
  final int max;
  final int initial;
  final ValueChanged<int> onChanged;

  /// How each row reads. Defaults to the bare number; pass one that carries the
  /// unit, because a column of unlabelled integers is a column somebody has to
  /// guess the meaning of.
  final String Function(int)? format;

  /// **Every one of these questions may be declined.** Age, height and weight
  /// are health data collected to build a plan, and a plan can be built without
  /// any of them — worse, but built. A control that can only be answered turns
  /// an optional disclosure into a wall, and somebody who cannot get past it
  /// either lies or leaves.
  final VoidCallback? onSkip;

  final String skipLabel;

  /// Tall enough for two neighbours either side of the choice. Fewer and the
  /// drum reads as a text field that happens to scroll; more and it takes the
  /// conversation's room.
  static const double _itemExtent = 44;
  static const double _height = _itemExtent * 5;

  @override
  State<WheelPicker> createState() => _WheelPickerState();
}

class _WheelPickerState extends State<WheelPicker> {
  late final FixedExtentScrollController _controller =
      FixedExtentScrollController(initialItem: widget.initial - widget.min);

  late int _value = widget.initial;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = widget.max - widget.min + 1;
    final format = widget.format ?? (int v) => '$v';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SectionLabel(widget.label),
        SizedBox(
          height: WheelPicker._height,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              // The selection band, behind the numbers. A wheel with no band
              // makes the reader work out which row counts from the fact that
              // it is slightly larger, which is a lot to ask at a glance.
              Container(
                height: WheelPicker._itemExtent,
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
              ),
              ListWheelScrollView.useDelegate(
                controller: _controller,
                itemExtent: WheelPicker._itemExtent,
                // Flat rather than the default barrel. A pronounced curve is
                // iOS chrome; this design language has no chrome to match, and
                // the tilt makes the neighbours harder to read for no gain.
                diameterRatio: 100,
                perspective: 0.002,
                physics: const FixedExtentScrollPhysics(),
                onSelectedItemChanged: (i) {
                  setState(() => _value = widget.min + i);
                  widget.onChanged(_value);
                },
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: count,
                  builder: (context, i) {
                    final v = widget.min + i;
                    final selected = v == _value;
                    return Center(
                      child: Text(
                        format(v),
                        style: TextStyle(
                          color: selected
                              ? AppColors.textPrimary
                              : AppColors.textTertiary,
                          fontSize: selected ? 26 : 20,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          height: 1.1,
                          // The column is a list of numbers being scrolled
                          // past. Without tabular figures each row sits at a
                          // slightly different width and the drum wobbles.
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Fades top and bottom, so values run out of the drum rather than
              // stopping at a hard edge.
              const IgnorePointer(child: _WheelFade()),
            ],
          ),
        ),
        if (widget.onSkip != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: widget.onSkip,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textTertiary,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(widget.skipLabel, style: theme.textTheme.bodySmall),
            ),
          ),
      ],
    );
  }
}

class _WheelFade extends StatelessWidget {
  const _WheelFade();

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          AppColors.bg,
          AppColors.bg.withValues(alpha: 0),
          AppColors.bg.withValues(alpha: 0),
          AppColors.bg,
        ],
        stops: const <double>[0, 0.28, 0.72, 1],
      ),
    ),
    child: const SizedBox.expand(),
  );
}
