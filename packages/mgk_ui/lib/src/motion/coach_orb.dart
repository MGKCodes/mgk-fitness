import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The coach, waiting to speak: a small orb of light that breathes.
///
/// **Both apps' coaches wait this way** (4 October 2026: "orb animations, not
/// the standard three dots"). Three dots are every chat app's; a coach that is
/// one product across two apps should have a wait of its own, and the same one
/// in each.
///
/// Built from the suite's greys (ADR-0009): a sphere lit from the upper left,
/// white falling to silver and into the elevated grey, with a soft light round
/// it that swells and settles as the orb does. No colour, so it reads on any of
/// the backdrops a conversation sits over.
///
/// Held still under Reduce Motion, at the middle of its breath: still visibly
/// the coach, without the movement.
class CoachOrb extends StatefulWidget {
  const CoachOrb({super.key, this.size = 18});

  /// The orb's diameter. Its light reaches past this, so the widget takes a
  /// little more room than [size] on every side.
  final double size;

  @override
  State<CoachOrb> createState() => _CoachOrbState();
}

class _CoachOrbState extends State<CoachOrb>
    with SingleTickerProviderStateMixin {
  /// One breath: in and out over this, eased at both ends.
  static const Duration _breath = Duration(milliseconds: 1600);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _breath,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _controller
        ..stop()
        ..value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return Semantics(
      label: 'The coach is thinking',
      child: SizedBox.square(
        dimension: size * 1.6,
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = Curves.easeInOut.transform(_controller.value);
              return Transform.scale(
                scale: 0.84 + 0.16 * t,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      center: Alignment(-0.35, -0.4),
                      radius: 0.95,
                      colors: <Color>[
                        AppColors.textPrimary,
                        Color(0xFFC0C0C0),
                        AppColors.elevated,
                      ],
                      stops: <double>[0, 0.5, 1],
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: AppColors.textPrimary.withValues(
                          alpha: 0.12 + 0.2 * t,
                        ),
                        blurRadius: size * (0.5 + 0.5 * t),
                        spreadRadius: size * 0.04,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
