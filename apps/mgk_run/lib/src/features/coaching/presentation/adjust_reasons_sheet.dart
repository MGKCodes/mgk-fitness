import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';

/// One reason a week needs to bend: what the runner taps, and the sentence it
/// puts to the coach on their behalf.
class AdjustReason {
  const AdjustReason({
    required this.label,
    required this.detail,
    required this.request,
  });

  /// The row's title — the runner's own words for the situation.
  final String label;

  /// What picking it will do, in one line.
  final String detail;

  /// The request handed to the coach. Written out in full because it travels
  /// the same path a typed sentence does, and a two-word prompt would get a
  /// two-word reading of it.
  final String request;
}

/// The situations that make a plan need to bend, as buttons.
///
/// **A door, not an engine.** [AdaptationService] has been here all along: it
/// takes a sentence, gets a revised week from the coach, and refuses anything
/// the validator will not have. The only way in was to type prose at the coach
/// — so the runner who most needs it, the one who is ill or sore or already
/// behind, had to compose a paragraph about it first. Every row here is a
/// pre-written request travelling that same propose → validate → diff →
/// approve path, and nothing reaches the plan until the runner has seen the
/// diff and said yes (CLAUDE.md rule 2).
///
/// Deliberately **not** a "skip week" switch that edits the plan directly. A
/// week the app rewrote on its own would be the app deciding what someone's
/// training should be from a tap, which is the thing the validator exists to
/// stop.
class AdjustReasonsSheet extends StatelessWidget {
  const AdjustReasonsSheet({super.key});

  /// The reasons offered, in the order a runner is likely to want them.
  ///
  /// Pitched at *this week*, because that is the unit the coach revises. A
  /// pause is the same operation with the remaining days emptied — there is no
  /// separate paused state to get stuck in, and a runner who is still off next
  /// week asks again then.
  static const List<AdjustReason> reasons = <AdjustReason>[
    AdjustReason(
      label: "I'm not feeling 100%",
      detail: 'Tired or run down. Take the edge off the rest of the week.',
      request:
          "I'm not feeling 100% this week — tired and a bit run down. Please "
          'make the rest of the week easier: less distance, and nothing hard.',
    ),
    AdjustReason(
      label: 'Something hurts',
      detail: 'Keep me moving, drop the hard running.',
      request:
          'Something is hurting. Please take the hard running out of the rest '
          'of this week and keep whatever is left easy.',
    ),
    AdjustReason(
      label: 'Pause the rest of this week',
      detail: 'Ill, or away. Make the remaining days rest.',
      request:
          'I need to pause my plan for the rest of this week. Please make the '
          'remaining days rest.',
    ),
    AdjustReason(
      label: 'I missed a run',
      detail: 'Rebalance what is left instead of cramming it in.',
      request:
          'I missed a run this week. Please rebalance what is left rather than '
          'squeezing the missed session into the remaining days.',
    ),
    AdjustReason(
      label: "I'm short on time",
      detail: 'Same shape, less of it.',
      request:
          "I'm short on time for the rest of this week. Please shorten the "
          'sessions but keep the shape of the week.',
    ),
  ];

  /// Opens the sheet and completes with the chosen [AdjustReason.request], or
  /// null if the runner backed out.
  static Future<String?> show(BuildContext context) =>
      showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        backgroundColor: AppColors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (_) => const AdjustReasonsSheet(),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.xl,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'What is going on?',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              // Said before they pick, not after: the runner is about to hand
              // their week to a coach, and the one thing they want to know is
              // whether it changes under them.
              'The coach will suggest a change and show you what it is. '
              'Nothing moves until you say yes.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final reason in reasons)
              _ReasonRow(
                reason: reason,
                onTap: () => Navigator.of(context).pop(reason.request),
              ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: AppTextButton(
                label: 'Never mind',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonRow extends StatelessWidget {
  const _ReasonRow({required this.reason, required this.onTap});

  final AdjustReason reason;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
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
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        reason.label,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        reason.detail,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                const Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: AppColors.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
