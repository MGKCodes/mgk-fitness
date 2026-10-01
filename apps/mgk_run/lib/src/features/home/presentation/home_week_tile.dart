import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../../coaching/domain/prescribed_distance.dart';
import '../../coaching/domain/training_history.dart';
import '../../coaching/domain/training_plan.dart';
import '../../coaching/domain/week_progress.dart';
import '../../coaching/presentation/session_labels.dart';
import '../../coaching/presentation/week_ribbon.dart';

/// The rest of the week, as one tile.
///
/// ## The same tile with and without a plan
///
/// Seven days, two figures, and a line about what is next. With a plan the days
/// are prescribed sessions and the figures count them; without one the days are
/// **runs**, and the figures count those. A runner who never buys a plan does
/// not get this tile emptied out — an empty week ribbon is the exact
/// counter-signal
/// [ADR-0019](../../../../docs/decisions/0019-onboarding-is-two-moments.md)
/// names — they get the same tile answering the same question off the log,
/// which every runner has.
///
/// ## Why two strips rather than one
///
/// [WeekRibbon] draws [DayOutcome]: did you do what the plan asked. The strip
/// below it draws [RunDay]: did you run. `training_history.dart` keeps those
/// two apart deliberately, because only the first needs a plan — and a single
/// component taking either would have to be told which question it was
/// answering anyway.
class HomeWeekTile extends StatelessWidget {
  const HomeWeekTile({
    super.key,
    required this.now,
    required this.unit,
    this.week,
    this.outcomes = const <int, DayOutcome>{},
    this.standing,
    this.runDays = const <RunDay>[],
    this.onOpenPlan,
    this.onAddTreadmillRun,
  });

  final DateTime now;
  final UnitSystem unit;

  /// This week's prescribed sessions, when a plan exists.
  final TrainingWeek? week;

  final Map<int, DayOutcome> outcomes;

  /// Where the week stands. Null only for a caller that has not worked one out
  /// — every runner has a week, and a runner with no plan still has the
  /// distance half of it.
  final WeekStanding? standing;

  /// Monday to Sunday of the current week, off the run log. The last row of the
  /// consistency grid Home already builds, so this costs no new derivation.
  final List<RunDay> runDays;

  /// Opens the Plan tab. Only wired when there is a plan to open onto: sending
  /// a runner who has not bought one to the tab that sells it, from a tile
  /// about their own week, would be an advert wearing a fact's clothes.
  final VoidCallback? onOpenPlan;

  /// Opens the add-a-run form, already set to Treadmill. Null hides the row:
  /// a build with nowhere to write a run has nothing to offer here.
  ///
  /// **On this tile because this tile is where the run will show up.** A
  /// treadmill run is a run the phone did not see, added to the week by hand,
  /// and the week is what changes when it is: a dot on its day and its
  /// distance in the total. It was a lone button on the today card for one
  /// build, which is the card about the run the phone *can* record.
  final VoidCallback? onAddTreadmillRun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = week;
    final ran = standing?.ranMeters ?? 0;
    final next = plan == null ? null : nextRunAfter(plan, now.weekday);

    return HomeTile(
      label: 'This week',
      onTap: plan == null ? null : onOpenPlan,
      trailing: plan == null
          ? null
          : const Icon(
              Icons.chevron_right,
              size: 20,
              color: AppColors.textTertiary,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (plan != null)
            WeekRibbon(week: plan, today: now, outcomes: outcomes)
          else
            _RunWeekStrip(days: runDays, today: now.weekday),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: plan == null
                    ? StatBlock(
                        label: 'Runs',
                        // A dash, not a zero. A week nothing has happened in
                        // has no count to report — the strip above has already
                        // shown the days going by, which is the honest way to
                        // say it.
                        value: _ranDays == 0 ? '—' : '$_ranDays',
                        valueColor: _ranDays == 0
                            ? AppColors.textTertiary
                            : null,
                      )
                    : StatBlock(
                        label: 'Sessions',
                        // Zero *is* a fact here, because the denominator gives
                        // it one: "0 of 5" says there are five to do, where a
                        // bare 0 would only say nothing has happened.
                        value: standing == null
                            ? '—'
                            : '${standing!.done} of ${standing!.sessions}',
                      ),
              ),
              Expanded(
                child: StatBlock(
                  label: 'Distance',
                  // The distance a runner actually covered, to a decimal.
                  // Prescriptions round; achievements do not.
                  value: ran <= 0
                      ? '—'
                      : Distance.meters(ran).format(unit, fractionDigits: 1),
                  valueColor: ran <= 0 ? AppColors.textTertiary : null,
                ),
              ),
            ],
          ),
          if (next != null) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            Text(
              // No time of day: a session later in the week has no hour
              // attached to it, and inventing one is what [sessionNameAt] and
              // [sessionName] exist to keep apart.
              'Next · ${sessionName(next).toLowerCase()} '
              '${formatPrescribed(next.distanceMeters, unit)}'
              ' on ${weekdayLongName(next.weekday)}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.textTertiary,
              ),
            ),
          ],
          if (onAddTreadmillRun != null) ...<Widget>[
            const SizedBox(height: AppSpacing.lg),
            _AddRunRow(onTap: onAddTreadmillRun!),
          ],
        ],
      ),
    );
  }

  int get _ranDays => runDays.where((d) => d == RunDay.ran).length;
}

/// The foot of the tile: a rule, and one full-width row that adds a run.
///
/// A row rather than a button, so it fills the tile's width and has no empty
/// space beside it. The whole row is the target.
class _AddRunRow extends StatelessWidget {
  const _AddRunRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(height: 1, color: AppColors.elevated.withValues(alpha: 0.7)),
        InkWell(
          onTap: onTap,
          borderRadius: AppRadius.chipAll,
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Add a treadmill run',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'For a run the phone could not track',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                const Icon(Icons.add, size: 22, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Monday to Sunday, marked where a run happened.
///
/// Built to the same rhythm as [WeekRibbon] — a letter, a dot, today picked out
/// in a chip — so the tile does not change shape when a runner gets a plan. The
/// dot means something different, which is why it is a different widget.
class _RunWeekStrip extends StatelessWidget {
  const _RunWeekStrip({required this.days, required this.today});

  /// Seven entries, Monday first. Fewer than seven — a caller with no grid yet
  /// — draws the week as still to come rather than throwing.
  final List<RunDay> days;

  final int today;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (var weekday = 1; weekday <= 7; weekday++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: weekday == 7 ? 0 : AppSpacing.xs),
              child: _Cell(
                letter: weekdayName(weekday).substring(0, 1),
                day: weekday <= days.length ? days[weekday - 1] : RunDay.future,
                isToday: weekday == today,
              ),
            ),
          ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.letter, required this.day, required this.isToday});

  final String letter;
  final RunDay day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final ran = day == RunDay.ran;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isToday ? AppColors.primary : Colors.transparent,
        borderRadius: AppRadius.chipAll,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            letter,
            style: TextStyle(
              color: isToday ? AppColors.onPrimary : AppColors.textTertiary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            height: 10,
            child: ran
                ? Center(
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: isToday
                            ? AppColors.onPrimary
                            : AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  )
                // **A day without a run is a gap, not a cross.** Most days of
                // most weeks are this, by design, and a row of marks for them
                // would turn a fact into a scorecard.
                : null,
          ),
        ],
      ),
    );
  }
}
