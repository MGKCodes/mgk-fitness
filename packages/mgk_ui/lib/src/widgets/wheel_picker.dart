import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
/// ## Cupertino underneath, this design language on top
///
/// The drum is a [CupertinoPicker] rather than a hand-rolled
/// [ListWheelScrollView], because the parts worth having are the parts that are
/// tedious to reproduce: the deceleration curve, the snap, and the **selection
/// haptic on every value it passes**. A wheel without that tick feels like a
/// list; with it, it feels like a dial. None of it is visual, which is why
/// building the widget from scratch got everything except the thing that
/// mattered.
///
/// What is NOT taken is the look. `selectionOverlay` is this system's card, not
/// Cupertino's grey bars, and `useMagnifier` is off — the lens is iOS chrome
/// and this palette has none to match it.
///
/// **The haptic is platform-split on purpose.** CupertinoPicker only calls
/// [HapticFeedback.selectionClick] on iOS, so Android gets nothing unless it is
/// added — and adding it unconditionally would fire twice per value on iOS.
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
        const SizedBox(height: 6),
        // Carded to match a bubble, because that is what it sits among. Bare,
        // the drum was a column of numbers floating on the glass with a
        // selection band and two hard-edged fades, and it read as an unfinished
        // control rather than as the coach's half of the conversation.
        Container(
          height: WheelPicker._height,
          decoration: BoxDecoration(
            color: AppColors.elevated.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.elevated),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              // The selection band, behind the numbers. A wheel with no band
              // makes the reader work out which row counts from the fact that
              // it is slightly larger, which is a lot to ask at a glance.
              Container(
                height: WheelPicker._itemExtent,
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.70),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
              ),
              CupertinoPicker.builder(
                scrollController: _controller,
                itemExtent: WheelPicker._itemExtent,
                // The lens is iOS chrome, and this palette has nothing to match
                // it with. The selection band does the same job flat.
                useMagnifier: false,
                magnification: 1,
                squeeze: 1,
                backgroundColor: const Color(0x00000000),
                // The default is a pair of grey hairlines. The band behind the
                // numbers is already the selection, so this would be a second
                // one drawn in another design system's voice.
                selectionOverlay: const SizedBox.shrink(),
                onSelectedItemChanged: (i) {
                  setState(() => _value = widget.min + i);
                  // iOS already ticked inside CupertinoPicker. Doing it here as
                  // well is a double tap per value, which reads as a stutter
                  // rather than a dial.
                  if (defaultTargetPlatform != TargetPlatform.iOS) {
                    unawaited(HapticFeedback.selectionClick());
                  }
                  widget.onChanged(_value);
                },
                childCount: count,
                itemBuilder: (context, i) {
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
                        // The column is a list of numbers being scrolled past.
                        // Without tabular figures each row sits at a slightly
                        // different width and the drum wobbles.
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  );
                },
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
        // The CARD's fill, not the page base. Fading to `bg` over glass drew
        // two opaque charcoal bands across a translucent panel, which is the
        // one thing on this sheet that looked like it had been forgotten.
        colors: <Color>[
          AppColors.elevated,
          AppColors.elevated.withValues(alpha: 0),
          AppColors.elevated.withValues(alpha: 0),
          AppColors.elevated,
        ],
        stops: const <double>[0, 0.28, 0.72, 1],
      ),
    ),
    child: const SizedBox.expand(),
  );
}
