import 'package:flutter/material.dart';

import '../motion/press_scale.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';

/// A surface panel — the design system's **Card**: `surface` fill on the
/// charcoal base, one radius.
///
/// With no accent colour to lean on, separation in this palette comes from
/// surface and space (ADR-0009), which makes the card the main structural
/// device. Before this it was rebuilt inline at every call site with radii
/// ranging from 12 to 20, so panels that sat side by side had different corners.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.color,
    this.borderRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Makes the whole card tappable, with the ripple clipped to its corners.
  final VoidCallback? onTap;

  /// Overrides the fill — for a card that has to read as elevated or as a
  /// status surface.
  final Color? color;

  /// Overrides the corner radius. Prefer the default; asymmetric corners are the
  /// legitimate case (a chat bubble's tail, a sheet's top edge).
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? AppRadius.cardAll;
    final content = Padding(padding: padding, child: child);

    final surface = Material(
      color: color ?? AppColors.surface,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(onTap: onTap, borderRadius: radius, child: content),
    );

    if (onTap == null) return surface;

    // A tappable card gets the same acknowledgement the primary button gets:
    // it settles under the finger and ticks. [PressScale] only listens — it
    // never enters the gesture arena — so the InkWell above still owns the tap
    // and keeps its semantics and its tap target.
    //
    // The ripple stays underneath deliberately. It is nearly invisible on these
    // surfaces (see PressScale's own note on why a spreading grey circle is the
    // wrong answer here), but removing it would take the platform's own
    // accessibility affordance with it for a feel this already replaces.
    return PressScale(child: surface);
  }
}
