import 'package:flutter/material.dart';

import 'app_motion.dart';

/// Counts a number up to its value when it first appears, and animates between
/// values afterwards.
///
/// ADR-0009 asks for hero numerals that count up. It matters more here than in
/// most apps: with no accent colour, the numbers *are* the interface, so giving
/// them the entrance is what makes a screen feel alive rather than printed.
///
/// [format] turns the running value into text, so this stays unit-agnostic —
/// the caller formats through the display layer as usual and nothing here has
/// an opinion about km or miles, kg or lb.
///
/// Only counts from zero on **first** appearance. A later change animates from
/// where it was, so a live value updating mid-activity tweens rather than
/// replaying from nothing every second.
class CountUp extends StatefulWidget {
  const CountUp({
    super.key,
    required this.value,
    required this.format,
    this.duration = AppMotion.slow,
    this.style,
    this.textAlign,
  });

  final double value;
  final String Function(double value) format;
  final Duration duration;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  State<CountUp> createState() => _CountUpState();
}

class _CountUpState extends State<CountUp> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  late double _from = 0;
  late double _to = widget.value;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = 1;
      return;
    }
    _controller.forward();
  }

  @override
  void didUpdateWidget(CountUp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value == _to) return;
    // Continue from wherever the last run reached, so a value that changes
    // mid-flight does not jump back to zero.
    _from = _current;
    _to = widget.value;
    _controller
      ..reset()
      ..forward();
  }

  double get _current {
    final t = Curves.easeOutCubic.transform(_controller.value);
    return _from + (_to - _from) * t;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Text(
        widget.format(_current),
        style: widget.style,
        textAlign: widget.textAlign,
      ),
    );
  }
}
