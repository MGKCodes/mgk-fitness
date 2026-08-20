import 'dart:async';

import 'package:flutter/material.dart';

import 'app_haptics.dart';
import 'app_motion.dart';

/// Shrinks its child a little while it is held down.
///
/// The cheapest possible thing that makes an interface feel built rather than
/// rendered: a control that acknowledges the finger before the action happens.
/// Material's ink ripple is the platform's answer and it is the wrong one here
/// — a spreading grey circle on a greyscale surface reads as a smudge, and the
/// suite's language is a thing settling rather than a thing splashing.
///
/// Wraps anything tappable, including widgets with their own gesture handling:
/// this only listens, it never consumes.
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.onTap,
    this.scale = 0.97,
    this.enabled = true,
    this.haptic = true,
  });

  final Widget child;

  /// Optional. Leave null when the child already handles its own tap and this
  /// is only here for the feel.
  final VoidCallback? onTap;

  /// Whether pressing also ticks.
  ///
  /// On by default, because this widget already exists to make a control
  /// acknowledge the finger and the tick is the other half of that. Turn it off
  /// where a press is not really a press — a row that scrolls as often as it is
  /// tapped, or a surface holding many of these at once, where every drag would
  /// stutter its way across the screen.
  final bool haptic;

  /// How far it shrinks. Small on purpose — felt, not watched.
  final double scale;

  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _down = false;

  void _set(bool down) {
    if (!widget.enabled || _down == down) return;
    setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return Listener(
      // Listener rather than GestureDetector for the press states, so a child
      // that wants the tap still gets it — the two do not fight over the arena.
      onPointerDown: (_) {
        _set(true);
        // On the way down, not on the tap: the tick is the control saying it
        // felt you, which has to happen before whatever the tap does. Dropped
        // rather than awaited — a haptic must never hold a frame.
        if (widget.haptic && widget.enabled) unawaited(AppHaptics.tap());
      },
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        behavior: HitTestBehavior.deferToChild,
        child: AnimatedScale(
          scale: _down && !reduceMotion ? widget.scale : 1,
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          child: widget.child,
        ),
      ),
    );
  }
}
