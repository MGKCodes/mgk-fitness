import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The signature treatment: a monochrome photograph at low opacity over the
/// charcoal base, under a gradient scrim that keeps text crisp.
///
/// Three layers, in order — charcoal fill, photo at ~0.25–0.34, then a scrim
/// heavier at top and bottom so the subject breathes through the middle while
/// headings and controls stay legible.
///
/// It lived inline in one screen, which meant every other surface that wanted it
/// would have re-derived the opacity and the four scrim stops by eye. With no
/// accent colour to carry the brand (ADR-0009), this treatment *is* the brand,
/// so it has to be identical everywhere it appears — across apps as well as
/// across screens.
///
/// The photography itself stays with the app: each app declares its own images
/// and passes an asset path, so `mgk_run` shows running scenes and `mgk_lift`
/// shows lifting ones while the treatment stays identical.
class PhotoBackdrop extends StatelessWidget {
  const PhotoBackdrop({
    super.key,
    required this.image,
    this.child,
    this.opacity = 0.30,
    this.scrim = ScrimStrength.balanced,
    this.alignment = Alignment.center,
    this.offset = 0,
  });

  /// Asset path, declared by the consuming app —
  /// e.g. `assets/images/backgrounds/onboarding.jpg`.
  final String image;

  final Widget? child;

  /// Photo opacity. The band is narrow on purpose: below ~0.2 the image is a
  /// rumour, above ~0.36 it competes with the content.
  final double opacity;

  final ScrimStrength scrim;
  final Alignment alignment;

  /// Vertical parallax, in logical pixels. Positive moves the photo down.
  ///
  /// Drive it from a scroll offset at a fraction of the scroll distance and the
  /// background drifts behind the content — the depth cue ADR-0009 asks for.
  final double offset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const ColoredBox(color: AppColors.bg),
        Transform.translate(
          offset: Offset(0, offset),
          child: Opacity(
            opacity: opacity,
            child: Image.asset(
              image,
              fit: BoxFit.cover,
              alignment: alignment,
              // A missing asset must never take a screen down — the content is
              // legible on the charcoal base alone.
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
        ),
        DecoratedBox(decoration: BoxDecoration(gradient: scrim.gradient)),
        ?child,
      ],
    );
  }
}

/// How hard the scrim works, which depends on what sits on top of it.
enum ScrimStrength {
  /// Heavy top and bottom, open in the middle. For a screen with a headline and
  /// a call to action at opposite ends.
  balanced(
    <Color>[
      Color(0xB81A1A1A),
      Color(0x2E1A1A1A),
      Color(0x8C1A1A1A),
      Color(0xF51A1A1A),
    ],
    <double>[0, 0.42, 0.72, 1],
  ),

  /// Weighted to the bottom, for a screen whose content stacks from the base up.
  grounded(
    <Color>[Color(0x661A1A1A), Color(0x991A1A1A), Color(0xFA1A1A1A)],
    <double>[0, 0.5, 1],
  ),

  /// Nearly opaque — the photo is texture rather than subject, for a screen of
  /// dense content that still wants the base to breathe.
  quiet(
    <Color>[Color(0xE01A1A1A), Color(0xF01A1A1A), Color(0xFD1A1A1A)],
    <double>[0, 0.55, 1],
  );

  const ScrimStrength(this.colors, this.stops);

  final List<Color> colors;
  final List<double> stops;

  LinearGradient get gradient => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: colors,
    stops: stops,
  );
}
