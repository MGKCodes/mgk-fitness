/// The bubbles a **scripted** exchange is drawn with.
///
/// Shared because onboarding now happens in two places — the pre-account intro
/// and the question at the front of the plan flow (ADR-0019) — and a runner
/// should not be able to tell that one of them is in a different feature
/// folder. When these were private to `intro_screen.dart` the second screen
/// would have had to copy them, and a copied bubble is a bubble that drifts.
///
/// Distinct from `ChatBubble`, which is the *model's* transcript. These read as
/// the coach speaking directly: no fill, the mark to the left.
library;

import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'chat_widgets.dart' show CoachMark;

/// Something the coach said.
class Said extends StatelessWidget {
  const Said(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // The transcript's own mark, imported rather than copied, so a
          // restyle there carries here and the two never drift apart.
          const SizedBox(width: 30, child: CoachMark()),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.textPrimary,
                height: 1.45,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Something the runner said.
class Replied extends StatelessWidget {
  const Replied(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Align(
        alignment: Alignment.centerRight,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.all(Radius.circular(16)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Text(
              text,
              style: const TextStyle(
                color: AppColors.onPrimary,
                height: 1.4,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One tappable answer, with a label and a line of detail beneath it.
class ChoiceCard extends StatelessWidget {
  const ChoiceCard({
    super.key,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      // `elevated`, not `surface` — the colour the design system names for
      // inputs and raised surfaces, which is what these are.
      //
      // Two attempts to get this right. The first choice sat over the lightest
      // part of a `grounded` scrim and read as no card at all while the four
      // below it read fine. Making the fill opaque did not help, because the
      // fill was never the problem: `surface` is very near the backdrop's own
      // tone at that height, so the card was invisible by coincidence of
      // matching grey rather than by transparency. `elevated` is lighter than
      // the backdrop at both ends of the gradient.
      color: AppColors.elevated,
      borderRadius: AppRadius.cardAll,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                label,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
