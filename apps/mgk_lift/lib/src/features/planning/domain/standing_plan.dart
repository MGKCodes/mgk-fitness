import 'package:meta/meta.dart';

import 'training_split.dart';

/// A plan that does not end.
///
/// ## Why the block model was wrong here
///
/// [Plan] carries `startDate`, `weeks`, an `arc` of weeks and a `completed`
/// status. That shape is inherited from Runio and it is correct there: a
/// marathon plan ends on race day, the taper only makes sense relative to it,
/// and "completed" is a real event with a date attached.
///
/// Lifting has no race day. "Get stronger" and "lose fat" do not finish, and a
/// twelve-week block implies a finish line the sport does not have — which
/// leaves the app with two bad answers on week thirteen: expire the plan and
/// make somebody re-answer an intake to carry on doing what they were already
/// doing, or quietly extend it and admit the twelve was decorative.
///
/// So this is a **standing** plan: a split, the days it runs on, and what fills
/// each slot. It is a rule for deriving today's session rather than a list of
/// sessions already written down.
///
/// ## The consequence worth noticing
///
/// The plan stops being data and becomes a generator. `lift.plan_sessions` held
/// a row per session for the whole block, which had to be written up front,
/// rewritten whenever anything changed, and thrown away at the end. A standing
/// plan holds one slot per movement — a couple of dozen rows that outlive every
/// session derived from them.
///
/// ## Rotation is planned and slow, and the data triggers it
///
/// The instinct is that movements should keep changing so nothing gets stale or
/// sore. The evidence does not support it for growth: varying exercises and
/// repeating them produce similar hypertrophy and strength, and progressive
/// overload — the thing that does drive both — is impossible on a movement you
/// keep replacing, because there is no previous number to beat.
///
/// What variation is good for is avoiding detrimental adaptation, and it works
/// best **planned rather than reactive**. So:
///
///  * main lifts stay, indefinitely, because they are what progress is measured
///    in;
///  * accessories carry a review interval, so change is scheduled rather than
///    improvised;
///  * and a slot becomes eligible early when the data says it has stopped
///    paying — [MovementSlot.hasStalled], which is the same signal the coach
///    already reads out loud when it says a lift has not moved in six sessions.
///
/// A stall is a reason to change something. A calendar week is not.
@immutable
class StandingPlan {
  const StandingPlan({
    required this.id,
    required this.split,
    required this.weekdays,
    required this.slots,
    this.startedAt,
  });

  final String id;
  final TrainingSplit split;

  /// Which weekdays it runs on, `DateTime.monday`-style. Length decides the
  /// split, and the two are checked against each other rather than trusted.
  final List<int> weekdays;

  /// Every movement the plan holds, keyed by the day of the split it belongs
  /// to — "Upper", "Push", "Full body A".
  final Map<String, List<MovementSlot>> slots;

  /// When it began. **Kept for interest, not for arithmetic.** Nothing is
  /// derived from it, no week number is computed off it, and it never expires
  /// anything — it exists so the app can say "you have been on this since
  /// March", which is a nice thing to know and not a schedule.
  final DateTime? startedAt;

  /// The day of the split that falls on [date], or null if it is a rest day.
  ///
  /// Derived from the weekday rather than from a stored calendar, which is what
  /// makes the plan survive a missed week: skip a fortnight and Wednesday is
  /// still Upper, where a pre-generated schedule would have you three sessions
  /// behind on a plan that had moved on without you.
  String? dayFor(DateTime date) {
    final i = weekdays.indexOf(date.weekday);
    if (i < 0) return null;
    return split.weekFor(weekdays.length)[i];
  }

  List<MovementSlot> movementsFor(DateTime date) {
    final day = dayFor(date);
    return day == null ? const <MovementSlot>[] : slots[day] ?? const [];
  }

  /// The whole seven-day week, rest days included.
  ///
  /// **Rest is part of the shape, not an absence.** Listing only training days
  /// meant Wednesday, Saturday and Sunday did not appear anywhere, so the one
  /// question the overview exists to answer — what does my week look like —
  /// could not be answered from it.
  List<({int weekday, String? day})> get week {
    final shape = split.weekFor(weekdays.length);
    return <({int weekday, String? day})>[
      for (var d = DateTime.monday; d <= DateTime.sunday; d++)
        (
          weekday: d,
          day: weekdays.contains(d) ? shape[weekdays.indexOf(d)] : null,
        ),
    ];
  }

  /// Slots worth looking at, because the numbers have stopped moving.
  List<MovementSlot> get stalled =>
      slots.values.expand((s) => s).where((s) => s.hasStalled).toList();
}

/// One movement's place in the week, and what has filled it.
@immutable
class MovementSlot {
  const MovementSlot({
    required this.id,
    required this.role,
    required this.movement,
    this.isMain = false,
    this.sessionsAtSameTop = 0,
    this.lastTopKg,
    this.lastTopReps,
  });

  final String id;

  /// What the slot is FOR, independent of what currently fills it — "horizontal
  /// press", "vertical pull", "hinge".
  ///
  /// **The role is the plan; the movement is this month's answer to it.** Swap
  /// a barbell bench for a dumbbell press and the slot has not changed, which
  /// is what lets the app say "your horizontal press has stalled" across a
  /// change of equipment instead of losing the thread every time somebody
  /// travels or a rack is busy.
  final String role;

  /// What is in the slot now.
  final String movement;

  /// Main lifts are not rotated. Progress is measured in them, and a number
  /// that changes movement every few weeks is not a trend.
  final bool isMain;

  /// How many sessions the top set has failed to improve.
  final int sessionsAtSameTop;

  /// The best set last time this slot came round.
  ///
  /// **The plan screen was numbers-free without these**, on a screen in an app
  /// whose whole design language is numerals — it could name the movements and
  /// say nothing about what you lift, which is the one thing you open it to
  /// check on the way to the gym.
  final double? lastTopKg;
  final int? lastTopReps;

  bool get hasHistory => lastTopKg != null && lastTopReps != null;

  /// Six sessions, and only for accessories.
  ///
  /// Six because it is long enough to rule out a bad week, an illness or a
  /// deliberately light session, and short enough that somebody is not spending
  /// two months on a movement that has stopped paying. Main lifts are excluded
  /// on purpose: a stalled squat is a programming problem — load, fatigue,
  /// sleep — and swapping the movement hides it rather than fixing it.
  bool get hasStalled => !isMain && sessionsAtSameTop >= 6;
}
