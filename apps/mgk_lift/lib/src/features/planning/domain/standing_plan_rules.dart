import 'standing_plan.dart';
import 'training_split.dart';

/// What makes a standing plan usable, checked rather than requested.
///
/// The same principle the load rule follows and the split selection follows:
/// a property the app can decide exactly is not left to something that answers
/// in prose. `PlanValidator` does this for a session's weights; this does it
/// for the shape of the plan those sessions come out of.
///
/// **Every rule here is one a generated plan has actually got wrong**, or one
/// where getting it wrong is silent. A plan with an empty day still renders, a
/// plan whose split disagrees with its day count still renders, and a plan with
/// no main lift trains somebody for months on cable work without ever saying so.
abstract final class StandingPlanRules {
  /// Reasons this plan cannot be shown. Empty means usable.
  ///
  /// Phrased as instructions rather than complaints, so the list can go
  /// straight back to whatever produced the plan — the shape `PlanValidator`
  /// already uses, for the same reason.
  static List<String> violations(StandingPlan plan) {
    final out = <String>[];

    if (plan.weekdays.isEmpty) {
      out.add('Give the plan at least one training day.');
      return out;
    }

    if (plan.weekdays.length > 7) {
      out.add('A week has seven days; use no more than seven.');
    }

    if (plan.weekdays.toSet().length != plan.weekdays.length) {
      out.add('Each training day must be a different weekday.');
    }

    for (final d in plan.weekdays) {
      if (d < DateTime.monday || d > DateTime.sunday) {
        out.add('Weekdays run 1 to 7; $d is not one.');
      }
    }

    // The split is chosen from the day count, so the two disagreeing means one
    // of them was overridden without the other being told.
    final expected = TrainingSplit.forDays(plan.weekdays.length);
    if (plan.split != expected) {
      out.add(
        'A ${plan.weekdays.length}-day week is ${expected.name}, '
        'not ${plan.split.name}.',
      );
    }

    // Every day the week actually runs needs movements. An empty day renders
    // perfectly happily as a session with nothing in it.
    final days = plan.split.weekFor(plan.weekdays.length).toSet();
    for (final day in days) {
      final slots = plan.slots[day];
      if (slots == null || slots.isEmpty) {
        out.add('Put at least one movement in $day.');
      }
    }

    // Slots the plan holds for days it never trains are not a crash, they are a
    // plan that quietly disagrees with itself about what it is.
    for (final day in plan.slots.keys) {
      if (!days.contains(day)) {
        out.add('$day is not part of a ${plan.split.name} week; remove it.');
      }
    }

    // A plan of nothing but accessories never progresses and never says so,
    // because the stall rule deliberately exempts main lifts.
    if (!plan.slots.values.expand((s) => s).any((s) => s.isMain)) {
      out.add(
        'Every plan needs at least one main lift to measure progress in.',
      );
    }

    return out;
  }

  static bool isUsable(StandingPlan plan) => violations(plan).isEmpty;
}
