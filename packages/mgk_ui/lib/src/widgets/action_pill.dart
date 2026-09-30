import 'package:flutter/material.dart';

import '../motion/press_scale.dart';
import '../theme/app_colors.dart';
import '../theme/app_radius.dart';

/// The one action a front page exists for, drawn as the references draw it: a
/// tall silver pill with the verb on the left and an arrow in a dark disc on
/// the right, anchored low where a thumb rests.
///
/// **Louder than [PrimaryButton] on purpose, and rarer.** A primary button is
/// the screen's main action; this is the *app's* main action, on the screen
/// people open to do it. Lift's design review asked for "Start a session" to
/// be the obvious purpose of Track, more dominant than Run's start is, and a
/// full-width filled button in the middle of a column did not read that way:
/// it had the same weight as every other primary button in the suite. The
/// height, the arrow and the position are what set it apart. Use one per
/// screen at most, and only where the screen's purpose is to be left through
/// it.
class ActionPill extends StatelessWidget {
  const ActionPill({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.arrow_forward_rounded,
    this.busy = false,
  });

  /// The verb and its object: `Start a session`, `Start today's session`.
  final String label;

  /// Null draws it disabled, which reads as unavailable rather than broken.
  final VoidCallback? onPressed;

  /// What the disc holds. An arrow unless the action is something else.
  final IconData icon;

  final bool busy;

  /// Tall enough to be the obvious thing to press, and to hold the disc with
  /// air around it. The [PrimaryButton] beside it is 52.
  static const double height = 64;

  @override
  Widget build(BuildContext context) {
    final enabled = !busy && onPressed != null;
    final theme = Theme.of(context);

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: PressScale(
        enabled: enabled,
        onTap: enabled ? onPressed : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: enabled ? 1 : 0.45,
          child: Container(
            height: height,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill)),
            ),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl + AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: AppColors.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                AspectRatio(
                  aspectRatio: 1,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: AppColors.bg,
                      shape: BoxShape.circle,
                    ),
                    child: busy
                        ? const Padding(
                            padding: EdgeInsets.all(AppSpacing.md + 2),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textPrimary,
                            ),
                          )
                        : Icon(icon, color: AppColors.textPrimary, size: 22),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The card-sized action: a short silver pill for the one thing a card or a
/// row does — `Start`, `Add` — quieter than the page's [ActionPill].
///
/// It sits inside something tappable (a card that opens, a row that expands),
/// so the pill's own target is taller than it looks: 44 high around a 36 pill,
/// so a thumb that lands just off it presses it rather than the card behind.
class SmallPill extends StatelessWidget {
  const SmallPill({super.key, required this.label, required this.onPressed});

  final String label;

  /// Null draws it disabled.
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: PressScale(
        enabled: enabled,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            decoration: BoxDecoration(
              color: enabled ? AppColors.primary : AppColors.elevated,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            // Hugs its label, so a row's Start is a pill beside the text and
            // not a bar across it.
            child: Center(
              widthFactor: 1,
              child: Text(
                label,
                maxLines: 1,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: enabled ? AppColors.onPrimary : AppColors.textTertiary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
