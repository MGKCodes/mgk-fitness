import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The suite's silver primary button — full-width, with a busy state.
/// Styling comes from the theme's [FilledButtonThemeData].
///
/// **This is the action the screen exists for**, and it should be reached for
/// on that basis rather than because a button is needed. With no accent colour
/// (ADR-0009), a silver fill is the strongest emphasis the product has; spend
/// it on "Start a session", not on something a person would regret tapping.
/// For those, see [DestructiveButton].
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.onPrimary,
                ),
              )
            : Text(label),
      ),
    );
  }
}

/// An action that is offered but not encouraged — erasing, deleting, forgetting.
///
/// **Danger on the word, not around it.** Outlined rather than filled, with the
/// red carried by the label and a neutral border. A red ring was tried first
/// and was worse than the fill it replaced: on a screen with no other colour,
/// it pulled the eye harder than the silver primary did, which is the opposite
/// of the point. The distinction being drawn is emphasis, not availability —
/// the action is one tap away, it simply is not what the screen recommends.
///
/// **Written because both apps got this wrong in opposite directions.** Run's
/// delete-account screen re-specified height, shape, border and text style
/// inline — the only styling of its kind in the suite — because there was no
/// `outlinedButtonTheme` to inherit from and no component to reach for. Lift's
/// coach-memory screen, having the same need, used [PrimaryButton], which made
/// "Forget everything" the highest-contrast element on a screen whose entire
/// purpose is to be read.
///
/// It matches [PrimaryButton]'s metrics so the two are interchangeable in a
/// slot without the layout moving.
class DestructiveButton extends StatelessWidget {
  const DestructiveButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;

  /// Null disables it. Used by flows that arm the action behind a typed
  /// confirmation rather than showing it live from the start.
  final VoidCallback? onPressed;

  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: busy ? null : onPressed,
        // Border and metrics come from the theme, so this differs from a plain
        // outlined button in exactly one respect: the colour of its label.
        style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
        child: busy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.danger,
                ),
              )
            : Text(label),
      ),
    );
  }
}
