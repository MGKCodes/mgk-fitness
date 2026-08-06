import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import '../domain/training_plan.dart';
import '../domain/week_progress.dart';
import 'session_labels.dart';

/// The week as a single compact row, with today picked out.
///
/// Home's version of the calendar. It answers "where am I in the week" and
/// nothing else — no distances, no session names, no tap targets. The detail
/// belongs to today, which sits underneath it, and to the Plan tab, which
/// shows the week properly.
///
/// Distinct from [WeekCalendar] on purpose. That one is a plan you read; this is
/// a position you glance at. Rendering the same component small would have made
/// Home a worse copy of a screen the runner can already reach in one tap.
///
/// **It draws outcomes, not intentions.** It used to take a [SessionStatus] the
/// runner had asserted by tapping, and only ever knew today's. It now takes
/// [DayOutcome]s derived from the run log, so the whole week reads as what
/// actually happened — which is the job Home's recent-runs list was doing
/// badly, and why that list could go (ADR-0017).
class WeekRibbon extends StatelessWidget {
  const WeekRibbon({
    super.key,
    required this.week,
    required this.today,
    this.outcomes = const <int, DayOutcome>{},
  });

  final TrainingWeek week;

  /// Today, so the right cell is lit.
  final DateTime today;

  /// What became of each prescribed day, by weekday. Days absent from the map
  /// are drawn as still-to-come.
  final Map<int, DayOutcome> outcomes;

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
                hasSession: week.sessionOn(weekday) != null,
                outcome: outcomes[weekday] ?? DayOutcome.upcoming,
                isToday: today.weekday == weekday,
                isPast: weekday < today.weekday,
              ),
            ),
          ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.letter,
    required this.hasSession,
    required this.outcome,
    required this.isToday,
    required this.isPast,
  });

  final String letter;
  final bool hasSession;
  final DayOutcome outcome;
  final bool isToday;
  final bool isPast;

  @override
  Widget build(BuildContext context) {
    final done = outcome == DayOutcome.done;
    // Missed and skipped draw the same: both mean the day went by without the
    // run. **Hollow, not red.** Colour is reserved for destructive actions
    // (ADR-0009), and a row of red crosses is a guilt machine — a coach
    // mentions a missed session, they do not decorate it.
    final hollow =
        outcome == DayOutcome.skipped || outcome == DayOutcome.missed;

    // A run day is a dot; a rest day is a gap. Done fills, missed hollows,
    // still-to-come sits between the two — the week reads left to right as a
    // row of things behind you and things ahead.
    final Color dot;
    if (!hasSession) {
      dot = Colors.transparent;
    } else if (done) {
      dot = isToday ? AppColors.onPrimary : AppColors.primary;
    } else if (hollow) {
      dot = isToday
          ? AppColors.onPrimary.withValues(alpha: 0.35)
          : AppColors.textTertiary;
    } else {
      // Fainter than it was. Done and upcoming were both filled dots a third of
      // an alpha apart, which at 7px is no difference at all — a runner
      // glancing at the ribbon could not tell a week they had run from a week
      // they had not. Missed is the shape that carries (hollow); this is the
      // weight that separates the other two.
      dot = isToday
          ? AppColors.onPrimary
          : AppColors.primary.withValues(alpha: 0.22);
    }

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
            child: hasSession
                ? Center(
                    child: Container(
                      // A run behind you is worth more pixels than one ahead of
                      // you: size carries the distinction alpha alone could not.
                      width: done ? 9 : 7,
                      height: done ? 9 : 7,
                      decoration: BoxDecoration(
                        color: hollow ? Colors.transparent : dot,
                        shape: BoxShape.circle,
                        border: hollow
                            ? Border.all(color: dot, width: 1.4)
                            : null,
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}
