import 'package:flutter/material.dart';

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

    return Material(
      color: color ?? AppColors.surface,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(onTap: onTap, borderRadius: radius, child: content),
    );
  }
}
