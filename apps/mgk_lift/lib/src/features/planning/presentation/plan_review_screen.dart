import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../domain/plan.dart';

/// The draft, before it is anyone's training.
///
/// **Generated, shown, accepted — never generated and imposed.** The plan is a
/// `draft` in the database until this screen returns true, and that is a
/// schema constraint rather than a UI convention, so no other path can quietly
/// make one live.
///
/// It shows the whole arc and the weeks that have been filled in. The rest are
/// honestly marked as not written yet: weeks are generated a week ahead, and
/// pretending otherwise would be the screen claiming more than the plan has.
class PlanReviewScreen extends StatelessWidget {
  const PlanReviewScreen({
    super.key,
    required this.plan,
    required this.unit,
    this.onAccept,
    this.busy = false,
  });

  final Plan plan;
  final MassUnit unit;
  final VoidCallback? onAccept;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filled = plan.sessions.map((PlanSession s) => s.weekNumber).toSet();
    final targeted = plan.sessions.fold<int>(
      0,
      (int sum, PlanSession s) => sum + s.targetedMovements,
    );
    final movements = plan.sessions.fold<int>(
      0,
      (int sum, PlanSession s) => sum + s.movements.length,
    );

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('Your plan')),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.xl,
                ),
                children: <Widget>[
                  if (plan.goal != null && plan.goal!.isNotEmpty) ...<Widget>[
                    const SectionLabel('What this is for'),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      plan.goal!,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.4),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],

                  Text(
                    '${plan.weeks} weeks, '
                    '${plan.profile.daysPerWeek} days a week.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),

                  // Said plainly rather than left to be noticed. A plan that is
                  // mostly targetless is the honest state for somebody a
                  // fortnight in, and it looks like a bug if nobody says so.
                  if (movements > 0 && targeted < movements) ...<Widget>[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      targeted == 0
                          ? 'No weights yet. Your coach sets them from what you '
                                'have actually lifted, and it has not seen '
                                'enough to work any out. Log a few sessions and '
                                'they will appear.'
                          : '$targeted of $movements movements have a weight. '
                                'The rest are ones your coach has not seen you '
                                'lift, so it is not guessing at a number.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textTertiary,
                        height: 1.4,
                      ),
                    ),
                  ],

                  const SizedBox(height: AppSpacing.xl),
                  const SectionLabel('The block'),
                  const SizedBox(height: AppSpacing.sm),

                  // The weeks that exist, in full.
                  for (final week in plan.arc)
                    if (filled.contains(week.number))
                      _WeekRow(
                        week: week,
                        sessions: plan.sessions
                            .where(
                              (PlanSession s) => s.weekNumber == week.number,
                            )
                            .toList(),
                        unit: unit,
                      ),

                  // And the rest as ONE row, not one card each.
                  //
                  // Rendered individually they were six near-identical cards,
                  // every one repeating that it would be written closer to the
                  // time — a wall of sameness that makes a plan read as
                  // generated, which is the impression this screen exists to
                  // avoid. The arc is still shown, because knowing the block
                  // deloads in week 4 is the point of having one.
                  if (plan.arc.any((PlanWeek w) => !filled.contains(w.number)))
                    _WeeksToCome(
                      weeks: plan.arc
                          .where((PlanWeek w) => !filled.contains(w.number))
                          .toList(),
                    ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.lg,
              ),
              child: Column(
                children: <Widget>[
                  PrimaryButton(
                    label: busy ? 'Starting…' : 'Start this plan',
                    onPressed: busy ? null : onAccept,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Nothing is training until you start it. You can change it '
                    'or ask for a different one.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.week,
    required this.sessions,
    required this.unit,
  });

  final PlanWeek week;
  final List<PlanSession> sessions;
  final MassUnit unit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  'Week ${week.number}',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  week.phase.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: week.isDeload
                        ? AppColors.textSecondary
                        : AppColors.textTertiary,
                  ),
                ),
              ],
            ),
            if (week.intent != null && week.intent!.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.xs),
              Text(
                week.intent!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],

            for (final session in sessions) ...<Widget>[
              const SizedBox(height: AppSpacing.md),
              Text(
                '${_weekdayName(session.weekday)} · ${session.title}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              for (final movement in session.movements)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '${movement.name} — ${movement.render(unit)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              if (session.rationale != null &&
                  session.rationale!.isNotEmpty) ...<Widget>[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  session.rationale!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                    height: 1.4,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

String _weekdayName(int weekday) => switch (weekday) {
  1 => 'Monday',
  2 => 'Tuesday',
  3 => 'Wednesday',
  4 => 'Thursday',
  5 => 'Friday',
  6 => 'Saturday',
  7 => 'Sunday',
  _ => 'Day $weekday',
};

/// The weeks the coach has not written yet, as one row.
///
/// **The arc without the repetition.** Each unwritten week rendered its own
/// card, and since they carry only a phase and an intent, six of them read as
/// the same card printed six times — which makes a plan look machine-made in
/// the one place it most needs not to.
///
/// The phases still show, because the shape of the block is the thing worth
/// knowing in advance: that week 4 backs off is a fact about the plan, and that
/// week 5's sessions are not written yet is a fact about the plumbing.
class _WeeksToCome extends StatelessWidget {
  const _WeeksToCome({required this.weeks});

  final List<PlanWeek> weeks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = weeks.first.number;
    final last = weeks.last.number;
    final deloads = weeks
        .where((PlanWeek w) => w.isDeload)
        .map((PlanWeek w) => w.number)
        .toList();

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            first == last ? 'Week $first' : 'Weeks $first to $last',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Written a week at a time, so each one can answer how the last '
            'actually went.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          if (deloads.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppSpacing.sm),
            Text(
              deloads.length == 1
                  ? 'Week ${deloads.single} backs off.'
                  : 'Weeks ${deloads.join(' and ')} back off.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
