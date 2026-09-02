/// Race day, the result, and the end of a plan — everything that happens when a
/// block arrives at the thing it was aimed at.
///
/// **A plan aimed at a date has an ending, and the app had none.** Race day was
/// the last row of the last week: a Sunday with a distance on it, indistinguishable
/// from the Tuesday before. Nothing said the day had come, nothing recorded what
/// the runner ran, and `plans.status` documented a `completed` value that no
/// line in the app had ever written — so sixteen weeks of training ended by
/// being quietly superseded the next time somebody built a plan.
///
/// Three decisions live here, and [ADR-0027](../../../../../docs/decisions/0027-a-plan-ends-on-race-day.md)
/// is where they are argued:
///
/// **The result is read from the log and confirmed by the runner.** A run
/// recorded on the day is the result, because completion is observed rather
/// than asserted ([ADR-0017](../../../../../docs/decisions/0017-the-coach-is-the-entry-point.md)).
/// The time is editable before it is confirmed, because a chip time and a GPS
/// time disagreeing is normal — the watch started in the pen, the line was
/// crossed forty seconds later, and the number on the certificate is the one
/// the runner will tell people. Neither figure is an error and neither is
/// discarded.
///
/// **The plan ends when the runner says so, and by itself if they never do.**
/// A race that has been and gone leaves the plan [RacePhase.awaiting] until it
/// is closed out. A runner who got injured in week eleven, never raced and
/// never opened the app again would otherwise carry an active marathon block
/// forever, so a plan whose race is more than [kRaceGraceDays] past closes
/// itself.
///
/// **Only a block has any of this.** [shapeOf] is asked once, here, and answers
/// null for a horizon, a rhythm and a log — none of which has a date to arrive
/// at. Every surface downstream takes a nullable [RaceOutlook] and draws it or
/// does not, so no widget learns that shapes exist (ADR-0011).
library;

import 'package:mgk_units/mgk_units.dart';

import '../../recording/domain/run_summary.dart';
import 'plan_shape.dart';
import 'prescribed_distance.dart';
import 'runner_profile.dart';
import 'stored_plan.dart';

/// How close race day has to be before the app starts saying so.
///
/// Ten days, which is inside the taper for every block this app builds and
/// outside it for none. A countdown that starts a month out is a countdown a
/// runner stops reading; one that starts on the morning has nothing to say
/// about the week they are already living in.
const int kRaceHorizonDays = 10;

/// How long the runner gets to close their own plan out before the app does it
/// for them.
///
/// Two weeks. Long enough that somebody who raced on Sunday and went on
/// holiday on Monday still gets to record what they ran; short enough that a
/// plan cannot outlive its race by a season. The number matters less than the
/// fact that it is finite — see [overdueClosureFor].
const int kRaceGraceDays = 14;

/// Where the runner stands relative to their race.
enum RacePhase {
  /// Inside [kRaceHorizonDays]. There is still training to do today, and the
  /// race is a fact about the week rather than about the day.
  approaching,

  /// The day itself.
  today,

  /// It has been and gone, and nobody has said what happened.
  awaiting,
}

/// The race, as the app has to talk about it today — or null when this plan is
/// not aimed at one.
///
/// Carries its own copy for the same reason [PlanHeadline] does: what to say
/// about a race is a property of the plan, and a card that composed the
/// sentence itself would be a card that knows what a block is.
class RaceOutlook {
  const RaceOutlook({
    required this.phase,
    required this.date,
    required this.distanceMeters,
    required this.daysAway,
    required this.name,
    required this.headline,
    required this.detail,
  });

  final RacePhase phase;

  /// Race day, date-only.
  final DateTime date;

  /// The distance entered, in metres. Metric stored, converted at display.
  final double distanceMeters;

  /// Whole days from today to [date]. Zero on the day, negative afterwards.
  final int daysAway;

  /// What the runner calls it: "Marathon", or the distance where there is no
  /// word for it.
  final String name;

  /// The card's line.
  final String headline;

  /// The sentence under it.
  final String detail;
}

/// What the app has to say about [plan]'s race on [today], or null when there
/// is nothing to say.
///
/// Null covers four different situations that all mean the same thing to a
/// screen — this plan has no race ([PlanShape.horizon], [PlanShape.rhythm],
/// [PlanShape.log]), or the race is further off than [kRaceHorizonDays], or it
/// is so long past that the plan should already have closed. A caller that
/// treated any of those as an error would be inventing a state; they are all
/// simply "draw the ordinary day".
RaceOutlook? raceOutlookFor(
  StoredPlan plan,
  DateTime today, {
  UnitSystem unit = UnitSystem.metric,
}) {
  final profile = plan.profile;
  // The one branch on shape in this feature, and it is here rather than in a
  // widget on purpose (ADR-0011). A horizon has a goal and no date; asking it
  // about race day would be asking about a race nobody has entered.
  if (shapeOf(profile) != PlanShape.block) return null;

  final date = profile.eventDate!;
  final goalMeters = profile.goalDistanceMeters!;
  final days = daysBetweenDates(today, date);
  final name = describeGoal(goalMeters, unit);
  final dateOnly = DateTime(date.year, date.month, date.day);

  if (days > kRaceHorizonDays) return null;
  if (days < -kRaceGraceDays) return null;

  if (days == 0) {
    return RaceOutlook(
      phase: RacePhase.today,
      date: dateOnly,
      distanceMeters: goalMeters,
      daysAway: 0,
      name: name,
      // Not "Marathon · 42 km" over a Start button that looks like every other
      // morning. The day is the thing being announced, and the distance is
      // underneath it where it has been for sixteen weeks.
      headline: 'Race day',
      detail: 'Everything is already done. Go and run it.',
    );
  }

  if (days > 0) {
    return RaceOutlook(
      phase: RacePhase.approaching,
      date: dateOnly,
      distanceMeters: goalMeters,
      daysAway: days,
      name: name,
      headline: days == 1 ? '$name tomorrow' : '$name in $days days',
      // The taper is the part runners distrust, so the line says what the
      // small week is for rather than leaving them to conclude the plan has
      // given up on them.
      detail: 'The work is behind you. What is left is arriving fresh.',
    );
  }

  return RaceOutlook(
    phase: RacePhase.awaiting,
    date: dateOnly,
    distanceMeters: goalMeters,
    daysAway: days,
    name: name,
    headline: 'How did the ${midSentenceRaceName(name)} go?',
    detail: days == -1
        ? 'Yesterday was race day. Tell me and I will close the plan out.'
        : 'Race day was ${-days} days ago. Tell me and I will close the plan '
              'out.',
  );
}

/// A race name as it reads inside a sentence: "how did the marathon go".
///
/// **Only the first letter, and that is the point.** A blanket `toLowerCase`
/// turns "5K" into "5k" and "Half marathon" into something correct only by
/// luck; dropping the first capital handles "Marathon" and "Half marathon",
/// leaves "5K" and "10K" as the runner writes them, and does nothing at all to
/// a goal with no name ("12 km"), which is already lower case.
///
/// The same problem [PlanHeadline] solves with its own private helper. Public
/// here because the sheet that asks for the result needs it too, and two
/// copies would eventually disagree about a distance somebody adds later.
String midSentenceRaceName(String name) =>
    name.isEmpty ? name : '${name[0].toLowerCase()}${name.substring(1)}';

/// Where a race time came from.
enum RaceTimeSource {
  /// Read off a run recorded on the day. The runner typed nothing.
  logged,

  /// Given by the runner — a chip time, or a race their phone sat out.
  entered,
}

/// What the runner ran, and in what time.
///
/// **The distance is the race distance, never the trace's.** A marathon whose
/// watch read 42.61 km is still a marathon: the extra 400 m is the weaving,
/// the missed tangents and the walk to the barrier, and reporting it as the
/// distance would make every runner's marathon a slightly different length.
/// What the phone measured is kept as [watchDistanceMeters], beside the time it
/// measured, so the two can be shown disagreeing rather than one quietly
/// replacing the other.
class RaceResult {
  const RaceResult({
    required this.distanceMeters,
    required this.time,
    required this.source,
    this.watchTime,
    this.watchDistanceMeters,
  });

  /// The race distance in metres — the plan's goal.
  final double distanceMeters;

  /// The finish time being reported.
  final Duration time;

  final RaceTimeSource source;

  /// What the phone made of it, when there is a recorded run and it disagrees
  /// with [time]. Null when nothing was recorded, and null when the two agree —
  /// a "difference" of zero is not a difference and printing it twice would
  /// invite the runner to look for one.
  final Duration? watchTime;

  /// The distance the phone measured, when there is a recorded run. Null for a
  /// race the phone sat out.
  final double? watchDistanceMeters;

  /// Whether the runner's own figure and the phone's disagree — the ordinary
  /// case in a chip-timed race, and not an error.
  bool get disagrees => watchTime != null;

  /// Average pace over the **race** distance, in seconds per kilometre.
  ///
  /// Derived from [distanceMeters] rather than from the trace, so it is the
  /// pace the result implies. A pace computed against 42.61 km would be the
  /// pace they ran, which is a different and less useful number: nobody sets
  /// out to run 42.61 km.
  double get paceSecondsPerKm => time.inSeconds / (distanceMeters / 1000);
}

/// The run that was the race, or null when the phone did not record one.
///
/// **Matched by the day, and nothing else.** No distance tolerance, for
/// ADR-0017's reason: a runner who covered 41.9 km of a marathon by their
/// phone's reckoning ran the marathon, and an app that refused to call it the
/// race because of a GPS shortfall would be right about a number and wrong
/// about a person.
///
/// The longest run of the day wins where there are several, because a race
/// morning routinely contains a shakeout jog and a warm-up. Ties go to the
/// first recorded, which cannot matter — two runs of identical length on race
/// day is not a case anyone needs a rule for.
RunSummary? raceRunOn(List<RunSummary> runs, DateTime date) {
  RunSummary? best;
  for (final run in runs) {
    if (daysBetweenDates(run.startedAt, date) != 0) continue;
    if (best == null || run.distanceMeters > best.distanceMeters) best = run;
  }
  return best;
}

/// What the runner ran on race day, or null when nothing is known yet.
///
/// [entered] is the time the runner gave, when they gave one. It wins over the
/// log — that is the whole point of it — and the recorded run is kept beside it
/// rather than discarded, so the surface can show a chip time and a watch time
/// side by side instead of pretending one of them did not happen.
///
/// Null means the app genuinely does not know: no run on the day and nothing
/// typed. It is not the same as "they did not race", which is a thing the
/// runner has to say (see [PlanClosure.didNotRace]) — the phone being in a bag
/// at the finish is not evidence of anything.
RaceResult? raceResultFor(
  StoredPlan plan,
  List<RunSummary> runs, {
  Duration? entered,
}) {
  final profile = plan.profile;
  if (shapeOf(profile) != PlanShape.block) return null;

  final goalMeters = profile.goalDistanceMeters!;
  final run = raceRunOn(runs, profile.eventDate!);

  if (entered != null) {
    final watch = run?.duration;
    return RaceResult(
      distanceMeters: goalMeters,
      time: entered,
      source: RaceTimeSource.entered,
      // Only when they differ. Two identical figures under two different
      // labels reads as a discrepancy the runner is being asked to resolve.
      watchTime: watch == entered ? null : watch,
      watchDistanceMeters: run?.distanceMeters,
    );
  }

  if (run == null) return null;
  return RaceResult(
    distanceMeters: goalMeters,
    time: run.duration,
    source: RaceTimeSource.logged,
    watchDistanceMeters: run.distanceMeters,
  );
}

/// How a plan stopped being the runner's plan, once it reached its own end.
///
/// The two wire values `plans.status` has documented since the schema was
/// written and nothing has ever produced. `superseded` — the third — is not
/// here because it is not an ending: it is what happens to a plan when another
/// one starts, which can happen in week two.
enum PlanClosure {
  /// They got to the line. Wire value `completed`.
  raced,

  /// Race day came and went without them. Wire value `abandoned`.
  ///
  /// **Not a verdict.** Injury, a cancelled event, a changed mind and an entry
  /// never made all land here, and the app has no way to tell them apart and no
  /// business trying. Nothing on any screen says the word.
  didNotRace,
}

/// Whether [plan] has outlived its race by long enough that the app should
/// close it without being asked, and as what.
///
/// **This exists for the runner who never races**, which is common and is the
/// case a status nobody writes fails worst. Somebody who tore a calf in week
/// eleven does not open the app to file a result; they stop opening the app.
/// Left alone their block stays `active` forever, so the coach keeps briefing
/// against a marathon that happened last spring and Profile never lists it
/// among the things they have trained for.
///
/// Returns null while the plan is still the runner's to close — that is, right
/// up to [kRaceGraceDays] past the date, which is the window
/// [RacePhase.awaiting] is asking in.
///
/// The closure is read off the log, not guessed: a run on the day says they
/// raced whatever they never got round to telling us, and no run says they did
/// not. That can be wrong — a runner whose phone stayed in the hotel raced and
/// is recorded as not having — and it is the direction the mistake has to fall,
/// because the alternative is the app asserting a race nothing evidences.
PlanClosure? overdueClosureFor(
  StoredPlan plan,
  List<RunSummary> runs,
  DateTime now,
) {
  final profile = plan.profile;
  if (shapeOf(profile) != PlanShape.block) return null;
  if (daysBetweenDates(now, profile.eventDate!) >= -kRaceGraceDays) return null;
  return raceRunOn(runs, profile.eventDate!) == null
      ? PlanClosure.didNotRace
      : PlanClosure.raced;
}

/// What the coach says about a finished block, in one line and its evidence.
///
/// **Derived in Dart, exactly like [CoachNote] and [RunNote].** This is the
/// moment in the product where a model would be most tempted to embellish and
/// least able to be checked — sixteen weeks and a number the runner will
/// remember for years — so nothing here is generated. The coach's *judgement*
/// still has somewhere to go: the finish screen hands the conversation an
/// opener, and the brief carries the result, so a runner who wants to talk
/// about it is talking to a coach that knows what they ran (CLAUDE.md rule 2).
class RaceVerdict {
  const RaceVerdict({required this.headline, required this.detail});

  final String headline;
  final String detail;
}

/// The coach's word on a finished plan.
///
/// [result] is null for a runner who did not race, and that case gets a line
/// too — arguably it needs one more. Somebody who trained for eleven weeks and
/// then could not start has done eleven weeks of running, and a screen that
/// went quiet on them would be the app treating the race as the only part that
/// counted.
RaceVerdict raceVerdict({
  required StoredPlan plan,
  required RaceResult? result,
  required List<RunSummary> runs,
  UnitSystem unit = UnitSystem.metric,
}) {
  final ran = runsDuring(plan, runs);
  final weeks = plan.skeleton.weeks.length;
  final meters = ran.fold<double>(0, (sum, r) => sum + r.distanceMeters);
  final covered = Distance.meters(meters).format(unit, fractionDigits: 0);
  // "1 runs" is the tell that a sentence was assembled rather than written, and
  // it lands on exactly the runner least well served by this screen — the one
  // with almost nothing in the window.
  final ranCount = '${ran.length} ${ran.length == 1 ? 'run' : 'runs'}';

  if (result == null) {
    return RaceVerdict(
      headline: 'The training happened either way.',
      detail: ran.isEmpty
          // No plan, no runs, nothing to point at. Silence would be worse than
          // a short sentence: the runner is looking at the end of something.
          ? 'Race day has been and gone. Whenever you want to start something '
                'new, tell me what it is.'
          : '$ranCount and $covered over $weeks weeks. None of that is undone '
                'by a race you did not run, and the fitness is still there for '
                'the next one.',
    );
  }

  final pace = Pace.secondsPerKilometer(result.paceSecondsPerKm).format(unit);
  return RaceVerdict(
    headline: 'That is the block done.',
    // Every figure here is counted rather than asserted: the runs are the
    // runner's own log, the pace is the result divided by the race distance,
    // and the week count is the arc that was validated before it was stored.
    detail: ran.isEmpty
        ? '${result.time.hoursMinutesSeconds} at $pace. '
              'That is the one that counts.'
        : '${result.time.hoursMinutesSeconds} at $pace, off $ranCount and '
              '$covered across $weeks weeks.',
  );
}

/// The runs that fall inside [plan]'s arc, newest first.
///
/// **Bounded by the plan, not by the log.** A runner's third marathon block
/// sits on top of years of running, and a finish screen totalling the lot would
/// be reporting their life rather than the thing that just ended. The window
/// runs from the plan's own [StoredPlan.startDate] to race day inclusive, so
/// the race itself is in it.
List<RunSummary> runsDuring(StoredPlan plan, List<RunSummary> runs) {
  // Race day where there is one, and the last day of the arc otherwise — so
  // this reads sensibly for a horizon as well, which has weeks and no date.
  final last =
      plan.profile.eventDate ??
      addDays(plan.startDate, plan.skeleton.weeks.length * 7 - 1);
  return <RunSummary>[
    for (final run in runs)
      if (daysBetweenDates(plan.startDate, run.startedAt) >= 0 &&
          daysBetweenDates(run.startedAt, last) >= 0)
        run,
  ]..sort((a, b) => b.startedAt.compareTo(a.startedAt));
}

/// The sentence handed to the coach when the runner wants to talk about it.
///
/// Written here rather than at the button for [AdjustReasonsSheet]'s reason: it
/// travels the same path a typed sentence does, and a two-word prompt gets a
/// two-word reading of it. The result is stated so the coach is answering about
/// the race the runner actually ran rather than asking them what they did.
String raceChatOpener({
  required RunnerProfile profile,
  required RaceResult? result,
  UnitSystem unit = UnitSystem.metric,
}) {
  final name = midSentenceRaceName(
    describeGoal(profile.goalDistanceMeters!, unit),
  );
  if (result == null) {
    return 'I did not end up running my $name. Where does that leave me, and '
        'what should I be doing now?';
  }
  return 'I ran my $name in ${result.time.hoursMinutesSeconds}. What do you '
      'make of it, and what should I do next?';
}
