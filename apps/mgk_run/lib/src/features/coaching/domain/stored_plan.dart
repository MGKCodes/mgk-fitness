import 'plan_shape.dart';
import 'runner_profile.dart';
import 'training_plan.dart';

/// A plan as it exists **on disk** — the skeleton, the profile it was built for,
/// and the calendar anchor that turns a week index into real dates.
///
/// The profile is the one captured at plan creation, not the runner's current
/// profile. The validator checks a skeleton against a profile
/// (docs/architecture/plan-generation.md); pairing a stored plan with a later,
/// edited profile would make a perfectly good plan look invalid.
class StoredPlan {
  StoredPlan({
    required this.id,
    required this.profile,
    required this.skeleton,
    required this.startDate,
  }) : assert(skeleton.weeks.isNotEmpty, 'a stored plan has at least one week');

  final String id;
  final RunnerProfile profile;
  final PlanSkeleton skeleton;

  /// The Monday of week 1, date-only.
  final DateTime startDate;

  /// The 1-based week [date] falls in, clamped into the plan. Before the plan
  /// starts this is week 1 for a plan that progresses; after it ends, the final
  /// week — a plan the runner has run past still shows its last week rather
  /// than nothing at all.
  ///
  /// **A rhythm answers differently before its start, and must.** Its weeks
  /// cycle, so a negative index wraps to the end rather than clamping to the
  /// beginning — which keeps [dateFor] its exact inverse, the invariant
  /// `stored_plan_test.dart` pins as a round trip. Clamping it to 1 was tried
  /// when plans moved to a future start date (ADR-0034) and broke exactly that.
  /// Nothing is wrong with the wrapped answer: for a plan whose weeks are all
  /// the same week, which index names it is a labelling question.
  int weekIndexOn(DateTime date) {
    final week = _weeksFromStart(date) + 1;
    final total = skeleton.weeks.length;
    if (total <= 0) return 1;
    // A plan that goes somewhere runs out at its last week and stays there. A
    // rhythm does not go anywhere and does not run out: it cycles, because its
    // weeks are all the same week and "week 13 of a 12-week parkrun habit" is
    // not a thing that can happen.
    if (!shapeOf(profile).progresses) {
      return (week - 1) % total + 1;
    }
    return week.clamp(1, total);
  }

  /// The skeleton slot [date] falls in.
  SkeletonWeek weekOn(DateTime date) => skeleton.weeks[weekIndexOn(date) - 1];

  /// The calendar date of [weekday] (1=Mon..7=Sun) in week [weekIndex].
  ///
  /// [on] says **which occurrence** is meant, and only changes the answer for a
  /// plan whose weeks cycle. A block's week 5 happens once, so its dates are
  /// fixed by [startDate] and [on] is ignored. A rhythm's "week 1" comes round
  /// again every cycle, and the one the runner means is the one they are living
  /// in — so without [on] a cycling plan answers with its *first* cycle, which
  /// is how a parkrun habit started in May was still headed "4 – 10 May" in
  /// July. Callers drawing a calendar pass the day being drawn.
  ///
  /// Keeps [weekIndexOn] as its inverse for both shapes: the returned date
  /// always falls in week [weekIndex].
  DateTime dateFor({
    required int weekIndex,
    required int weekday,
    DateTime? on,
  }) {
    final total = skeleton.weeks.length;
    if (on == null || total <= 0 || shapeOf(profile).progresses) {
      return addDays(startDate, (weekIndex - 1) * 7 + (weekday - 1));
    }
    // The cycle [on] falls in, counted in whole weeks from the start. Dart's `%`
    // is non-negative for a positive divisor, so `cycleStart` stays a multiple
    // of [total] even for a date before the plan began.
    final weeksIn = _weeksFromStart(on);
    final cycleStart = weeksIn - (weeksIn % total);
    return addDays(startDate, (cycleStart + weekIndex - 1) * 7 + (weekday - 1));
  }

  /// Whole weeks from [startDate] to [date], 0 for the start week itself.
  ///
  /// **Floored, not truncated.** `~/` rounds toward zero, so a date 19 days
  /// before the start came back as two weeks earlier rather than three — the
  /// week either side of the start date was the same week. Nothing draws a date
  /// before the plan began, but [weekIndexOn] and [dateFor] have to agree about
  /// one or the round trip between them stops holding.
  int _weeksFromStart(DateTime date) =>
      (daysBetweenDates(startDate, date) / 7).floor();

  /// True once [date] is past the plan's final week — the event has been and
  /// gone, so the runner is due a new plan rather than a stale one.
  ///
  /// **A rhythm never ends.** Someone who runs parkrun every Saturday is not
  /// working toward anything that finishes, and telling them their plan expired
  /// after twelve weeks would be the app deciding their habit was a project.
  bool hasEndedBy(DateTime date) =>
      shapeOf(profile).progresses &&
      daysBetweenDates(startDate, date) >= skeleton.weeks.length * 7;
}

/// The Monday of the week [date] falls in, date-only. Weeks are anchored to
/// calendar Mondays so a session's weekday number means what it says.
DateTime mondayOf(DateTime date) =>
    addDays(date, DateTime.monday - date.weekday);

/// The next Monday at or after [date] — the Monday itself when [date] is one.
///
/// **Where a plan starts** (ADR-0034). Plans used to anchor to
/// `mondayOf(now)`, so one built on a Friday opened with Monday to Thursday
/// already behind it: four days of a seven-day week gone, on the screen a
/// runner had just asked for a plan on. Found on the build 12 field test.
DateTime comingMondayFrom(DateTime date) {
  final DateTime thisMonday = mondayOf(date);
  return thisMonday.isBefore(addDays(date, 0))
      ? addDays(thisMonday, 7)
      : thisMonday;
}

/// [date] shifted by [days], as a **date-only** local midnight.
///
/// Not `add(Duration(days:))`: a duration is absolute time, so crossing a
/// daylight-saving boundary would land on 23:00 or 01:00 and stop matching a
/// stored `scheduled_date`. The `DateTime` constructor normalises out-of-range
/// day numbers, so this stays midnight on the right calendar day.
DateTime addDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

/// Whole calendar days from [from] to [to], both taken date-only.
///
/// Computed in UTC so a daylight-saving hour cannot round a 7-day gap down to 6.
int daysBetweenDates(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
