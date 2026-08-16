import 'package:flutter/material.dart';

/// Fades its child in and out, forever, while [active].
///
/// The suite's one "this is live" signal. There is no accent colour to reach
/// for (ADR-0009), so a live state is expressed as motion — a recording dot, a
/// syncing marker, a session in progress.
///
/// It stops when [active] goes false rather than running under a paused state,
/// which matters for more than tidiness: an always-repeating controller never
/// settles, so it burns a ticker for something nobody is watching move and
/// hangs any `pumpAndSettle` that reaches the screen. That is a real bug the
/// in-run status pill shipped with, and the reason this is a component.
class Pulse extends StatefulWidget {
  const Pulse({
    super.key,
    required this.child,
    this.active = true,
    this.period = const Duration(milliseconds: 900),
    this.min = 0.25,
    this.max = 1,
    this.restingOpacity = 0.4,
  });

  final Widget child;

  /// Whether the thing being marked is actually live.
  final bool active;

  final Duration period;

  /// The range the opacity travels while active.
  final double min;
  final double max;

  /// Held when inactive — dimmed, so a stopped state still reads as present
  /// rather than disappearing.
  final double restingOpacity;

  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Vestibular disorders make motion a genuine barrier, and a thing that
    // never stops flashing is the worst version of it. Honoured here rather
    // than at each call site.
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(Pulse old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  void _sync() {
    if (widget.active && !_reduceMotion) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active || _reduceMotion) {
      return Opacity(
        opacity: widget.active ? widget.max : widget.restingOpacity,
        child: widget.child,
      );
    }
    return FadeTransition(
      opacity: Tween<double>(
        begin: widget.min,
        end: widget.max,
      ).animate(_controller),
      child: widget.child,
    );
  }
}
