import 'package:mgk_units/mgk_units.dart';
import '../../recording/domain/run_summary.dart';
import '../presentation/session_labels.dart';
import 'plan_shape.dart';
import 'prescribed_distance.dart';
import 'race_day.dart';
import 'readiness.dart';
import 'runner_profile.dart';
import 'stored_plan.dart';
import 'training_plan.dart';

/// What the top of the Plan tab says: what the runner is working on, and where
/// they are in it.
///
/// **This exists so no widget branches on [PlanShape].** A block counts down to
/// a date, a horizon counts up toward a distance, and a rhythm counts how often
/// the runner has turned up — three different sentences from three different
/// facts. Computing them here keeps that where the shapes live; the strip that
/// draws them takes two strings and asks no questions
/// ([ADR-0011](../../../../../docs/decisions/0011-a-plan-has-a-shape.md)).
class PlanHeadline {
  const PlanHeadline({required this.goal, required this.position});

  /// The larger line: what they are training for.
  final String goal;

  /// The smaller line: where they are in it.
  final String position;
}

/// Writes the headline for [plan].
///
/// [completedThisPlan] is how many of the plan's sessions the runner has
/// actually done — the only measure a rhythm has, since it has no ramp to
/// track and no date to count down to. Ignored by the other shapes.
PlanHeadline planHeadline(
  StoredPlan plan,
  DateTime today, {
  UnitSystem unit = UnitSystem.metric,
  int completedThisPlan = 0,
  Readiness? readiness,
}) {
  final profile = plan.profile;
  final shape = shapeOf(profile);
  final goalMeters = profile.goalDistanceMeters;
  final goal = goalMeters == null ? null : describeGoal(goalMeters, unit);

  switch (shape) {
    case PlanShape.block:
      final days = daysBetweenDates(today, profile.eventDate!);
      final weeks = plan.skeleton.weeks.length;
      final current = plan.weekIndexOn(today);
      // Before the plan's first Monday there is no current week (ADR-0034):
      // `weekIndexOn` answers 1, and "week 1 of 16" on the Wednesday before it
      // disagreed with the week below it, headed "Starts Monday 5 Oct". The
      // countdown still counts; the week number waits for the start.
      if (!plan.hasStartedBy(today)) {
        return PlanHeadline(
          goal: raceName(goalMeters!) ?? '$goal goal',
          position: '$days days · ${_starts(plan)}',
        );
      }
      return PlanHeadline(
        // "Marathon", not "Marathon goal" — the word is already the goal.
        goal: raceName(goalMeters!) ?? '$goal goal',
        // **A countdown stops being a countdown at zero.** "0 days · week 16 of
        // 16" is arithmetic where the runner wants the word, and "Event passed"
        // was a shrug at the most significant day in the plan — it said the
        // date had gone by and nothing about the block being over or about
        // anybody being asked how it went (ADR-0027). Both were the same
        // mistake: carrying a subtraction all the way to the screen.
        position: switch (days) {
          0 => 'race day · week $current of $weeks',
          1 => 'tomorrow · week $current of $weeks',
          // The line's job is "where are you in this", and after the date the
          // honest answer is not a week number — it is that the block is over
          // and the app is waiting to be told how it went. A plan only stays
          // here for a fortnight before it closes itself.
          < 0 => 'waiting on your result',
          _ => '$days days · week $current of $weeks',
        },
      );

    case PlanShape.horizon:
      // No date to count down to, so the count is of readiness — the only thing
      // a horizon is actually progressing toward. "Week 9 · no date set" said
      // where they were in a plan and nothing about whether it was working.
      final current = plan.hasStartedBy(today)
          ? 'week ${plan.weekIndexOn(today)}'
          : _starts(plan);
      return PlanHeadline(
        goal: 'Building toward ${_lowerIfNamed(goalMeters!, goal!)}',
        position: readiness == null
            ? '$current · no date set'
            : '$current · ${readiness.summary}',
      );

    case PlanShape.rhythm:
      // Consistency is the training state here, not a score. There is no ramp
      // and no date, so whether they have been turning up is the only thing
      // there is to measure — the same class of fact as "week 1 of 16", which
      // is why it is not the streak the product spec puts out of scope.
      final commitment = profile.commitments.isEmpty
          ? null
          : profile.commitments.first;
      final name = commitment?.label;
      final days = profile.daysPerWeek;
      final cadence = '$days ${_plural(days, 'run')} a week';
      return PlanHeadline(
        goal: name == null ? 'Your week' : 'Your $name week',
        position: completedThisPlan == 0
            ? cadence
            : '$cadence · ${_turnedUp(completedThisPlan, name)}',
      );

    case PlanShape.log:
      return const PlanHeadline(goal: 'Your runs', position: 'no plan set');
  }
}

/// "starts Monday 5 Oct": where a plan still ahead of its first Monday is.
String _starts(StoredPlan plan) => 'starts ${dayAndDate(plan.startDate)}';

/// What the Today card is headed. **Just "Today".**
///
/// It used to append the training phase for a shape that has one — "Today ·
/// Base". Two things were wrong with that. It leaked block vocabulary onto
/// plans with no phases, which is why this function exists at all: the fourth
/// such leak, after the headline, the outlook and the week subtitle. And even
/// where the phase was real it was jargon on the screen a runner opens in a
/// hurry, sitting under a header that already says "week 4 of 16" — the third
/// "where am I" indicator stacked in one card.
///
/// Kept as a function rather than inlined as a constant: the heading is a
/// property of the plan's shape, and the next thing worth putting here (a
/// rhythm's own word for the day, say) will need the profile again.
String todayHeading(RunnerProfile profile, SkeletonWeek slot) => 'Today';

/// "14 parkruns" where they named it, "14 so far" where they did not.
///
/// Named on purpose: "14 parkruns" is a fact about their running, where "14
/// sessions completed" is a progress bar wearing a sentence. The runner's own
/// word for the thing is what makes it the former.
String _turnedUp(int count, String? label) =>
    label == null ? '$count so far' : '$count ${_plural(count, label)}';

String _plural(int count, String label) =>
    count == 1 || label.endsWith('s') ? label : '${label}s';

/// How many times the runner has turned up, over the last [turnedUpWindow].
///
/// For a rhythm with a named commitment ("parkrun, Saturdays") this counts runs
/// on that weekday, so the number is *parkruns* rather than runs in general —
/// which is what the runner would count themselves.
///
/// **Counted over a window, not since the plan started.** A first version
/// counted from `plan.startDate` and showed a parkrun regular of three years a
/// count of zero, because the plan row was created this morning. The habit
/// predates the app; the plan row is an implementation detail of the app
/// knowing about it.
///
/// Deliberately not "sessions marked complete" either: a runner who turned up
/// and ran has turned up, whether or not they later tapped a button about it.
int turnedUpCount(
  StoredPlan plan,
  List<RunSummary> runs, {
  required DateTime now,
  Duration window = turnedUpWindow,
}) {
  if (shapeOf(plan.profile).progresses) return 0;
  final since = now.subtract(window);
  final byDay = <int, PlanCommitment>{
    for (final c in plan.profile.commitments) c.weekday: c,
  };
  var count = 0;
  for (final run in runs) {
    if (run.startedAt.isBefore(since)) continue;
    if (run.startedAt.isAfter(now)) continue;
    if (byDay.isEmpty) {
      count++;
      continue;
    }
    final commitment = byDay[run.startedAt.weekday];
    if (commitment == null) continue;
    // The right day is not enough: a two-kilometre jog on a Saturday is not a
    // parkrun. Near enough is, though — the same tolerance the plan uses
    // everywhere else.
    final asked = commitment.distanceMeters;
    if (asked != null) {
      final band = toleranceFor(roundPrescribed(asked));
      if (run.distanceMeters < band.low || run.distanceMeters > band.high) {
        continue;
      }
    }
    count++;
  }
  return count;
}

/// A year. Long enough that a settled habit shows a number worth seeing, short
/// enough that it is a statement about the runner now rather than a lifetime
/// total that can only ever go up.
const Duration turnedUpWindow = Duration(days: 365);

/// The card that shows the whole plan: what to head it, and what to say under
/// the arc.
class PlanOutlook {
  const PlanOutlook({required this.title, required this.caption});

  final String title;
  final String caption;
}

/// Written here rather than in the card, for the same reason [planHeadline] is:
/// a rhythm has no peak and nothing to taper into, and a card that said "peaks
/// in week 12, then tapers" over a flat arc would be describing a block the
/// runner is not on.
PlanOutlook planOutlook(
  StoredPlan plan, {
  UnitSystem unit = UnitSystem.metric,
  Readiness? readiness,
}) {
  final weeks = plan.skeleton.weeks;
  final peak = weeks.isEmpty
      ? null
      : weeks.reduce((a, b) => a.volumeMeters > b.volumeMeters ? a : b);
  final peakVolume = peak == null
      ? ''
      : Distance.meters(peak.volumeMeters).format(unit, fractionDigits: 0);
  const firmsUp = 'Sessions firm up about a week ahead.';

  switch (shapeOf(plan.profile)) {
    case PlanShape.block:
      return PlanOutlook(
        title: 'The whole block',
        caption:
            'Peaks at $peakVolume in week ${peak?.index}, then tapers. $firmsUp',
      );
    case PlanShape.horizon:
      final goalMeters = plan.profile.goalDistanceMeters;
      final note = readiness == null || goalMeters == null
          ? null
          : readinessNote(readiness, goalMeters);
      return PlanOutlook(
        title: 'The plan so far',
        caption:
            note ??
            'Builds toward $peakVolume a week and keeps going — there is no '
                'end date to taper into yet. $firmsUp',
      );
    case PlanShape.rhythm:
      return PlanOutlook(
        title: 'Your weeks',
        caption:
            'The same shape every week, at about $peakVolume. It does not '
            'build to anything and it does not run out. Ask the coach whenever '
            'you want it changed.',
      );
    case PlanShape.log:
      return const PlanOutlook(
        title: 'Your weeks',
        caption: 'No plan set yet.',
      );
  }
}

/// The line under a week's dates: what kind of week it is and how far.
///
/// A phase name and a week number are block vocabulary. "Base · 20 km planned ·
/// week 1" over a parkrun runner's week claims a training phase they are not in
/// and an ordinal in a plan that does not count — the third place the same leak
/// appeared, after the headline and the outlook.
String weekSubtitle(
  StoredPlan plan,
  SkeletonWeek slot, {
  UnitSystem unit = UnitSystem.metric,
  bool provisional = false,
  TrainingWeek? week,
  bool showWeekNumber = true,
}) {
  // The sum of the rows on screen, when there are rows. Prescriptions are
  // rounded in the runner's own unit, so converting the exact stored total
  // would print a header that does not match what is beneath it — five
  // sessions rounded to whole miles add to 24 where 40 km converts to 25. A
  // runner who adds up seven rows and gets a different number has found a bug,
  // whatever the tolerance says.
  final bool raceWeek = raceWeekdayIn(plan, slot) != null;
  final volume = week == null
      ? Distance.meters(
          raceWeek ? slot.beforeRaceMeters : slot.volumeMeters,
        ).format(unit, fractionDigits: 0)
      : formatPrescribedTotal(week.runs.map((s) => s.distanceMeters), unit);

  if (!shapeOf(plan.profile).progresses) {
    return provisional ? '$volume · firms up closer' : '$volume planned';
  }

  // The week of the race says so. "Taper · 24 km planned" over it was true of
  // the arithmetic and silent about the only thing in the week that matters.
  if (raceWeek) {
    final ordinal = showWeekNumber ? ' · week ${slot.index}' : '';
    return 'Race week · $volume before the race$ordinal';
  }

  final phase = slot.isDeload ? 'Deload' : phaseLabel(slot.phase);
  // The ordinal is dropped where the screen already carries it. On the plan
  // screen the header reads "week 1 of 16" a hundred pixels above this line,
  // and "week 1" underneath adds nothing except the loss of the denominator
  // that made the header worth reading — the same stacking of "where am I"
  // indicators that [todayHeading] above was trimmed for.
  //
  // The calendar keeps it. Its rows are titled with a date range, so this is
  // the only place the week number appears at all.
  final ordinal = showWeekNumber ? ' · week ${slot.index}' : '';
  return provisional
      ? '$phase · $volume$ordinal · firms up closer'
      : '$phase · $volume planned$ordinal';
}

/// "a marathon" rather than "Marathon" mid-sentence.
String _lowerIfNamed(double meters, String goal) {
  final name = raceName(meters);
  if (name == null) return goal;
  final article = RegExp('^[aeiou]', caseSensitive: false).hasMatch(name)
      ? 'an'
      : 'a';
  return '$article ${name.toLowerCase()}';
}
