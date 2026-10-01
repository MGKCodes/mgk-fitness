import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../domain/pace_model.dart';
import '../domain/prescribed_distance.dart';
import '../domain/race_day.dart';
import '../domain/session_effort.dart';
import '../domain/session_status.dart';
import '../domain/training_plan.dart';
import 'session_labels.dart';

/// One week as seven rows, Monday to Sunday.
///
/// **A list, not a grid.** A seven-column grid gives each day about 48px, which
/// holds roughly two facts — which is why an earlier version had to render the
/// session *kind* as a bar rather than the word "Threshold". The bar was a
/// workaround for the container, and it read as a chart nobody could decode.
///
/// A row holds the day, the session, its target pace and its distance without
/// abbreviating any of them. Mobile favours the list for exactly this reason,
/// and it is what the training apps that do this well use for the week you are
/// actually in.
///
/// The grid still earns its place in the calendar, where several weeks are
/// stacked and the job is comparing shapes rather than reading one week.
class WeekList extends StatelessWidget {
  const WeekList({
    super.key,
    required this.week,
    required this.weekStart,
    this.paces,
    this.today,
    this.statusFor,
    this.onTapDay,
    this.unit = UnitSystem.metric,
    this.raceDay,
  });

  final TrainingWeek week;

  /// The race, when it falls in this week. Its row is the race, whatever the
  /// week holds for that day.
  final RaceDayEntry? raceDay;

  /// The Monday this week begins on, so the dates are real.
  final DateTime weekStart;

  /// Target paces, when the profile supports deriving them.
  final TrainingPaces? paces;

  /// Today, when it falls in this week.
  final DateTime? today;

  final SessionStatus? Function(int weekday)? statusFor;
  final void Function(int weekday)? onTapDay;
  final UnitSystem unit;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (var weekday = 1; weekday <= 7; weekday++)
          _DayRow(
            weekday: weekday,
            date: DateTime(
              weekStart.year,
              weekStart.month,
              weekStart.day + (weekday - 1),
            ),
            session: week.sessionOn(weekday),
            race: raceDay?.weekday == weekday ? raceDay : null,
            paces: paces,
            status: statusFor?.call(weekday),
            isToday: today != null && today!.weekday == weekday,
            isPast: today != null && weekday < today!.weekday,
            unit: unit,
            // The race has no session brief: there is nothing to prescribe.
            onTap: onTapDay == null || raceDay?.weekday == weekday
                ? null
                : () => onTapDay!(weekday),
          ),
      ],
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.weekday,
    required this.date,
    required this.session,
    required this.paces,
    required this.status,
    required this.isToday,
    required this.isPast,
    required this.unit,
    this.race,
    this.onTap,
  });

  final int weekday;
  final DateTime date;
  final RaceDayEntry? race;
  final PlannedSession? session;
  final TrainingPaces? paces;
  final SessionStatus? status;
  final bool isToday;
  final bool isPast;
  final UnitSystem unit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final race = this.race;
    // On race day the row is the race. A session the week still holds for the
    // day, from a plan written before race day was kept clear, is not drawn.
    final run = race == null ? session : null;
    final isRest = run == null && race == null;
    // Strength occupies the day but adds no distance and has no pace, so the
    // row carries the word and nothing else — which is the whole point of the
    // kind. See [SessionKind.strength].
    final isSupport = run != null && run.kind.isSupport;
    final done = status == SessionStatus.completed;
    final skipped = status == SessionStatus.skipped;

    // Today is the only filled row. Days already gone recede; days ahead sit
    // between the two, so the week reads top to bottom as behind you and ahead.
    final ink = isToday
        ? AppColors.onPrimary
        : (isRest || isPast
              ? AppColors.textTertiary
              : (isSupport ? AppColors.textSecondary : AppColors.textPrimary));
    final quiet = isToday
        ? AppColors.onPrimary.withValues(alpha: 0.75)
        : AppColors.textTertiary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: isToday
            ? AppColors.primary
            : (isRest
                  ? Colors.transparent
                  : AppColors.textPrimary.withValues(
                      alpha: isSupport ? 0.03 : 0.05,
                    )),
        borderRadius: AppRadius.chipAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: <Widget>[
                // The day, as a word and a number. No abbreviation games and no
                // single letters, so Thursday cannot be mistaken for Tuesday.
                SizedBox(
                  width: 62,
                  child: Row(
                    children: <Widget>[
                      Text(
                        weekdayName(weekday),
                        style: TextStyle(
                          color: isToday ? AppColors.onPrimary : quiet,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      // Flexible, not fixed: the column is sized for the widest
                      // real weekday, and a narrower text scale must clip the
                      // date rather than overflow the row.
                      Flexible(
                        child: Text(
                          '${date.day}',
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: TextStyle(
                            color: isToday
                                ? AppColors.onPrimary.withValues(alpha: 0.7)
                                : AppColors.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),

                Expanded(
                  child: race != null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              'Race day',
                              style: TextStyle(
                                color: ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (race.detail().isNotEmpty) ...<Widget>[
                              const SizedBox(height: 1),
                              Text(
                                race.detail(),
                                style: TextStyle(color: quiet, fontSize: 11),
                              ),
                            ],
                          ],
                        )
                      : isRest
                      ? Text(
                          'Rest',
                          style: TextStyle(color: quiet, fontSize: 14),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              sessionName(run!),
                              style: TextStyle(
                                color: ink,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                decoration: skipped
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            // The effort, not the pace. "target 4:39 /km" told
                            // a runner what to chase and nothing about whether
                            // they were doing the session right — and chasing a
                            // number on an easy day is how a block stalls. The
                            // pace band lives one tap away, in the brief.
                            //
                            // Suppressed where it would only repeat the kind:
                            // strength's effort *is* "strength", and a row
                            // reading "Strength / strength" is a line of type
                            // spent saying nothing.
                            const SizedBox(height: 1),
                            Text(
                              effortFor(run.kind).cue,
                              style: TextStyle(color: quiet, fontSize: 11),
                            ),
                          ],
                        ),
                ),

                if (race != null)
                  Text(
                    race.distanceLabel(unit),
                    style: TextStyle(
                      color: ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (run != null && !isSupport) ...<Widget>[
                  // Done and skipped both get a mark. The strikethrough alone
                  // is easy to miss at 14px, and a skipped session is exactly
                  // the thing a runner scans the week for.
                  if (done || skipped)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: Icon(
                        done ? Icons.check : Icons.close,
                        size: 15,
                        color: quiet,
                      ),
                    ),
                  Text(
                    formatPrescribed(run.distanceMeters, unit),
                    style: TextStyle(
                      color: ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      decoration: skipped ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
