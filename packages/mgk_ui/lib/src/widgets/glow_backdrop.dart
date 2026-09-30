import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The charcoal base with a soft light falling into it — no photograph.
///
/// **For the screens where a photograph is noise.** Lift's design review put
/// it plainly: a photo is not needed mid-workout, and it adds noise to the
/// screen used at the rack. But the same review asked for more glass on that
/// screen's heading, and glass needs something behind it (see
/// [GlassSurface]). A flat fill gives it nothing; a photograph gives it too
/// much. A light does neither: a pane over it catches a brighter corner and a
/// darker one, which is enough to read as a material, and nothing in it
/// competes with a set being logged.
///
/// Drawn in code, so it costs no asset and scales to any screen.
class GlowBackdrop extends StatelessWidget {
  const GlowBackdrop({
    super.key,
    this.child,
    this.light = const Alignment(0.55, -1.05),
    this.intensity = 0.13,
  });

  final Widget? child;

  /// Where the light falls from. Off the top edge by default, like a lamp
  /// above the frame, so the brightest point is never behind text.
  final Alignment light;

  /// How strong the light is, as white over charcoal. Past ~0.2 the top of
  /// the screen reads as a grey panel rather than as lit.
  final double intensity;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const ColoredBox(color: AppColors.bg),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: light,
              radius: 1.25,
              colors: <Color>[
                Colors.white.withValues(alpha: intensity),
                Colors.white.withValues(alpha: intensity * 0.32),
                Colors.white.withValues(alpha: 0),
              ],
              stops: const <double>[0, 0.42, 1],
            ),
          ),
        ),
        // A second, fainter pool low on the other side, so a long list does
        // not scroll into flat charcoal the moment the top light is behind it.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-light.x, 1.1),
              radius: 1.0,
              colors: <Color>[
                Colors.white.withValues(alpha: intensity * 0.35),
                Colors.white.withValues(alpha: 0),
              ],
            ),
          ),
        ),
        ?child,
      ],
    );
  }
}
