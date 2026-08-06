import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_radius.dart';

/// A frosted-glass panel: the content behind it is blurred, brightened and
/// tinted, with a lit edge and a sheen across the top.
///
/// **Glass only exists where there is something behind it.** Blur over a flat
/// fill is a no-op — the effect is the *distortion of texture*, so on the
/// charcoal base a glass panel is indistinguishable from a plain one, only more
/// expensive. It belongs over the signature monochrome photography and over a
/// live map, and nowhere else.
///
/// Four layers, and all four matter. Dropping any one is what makes glass read
/// as "a translucent box" rather than as a material:
///
/// 1. **Blur** — the frost itself.
/// 2. **A luminance lift** — real glass gathers light. Without it a dark photo
///    behind the panel just reads as a dark smear. This carries most of the
///    effect in a greyscale palette, where there is no saturation to boost.
/// 3. **Tint** — a top-to-bottom gradient, brighter at the top, giving the pane
///    a direction to be lit from.
/// 4. **A lit edge and sheen** — a uniform 1px border reads as a stroke around a
///    box; a *gradient* edge that catches light at the top-left and fades away
///    reads as a bevel. This is the cheapest detail and the one that sells it.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.borderRadius,
    this.blurSigma = 24,
    this.tintOpacity = 0.10,
    this.luminance = 1.16,
    this.sheen = true,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;

  /// Frost strength. Below ~12 reads as a smudge rather than glass; above ~40
  /// the backdrop stops being legible as an image at all.
  final double blurSigma;

  /// Strength of the white tint. Small numbers — past ~0.18 the pane turns milky
  /// and stops showing what is behind it, which is the whole point of glass.
  final double tintOpacity;

  /// How much the backdrop is lifted. 1.0 is untouched.
  final double luminance;

  /// Makes the whole pane tappable, with the ripple clipped to its corners.
  final VoidCallback? onTap;

  /// The highlight across the top edge. Worth turning off for a panel that sits
  /// flush against another, where two adjacent sheens read as a seam.
  final bool sheen;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? AppRadius.cardAll;

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        // Blur and lift together in one filter: composing is a single pass, and
        // brightening *after* the blur lifts the whole pane evenly rather than
        // amplifying the brightest pixels behind it into blown-out blobs.
        filter: ui.ImageFilter.compose(
          outer: ui.ColorFilter.matrix(_luminanceMatrix(luminance)),
          inner: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        ),
        child: CustomPaint(
          foregroundPainter: _GlassEdge(radius: radius),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  Colors.white.withValues(alpha: tintOpacity),
                  Colors.white.withValues(alpha: tintOpacity * 0.45),
                ],
              ),
            ),
            child: Stack(
              children: <Widget>[
                if (sheen)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: 44,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Colors.white.withValues(alpha: 0.10),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (onTap == null)
                  Padding(padding: padding, child: child)
                else
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onTap,
                      borderRadius: radius,
                      child: Padding(padding: padding, child: child),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A 5x4 colour matrix that scales RGB about their midpoint, lifting the pane
  /// without clipping highlights the way a plain multiply does.
  static List<double> _luminanceMatrix(double amount) {
    final t = (1 - amount) * 128;
    return <double>[
      amount, 0, 0, 0, t, //
      0, amount, 0, 0, t, //
      0, 0, amount, 0, t, //
      0, 0, 0, 1, 0, //
    ];
  }
}

/// Strokes the pane's edge with a gradient — bright where light would catch it,
/// gone by the opposite corner.
class _GlassEdge extends CustomPainter {
  const _GlassEdge({required this.radius});

  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect);

    // Inset by half the stroke so the line sits inside the clip rather than
    // being shaved in half by it.
    final inner = rrect.deflate(0.5);

    canvas.drawRRect(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          <Color>[
            Colors.white.withValues(alpha: 0.42),
            Colors.white.withValues(alpha: 0.10),
            Colors.white.withValues(alpha: 0.06),
          ],
          <double>[0, 0.45, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_GlassEdge oldDelegate) => oldDelegate.radius != radius;
}
