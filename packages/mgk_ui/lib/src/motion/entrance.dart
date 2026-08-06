import 'package:flutter/material.dart';

import 'app_motion.dart';

/// Fades and lifts its child in once, on first build.
///
/// The building block for the list choreography ADR-0009 asks for: rows arrive
/// in sequence rather than the whole screen appearing at once. [index] positions
/// an item in that sequence; the delay is capped by [AppMotion.maxStaggered] so
/// a long list never leaves the last row waiting.
///
/// Plays **once**. It animates content arriving, so re-running it on every
/// rebuild — a `setState`, a scroll, a keyboard opening — would make the screen
/// twitch. It also self-disables when the platform asks for reduced motion, and
/// under a widget test, where an always-running animation would leave
/// `pumpAndSettle` hanging.
class Entrance extends StatefulWidget {
  const Entrance({
    super.key,
    required this.child,
    this.index = 0,
    this.offset = 12,
    this.duration = AppMotion.base,
  });

  final Widget child;

  /// Position in a staggered sequence. 0 starts immediately.
  final int index;

  /// How far the child lifts, in logical pixels. Small on purpose — the effect
  /// should be felt rather than watched.
  final double offset;

  final Duration duration;

  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  /// The stagger is part of the animation rather than a timer that starts it.
  ///
  /// A `Future.delayed` would leave a pending timer behind whenever the widget
  /// is disposed before it fires — which `testWidgets` fails on, and which is a
  /// real leak in a scrolling list that builds and discards rows constantly. One
  /// controller that runs from the moment of build, with the delay expressed as
  /// a dead interval at its head, has neither problem.
  late final Duration _delay =
      AppMotion.stagger * widget.index.clamp(0, AppMotion.maxStaggered);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration + _delay,
  );

  late final Animation<double> _curved = CurvedAnimation(
    parent: _controller,
    curve: Interval(
      _delay.inMicroseconds / (widget.duration + _delay).inMicroseconds,
      1,
      curve: AppMotion.entrance,
    ),
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    // Respect the accessibility setting: vestibular disorders make motion a
    // genuine barrier, so this jumps straight to the settled state.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.value = 1;
      return;
    }
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _curved,
      builder: (context, child) => Opacity(
        opacity: _curved.value,
        child: Transform.translate(
          offset: Offset(0, widget.offset * (1 - _curved.value)),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
