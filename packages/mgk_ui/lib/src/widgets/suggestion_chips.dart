import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
// AppSpacing lives beside AppRadius rather than in a file of its own.

/// Replies the coach has offered, for a person who does not want to type.
///
/// The coach is read standing up between sets and, at onboarding, by somebody
/// who has not yet decided the app is worth the effort. Both are situations
/// where a text field is a toll. A chip is one tap.
///
/// **These are proposed by the coach, never invented by the app.** That is not
/// a style rule — `CoachService` says in as many words that the app "cannot put
/// words in the coach's mouth and then ask it to act on them", and a chip the
/// client made up and then sent as the lifter's own message is exactly that.
/// The chips ride on the turn that offered them, so a turn with none renders
/// none and there is nowhere for a local default to creep in.
///
/// **Aligned to the person's side, not the coach's.** They are things *you*
/// would say, and tapping one puts your bubble where the chip was — so the
/// affordance sits where its own result will appear. Left-aligned under the
/// coach's bubble they read as part of the coach's answer, which is the one
/// thing they are not.
///
/// No accent colour, per ADR-0009: an outline against the page carries "tap
/// me" perfectly well, and the two sides of this conversation already differ by
/// weight rather than by hue.
class SuggestionChips extends StatelessWidget {
  const SuggestionChips({
    super.key,
    required this.suggestions,
    required this.onSelected,
  });

  final List<String> suggestions;

  /// Given the exact text the coach offered — the caller sends that, not a
  /// paraphrase, or the transcript stops matching what was actually said.
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: <Widget>[
          for (final s in suggestions)
            InkWell(
              onTap: () => onSelected(s),
              borderRadius: BorderRadius.circular(AppRadius.chip),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                  // `elevated` is the coach bubble's fill, used here as a line. The
                  // chip reads as belonging to the answer above it without
                  // taking a second surface colour to do it.
                  border: Border.all(color: AppColors.elevated),
                ),
                child: Text(
                  s,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
