/// What the race screen says about a run that was a race: where it stands
/// among the runner's races, how it was run, and the training behind it.
///
/// **Derived in Dart, like every other thing the coach says about a number**
/// (`RunNote`, `CoachNote`, `RaceVerdict`). A race is the run a runner quotes
/// for years and the one a model would be most tempted to dress up, so every
/// sentence here is counted from the log and the result they confirmed. The
/// conversation is still one tap away for anything that needs judgement.
///
/// Nothing here branches on a plan's shape (ADR-0011). A race is a property of
/// the run (ADR-0049); a plan is found behind it by date, or is not, and the
/// screen draws the training section or does not.
library;

import 'package:mgk_units/mgk_units.dart';

import '../../recording/domain/best_effort.dart';
import '../../recording/domain/race_breakdown.dart';
import '../../recording/domain/run_race.dart';
import '../../recording/domain/run_summary.dart';
import 'plan_history.dart';
import 'plan_shape.dart';
import 'prescribed_distance.dart';
import 'race_day.dart';
import 'stored_plan.dart';

/// What a runner calls a race of [meters]: "Half marathon", or "15 km race"
/// where there is no word for it.
String raceLabel(double meters, UnitSystem unit) {
  final named = raceName(meters);
  if (named != null) return named;
  final d = Distance.meters(meters);
  final shown = unit.isMetric ? d.kilometers : d.miles;
  final whole = (shown - shown.roundToDouble()).abs() < 0.05;
  return '${d.format(unit, fractionDigits: whole ? 0 : 1)} race';
}

/// Whether two race distances are the same race.
///
/// Fifty metres, or one per cent on a long one, so a half entered as 21,097.5
/// and one typed as 21.1 km are the same distance and a 15K is not a 16K.
bool sameRaceDistance(double a, double b) =>
    (a - b).abs() <= (b * 0.01 > 50 ? b * 0.01 : 50);

// ---------------------------------------------------------------------------
// Offering to mark a race
// ---------------------------------------------------------------------------

/// The phone's distance may sit this far either side of a named race and the
/// run is still offered as one. Long, because GPS reads long in a race — 2.8%
/// on Sunday's half — and only a little short, because a training run of
/// 4.8 km is far more often a training run than a 5K the phone undercounted.
const double _offerLow = 0.96;
const double _offerHigh = 1.08;

/// The named race [run] looks like, in metres, or null when it does not look
/// like one — or is one already.
///
/// **Only an offer, never a decision.** It decides whether the summary shows a
/// quiet "Was this a race?" and which distance the sheet starts on; nothing is
/// marked until the runner says so. A treadmill run is never offered: nobody
/// races on one, and offering every 5 km on the belt would teach the runner to
/// ignore the line on the day it matters.
double? suggestedRaceDistance(RunSummary run) {
  if (run.race != null || run.type == 'treadmill') return null;
  for (final meters in kRecordDistancesMeters) {
    final ratio = run.distanceMeters / meters;
    if (ratio >= _offerLow && ratio <= _offerHigh) return meters;
  }
  return null;
}

/// The named race nearest [meters], for the sheet to start on when the run is
/// not near any of them. Never null: a runner marking a 7 km run as a race
/// still needs a starting point, and the nearest name is a better one than
/// none.
double nearestRaceDistance(double meters) {
  var best = kRecordDistancesMeters.first;
  for (final candidate in kRecordDistancesMeters) {
    if ((candidate - meters).abs() < (best - meters).abs()) best = candidate;
  }
  return best;
}

// ---------------------------------------------------------------------------
// Where this race stands
// ---------------------------------------------------------------------------

/// The line at the top of a race screen: what this race is among the runner's
/// races at the distance.
class RaceStanding {
  const RaceStanding({
    required this.headline,
    required this.detail,
    required this.isFirst,
    required this.isBest,
  });

  final String headline;
  final String detail;

  /// No race at this distance before it.
  final bool isFirst;

  /// Quicker than every other race at the distance, before or since.
  final bool isBest;
}

/// Where [run]'s race stands among the races in [history], or null when [run]
/// is not a race.
///
/// **First looks backwards; best looks everywhere.** "Your first half
/// marathon" stays true of the first one however many come after it. "Your
/// fastest" is a claim about now, so a race that has since been beaten no
/// longer makes it — the rule `RunNote` applies to records, for the same
/// reason: opening an old run must not congratulate a runner on a best they no
/// longer hold.
///
/// The time compared is each race's reported time — official where the runner
/// gave one, the phone's where they did not — because that is the number they
/// would say out loud.
RaceStanding? raceStandingFor(
  RunSummary run,
  List<RunSummary> history, {
  UnitSystem unit = UnitSystem.metric,
}) {
  final race = run.race;
  if (race == null) return null;
  final time = race.timeFor(run.duration);
  final label = raceLabel(race.distanceMeters, unit);
  final mid = midSentenceRaceName(label);

  final others = <RunSummary>[
    for (final other in history)
      if (other.race != null &&
          (run.id == null || other.id != run.id) &&
          sameRaceDistance(other.race!.distanceMeters, race.distanceMeters))
        other,
  ];
  final earlier = <RunSummary>[
    for (final other in others)
      if (other.startedAt.isBefore(run.startedAt)) other,
  ];

  Duration timeOf(RunSummary other) => other.race!.timeFor(other.duration);

  if (earlier.isEmpty) {
    return RaceStanding(
      headline: 'Your first $mid.',
      detail:
          'Every one after this is measured against '
          '${time.hoursMinutesSeconds}.',
      isFirst: true,
      isBest: others.every((other) => timeOf(other) > time),
    );
  }

  final best = others.map(timeOf).reduce((a, b) => a < b ? a : b);
  if (time < best) {
    final previous = earlier.map(timeOf).reduce((a, b) => a < b ? a : b);
    return RaceStanding(
      headline: 'Your fastest $mid.',
      detail:
          '${(previous - time).hoursMinutesSeconds} quicker than your previous '
          'best of ${previous.hoursMinutesSeconds}.',
      isFirst: false,
      isBest: true,
    );
  }

  final count = earlier.length + 1;
  return RaceStanding(
    headline: '$label number $count.',
    detail:
        'Your best is ${best.hoursMinutesSeconds}, '
        '${(time - best).hoursMinutesSeconds} quicker than this one.',
    isFirst: false,
    isBest: false,
  );
}

/// The records worth saying on a race screen: the fastest stretches inside the
/// race, **except the race's own distance**.
///
/// The phone's fastest 21.0975 km inside a half marathon is not the runner's
/// half marathon time — it is shorter than the course they actually ran, by
/// exactly the distance the phone over-read — so showing it beside the official
/// time would put two half marathon times on one screen and the smaller one
/// would be the wrong one. The race's own result is in [raceStandingFor]; the
/// 5K and 10K inside it are records like any other run's.
List<BestEffort> recordsInsideRace(List<BestEffort> records, RunRace race) =>
    <BestEffort>[
      for (final r in records)
        if (!sameRaceDistance(r.distanceMeters, race.distanceMeters) &&
            r.distanceMeters < race.distanceMeters)
          r,
    ];

// ---------------------------------------------------------------------------
// How it was run
// ---------------------------------------------------------------------------

/// The coach's line about how a race was run, from its two halves.
class RaceNote {
  const RaceNote({required this.headline, required this.detail});

  final String headline;
  final String detail;
}

/// A second half this much slower than the first is a fade worth naming. Three
/// per cent is about ten seconds a kilometre at five-minute pace — more than
/// the drift a hot day or one hill explains.
const double _fadeAt = 0.03;

/// A second half this much quicker is a negative split worth naming.
const double _negativeAt = 0.02;

/// A step between two sections this much slower is a drop worth pointing at.
/// Four per cent is about thirteen seconds a kilometre at 5:30 pace, past the
/// noise a proportional checkpoint carries (`raceBreakdownFor`).
const double _dropAt = 0.04;

/// What the coach makes of how [breakdown] was run, in one line and its
/// evidence.
///
/// Never null: every race was run some way, and an even race is worth saying
/// as much as a fade. The evidence is always the two halves' paces, so the
/// line can be checked against the sections drawn beneath it.
RaceNote raceNoteFor(
  RaceBreakdown breakdown, {
  UnitSystem unit = UnitSystem.metric,
}) {
  String pace(RaceSection s) =>
      Pace.secondsPerKilometer(s.paceSecondsPerKm).format(unit);
  final halves =
      'First half ${pace(breakdown.firstHalf)}, '
      'second half ${pace(breakdown.secondHalf)}.';
  final fade = breakdown.fade;

  if (fade >= _fadeAt) {
    final drop = _biggestDrop(breakdown);
    return RaceNote(
      headline: 'You slowed in the second half.',
      detail: drop == null
          ? '$halves Setting off a shade slower usually finishes quicker.'
          : '$halves The biggest drop came after ${_checkpoint(drop, unit)}.',
    );
  }
  if (fade <= -_negativeAt) {
    return RaceNote(
      headline: 'You finished faster than you started.',
      detail: '$halves A negative split, which is the way round to do it.',
    );
  }
  return RaceNote(
    headline: 'An even race.',
    detail:
        '$halves Holding one pace for the whole distance is the hardest part '
        'of racing.',
  );
}

/// The checkpoint, in course metres, after which the pace dropped most from
/// one section to the next, or null when no step was as much as [_dropAt].
///
/// **The biggest step, not the first.** "The pace held to 5K" is true of a
/// half run 5:15, 5:31, 5:53, 6:08 and points at the wrong place: the 16
/// seconds a kilometre lost after 5K are less than the 22 lost after 10K,
/// which is where the race went. Naming the largest step is checkable against
/// the bars drawn under the line.
double? _biggestDrop(RaceBreakdown breakdown) {
  final sections = breakdown.sections;
  double? at;
  var biggest = _dropAt;
  for (var i = 1; i < sections.length; i++) {
    final before = sections[i - 1].paceSecondsPerKm;
    final step = (sections[i].paceSecondsPerKm - before) / before;
    if (step >= biggest) {
      biggest = step;
      at = sections[i].fromMeters;
    }
  }
  return at;
}

/// "10K", "6 mi": a checkpoint as a runner says it.
String _checkpoint(double meters, UnitSystem unit) {
  if (unit.isMetric) {
    final km = meters / 1000;
    return km == km.roundToDouble()
        ? '${km.round()}K'
        : '${km.toStringAsFixed(1)}K';
  }
  final miles = Distance.meters(meters).miles;
  return '${miles.toStringAsFixed(miles < 10 ? 1 : 0)} mi';
}

/// A section as the race screen labels it: the checkpoint it ends at, the way
/// a results page does — "5K", "10K", "Finish".
String raceSectionLabel(RaceSection section, UnitSystem unit) =>
    section.isFinish ? 'Finish' : _checkpoint(section.toMeters, unit);

// ---------------------------------------------------------------------------
// The training behind it
// ---------------------------------------------------------------------------

/// The plan that was aimed at [run]'s race, or null when none was.
///
/// **By date, and only for a plan that had one.** A plan aimed at a race on
/// this day is the plan behind this race, whether it is still active, was
/// closed out with this race, or ended some other way. A plan with no date —
/// a horizon or a rhythm — was not aimed at a race and is never behind one, so
/// the training section is simply not drawn (the runner asked for it to be
/// hidden without a plan).
///
/// Newest wins where two plans named the same day, which only happens when a
/// runner rebuilt their plan partway through the block.
///
/// Asked of any run, marked or not, because the screen that shows it lets the
/// runner mark the race there and then; the section is only drawn once they
/// have.
LabelledPlan? planBehindRace(List<LabelledPlan> plans, RunSummary run) {
  LabelledPlan? found;
  for (final plan in plans) {
    final record = plan.record;
    final date = record.eventDate;
    if (record.shape != PlanShape.block || date == null) continue;
    if (daysBetweenDates(run.startedAt, date) == 0) found = plan;
  }
  return found;
}

/// The training inside a plan's window, as the race screen draws it.
class RaceBuildUp {
  const RaceBuildUp({
    required this.label,
    required this.weeks,
    required this.runs,
    required this.meters,
    required this.weeklyMeters,
    this.longest,
  });

  /// "Half marathon plan", "Marathon plan 2".
  final String label;

  /// The plan's length in weeks.
  final int weeks;

  /// Runs logged inside the plan, before race day.
  final int runs;

  /// Their distance, summed.
  final double meters;

  /// Distance per plan week, first week first. The race week holds only what
  /// was run before the race.
  final List<double> weeklyMeters;

  /// The longest run inside the plan, or null when there were none.
  final RunSummary? longest;

  /// The biggest week, in metres.
  double get peakWeekMeters =>
      weeklyMeters.isEmpty ? 0 : weeklyMeters.reduce((a, b) => a > b ? a : b);
}

/// What the runner did inside [plan] up to race day.
///
/// **Bounded by the plan, not by the log**, for `runsDuring`'s reason: a third
/// marathon block sits on top of years of running, and totalling the lot would
/// report a life rather than the block that just ended. Race day itself is
/// left out — the race is the thing the section leads up to, and counting it
/// would make the longest run in every marathon block the marathon.
RaceBuildUp buildUpFor(LabelledPlan plan, List<RunSummary> runs) {
  final record = plan.record;
  final start = record.startDate;
  final race = record.eventDate ?? addDays(start, record.weeks * 7 - 1);
  final weekly = List<double>.filled(record.weeks, 0);
  var count = 0;
  var meters = 0.0;
  RunSummary? longest;
  for (final run in runs) {
    final fromStart = daysBetweenDates(start, run.startedAt);
    if (fromStart < 0 || daysBetweenDates(run.startedAt, race) <= 0) continue;
    final week = fromStart ~/ 7;
    if (week >= weekly.length) continue;
    weekly[week] += run.distanceMeters;
    count++;
    meters += run.distanceMeters;
    if (longest == null || run.distanceMeters > longest.distanceMeters) {
      longest = run;
    }
  }
  return RaceBuildUp(
    label: plan.label,
    weeks: record.weeks,
    runs: count,
    meters: meters,
    weeklyMeters: weekly,
    longest: longest,
  );
}

/// Whether [run] is the race [plan] was aimed at: on its race day, and the
/// longest run of that day, which is how ADR-0027 already tells the race from
/// a warm-up jog (`raceRunOn`).
///
/// **And at least half the race distance.** ADR-0027 matches a race by day
/// alone, and rightly, when the runner is the one confirming it. Marking a run
/// automatically has nobody confirming, and a 3 km shakeout recorded on the
/// morning of a marathon, before the marathon itself exists in the log, would
/// otherwise be filed as the marathon. Half is far below anything a phone
/// under-reads a real race by.
bool isPlanRaceRun(StoredPlan plan, RunSummary run, List<RunSummary> runs) {
  final date = plan.profile.eventDate;
  final goal = plan.profile.goalDistanceMeters;
  if (date == null || goal == null) return false;
  if (shapeOf(plan.profile) != PlanShape.block) return false;
  if (daysBetweenDates(run.startedAt, date) != 0) return false;
  if (run.distanceMeters < goal / 2) return false;
  final race = raceRunOn(<RunSummary>[run, ...runs], date);
  return race == run || (race != null && race.id != null && race.id == run.id);
}
