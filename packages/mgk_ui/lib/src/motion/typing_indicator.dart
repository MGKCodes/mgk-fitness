import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';

/// Three dots rising in sequence, in a bubble on the coach's side.
///
/// Distinct from `ThinkingIndicator`, and both are right for different waits.
/// `ThinkingIndicator` says "Thinking…" and is for a real model call, where the
/// wait is unbounded and honesty about it matters. This one is for a *scripted*
/// beat — the intro conversation, where the coach's next line is already
/// written and the pause exists purely so the exchange reads as a conversation
/// rather than a form that printed itself.
///
/// Using words for the scripted case would be the app claiming to think when it
/// is not; using dots for the real case would understate a wait that can run to
/// seconds. So: dots for a beat, words for a wait.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key, this.dotCount = 3});

  final int dotCount;

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  bool _reduceMotion = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!_reduceMotion && !_controller.isAnimating) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Each dot runs the same curve, offset along the cycle, so the three read as
  /// one gesture travelling rather than three things blinking.
  double _lift(int index) {
    if (_reduceMotion) return 0;
    final offset = index / (widget.dotCount * 2);
    final t = (_controller.value - offset) % 1.0;
    // A short rise and fall, then rest — the resting tail is what stops it
    // looking like a metronome.
    if (t > 0.4) return 0;
    return Curves.easeInOut.transform(1 - (t / 0.2 - 1).abs().clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.elevated,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 14,
            ),
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (var i = 0; i < widget.dotCount; i++) ...<Widget>[
                    if (i > 0) const SizedBox(width: 5),
                    Transform.translate(
                      offset: Offset(0, -3 * _lift(i)),
                      child: Opacity(
                        opacity: 0.45 + 0.55 * _lift(i),
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: AppColors.textSecondary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
