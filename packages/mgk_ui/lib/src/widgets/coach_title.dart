import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';

/// "[app icon] Coach": the heading over a conversation with the coach.
///
/// **The same heading in both apps, with each app's own icon** (4 October
/// 2026). The two apps look alike on purpose, and the icon is what says which
/// one this coach is in; the word is the same in both, where Run said "Your
/// coach" and Lift "Coach".
///
/// A title rather than an eyebrow: it names what the sheet is, and the icon
/// beside it needs words at its own weight to read as one mark.
class CoachTitle extends StatelessWidget {
  const CoachTitle({super.key, required this.icon, this.size = 26});

  /// The app's icon, as it is on the home screen.
  final ImageProvider icon;

  final double size;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.225);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // The edge the sign-in's icon has: both icons are dark squares, and
        // on a dark sheet the square is otherwise lost.
        DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: const Color(0x2EFFFFFF), width: 0.8),
          ),
          child: ClipRRect(
            borderRadius: radius,
            child: Image(
              image: icon,
              width: size,
              height: size,
              excludeFromSemantics: true,
              // An icon that will not load leaves its square, not an error
              // printed across the heading.
              errorBuilder: (_, _, _) => SizedBox.square(dimension: size),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          'Coach',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
