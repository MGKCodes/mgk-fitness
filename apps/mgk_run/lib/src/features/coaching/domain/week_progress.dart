import 'package:mgk_units/mgk_units.dart';
import '../../recording/domain/run_summary.dart';
import '../presentation/session_labels.dart';
import 'prescribed_distance.dart';
import 'session_status.dart';
import 'stored_plan.dart';
import 'training_plan.dart';

/// What became of a prescribed day.
///
/// **Derived on read, never stored** — the same reason `shapeOf()` derives
/// rather than stores. A stored completion is one more field that can disagree
/// with the log it claims to describe, and it did: a session could be marked
/// done with no run anywhere in the runner's history
/// ([ADR-0017](../../../../../docs/decisions/0017-the-coach-is-the-entry-point.md)).
enum DayOutcome {
  /// A run exists on the day.
  done,

  /// The day has passed with no run against it, and was not skipped.
  missed,

  /// The runner told the coach they were not doing it.
  skipped,

  /// Today. **Never missed** — the evening is still theirs.
  today,

  /// Still to come.
  upcoming,
}

/// Whether any of [runs] falls on [date].
///
/// **A run on the day satisfies the day, at any distance.** Telling a runner
/// who covered 8.5 km of a prescribed 9 km that they missed it is the app being
/// right about a number and wrong about a person; a shortfall is something the
/// coach can raise in a sentence. This is deliberately looser than
/// [turnedUpCount], which does band by distance — a rhythm is measured by
/// turning up to a *specific* thing, where a plan session is measured by being
/// run at all.
///
/// Nothing here cares how the run was recorded. A treadmill run typed into the
/// coach arrives as a [RunSummary] exactly like a tracked one, which is what
/// makes conversation a complete way in rather than a convenience.
bool ranOn(DateTime date, List<RunSummary> runs) {
  for (final run in runs) {
    if (daysBetweenDates(run.startedAt, date) == 0) return true;
  }
  return false;
}

/// What became of the prescribed day on [date].
///
/// [since] is the earliest day this plan can be held to. **A day before it
/// cannot have been missed**, and saying otherwise is how a plan built on a
/// Thursday greeted its runner with "3 sessions missed this week — Monday,
/// Tuesday, Wednesday" for days that predated its own existence.
///
/// Note it is *not* simply `plan.startDate`: that is the Monday week 1 aligns
/// to, which is on or before the day the runner actually committed. The caller
/// decides what it can honestly claim — see `home_shell.dart`, which passes
/// today for a plan still in its first week because nothing stored can date it
/// more precisely than that.
DayOutcome outcomeOn({
  required DateTime date,
  required DateTime now,
  required List<RunSummary> runs,
  SessionStatus status = SessionStatus.planned,
  DateTime? since,
}) {
  if (ranOn(date, runs)) return DayOutcome.done;
  if (status.isSkipped) return DayOutcome.skipped;

  // Drawn as still-to-come rather than as a gap: the plan was not asking for
  // anything yet, so there is nothing to mark either way.
  if (since != null && daysBetweenDates(since, date) < 0) {
    return DayOutcome.upcoming;
  }

  final days = daysBetweenDates(now, date);
  if (days == 0) return DayOutcome.today;
  return days > 0 ? DayOutcome.upcoming : DayOutcome.missed;
}

/// Every prescribed day of [week], by weekday, and what became of it.
///
/// Rest days are absent rather than present-and-empty: there is nothing to
/// complete on a day the plan asked for nothing.
Map<int, DayOutcome> weekOutcomes({
  required TrainingWeek week,
  required DateTime weekStart,
  required DateTime now,
  required List<RunSummary> runs,
  SessionStatus Function(int weekday)? statusFor,
  DateTime? since,
}) {
  final out = <int, DayOutcome>{};
  for (final session in week.runs) {
    final date = addDays(weekStart, session.weekday - 1);
    out[session.weekday] = outcomeOn(
      date: date,
      now: now,
      runs: runs,
      status: statusFor?.call(session.weekday) ?? SessionStatus.planned,
      since: since,
    );
  }
  return out;
}

/// One day of the week, as the plan asked for it and as it actually went.
///
/// The unit [weekAsRun] is made of, and the thing [weekOutcomes] cannot say. A
/// day the plan asked nothing of has no entry there at all — rest days are
/// absent rather than present-and-empty, which is right for drawing a week and
/// wrong for rewriting one. A run on a rest day is invisible to it, and that
/// run is precisely what the coach was missing: a runner who went out on a
/// Wednesday the plan left blank and then asked to have their week adjusted got
/// all seven days reshuffled as though Wednesday had never happened.
class DayAsRun {
  const DayAsRun({
    required this.weekday,
    required this.date,
    required this.hasPassed,
    required this.ranMeters,
    this.prescribed,
    this.outcome,
  });

  /// `DateTime.monday`..`DateTime.sunday`.
  final int weekday;

  final DateTime date;

  /// The day is behind us. **Today has not passed** — the evening is still
  /// theirs, which is the same line [outcomeOn] draws when it refuses to call
  /// today missed.
  final bool hasPassed;

  /// What the plan asked for, or null on a day it asked for nothing.
  ///
  /// Runs only. A strength day prescribes no distance at all (ADR-0010), so a
  /// run on one is as unplanned as a run on a rest day — the gym session it
  /// shares the day with is not the thing that got run.
  final PlannedSession? prescribed;

  /// What became of that prescription — null exactly when there was none.
  ///
  /// There is nothing to complete on a day the plan asked nothing of, and
  /// marking such a day [DayOutcome.done] would be the app congratulating
  /// itself for a session it never wrote.
  final DayOutcome? outcome;

  /// Every metre run on the day, summed. Two runs on a Wednesday are one
  /// Wednesday: the day is what the plan schedules against, not the run.
  final double ranMeters;

  bool get isDone => outcome == DayOutcome.done;
  bool get isMissed => outcome == DayOutcome.missed;
  bool get isSkipped => outcome == DayOutcome.skipped;

  /// A run on a day the plan prescribed nothing — the case this whole file was
  /// widened for.
  bool get isUnplanned => prescribed == null && ranMeters > 0;

  /// A prescription still to come: today or later, with nothing run against it
  /// and not waved off.
  bool get isRemaining =>
      prescribed != null && !hasPassed && ranMeters == 0 && !isSkipped;
}

/// The week measured against its own plan, day by day — what was done, what
/// went, what was never asked for, and what is still ahead.
///
/// **Richer than `weekStanding` on purpose, and it had to be.** That one answers
/// "am I behind?" with two totals and a count, which is exactly right for a tile
/// on Home and useless to anything that has to *rewrite* the week: it cannot
/// name the Tuesday that went, and it cannot see a run on a day the plan left
/// empty at all. Those two are the whole of what an adaptation needs to know,
/// so this derives them rather than inventing a second, disagreeing tally —
/// every outcome here comes back through [outcomeOn], the one place that decides
/// what became of a day.
class WeekAsRun {
  const WeekAsRun({required this.days});

  /// Monday to Sunday, always seven, in order. Days the plan asked nothing of
  /// are present and empty here — unlike [weekOutcomes], because a blank day
  /// is somewhere a session can be *put*, and a refit has to be able to see it.
  final List<DayAsRun> days;

  Iterable<DayAsRun> get done => days.where((d) => d.isDone);
  Iterable<DayAsRun> get missed => days.where((d) => d.isMissed);
  Iterable<DayAsRun> get skipped => days.where((d) => d.isSkipped);
  Iterable<DayAsRun> get unplanned => days.where((d) => d.isUnplanned);
  Iterable<DayAsRun> get remaining => days.where((d) => d.isRemaining);

  /// The weekdays a run happened on, prescribed or not.
  ///
  /// A day that has been run is **settled**: nothing may be scheduled onto it
  /// and nothing may be taken off it. This is the set both the validator rule
  /// and the deterministic refit are written against.
  Set<int> get settledWeekdays => <int>{
    for (final d in days)
      if (d.ranMeters > 0) d.weekday,
  };

  /// Every metre run inside the week, prescribed or not.
  double get ranMeters => days.fold<double>(0, (sum, d) => sum + d.ranMeters);

  /// The metres run on days the plan asked nothing of.
  ///
  /// Kept apart from [ranMeters] because it is the part of the week no
  /// prescription accounts for. The long-run share rule in `plan_validator.dart`
  /// adds it back before dividing, or a runner's extra Wednesday gets reported
  /// as a lopsided week.
  double get unplannedMeters =>
      unplanned.fold<double>(0, (sum, d) => sum + d.ranMeters);

  /// What the plan still has ahead of it, in prescribed metres.
  double get remainingMeters =>
      remaining.fold<double>(0, (sum, d) => sum + d.prescribed!.distanceMeters);

  /// Whether the week has departed from its plan at all.
  ///
  /// The gate on the deterministic refit. With nothing missed, nothing waved
  /// off and nothing run off-plan there is no situation to fit around, and
  /// offering a rearranged week anyway would be answering a question nobody
  /// asked — which is the "reshuffles the week generically" complaint arriving
  /// by a different door.
  bool get hasDiverged =>
      missed.isNotEmpty || skipped.isNotEmpty || unplanned.isNotEmpty;

  /// Whether anything has happened in the week yet.
  ///
  /// What decides whether this is worth sending to the model: a week nothing
  /// has happened in yet says nothing a revision could use, and paying to tell
  /// it so is how a prompt fills up with noise.
  bool get hasHistory => done.isNotEmpty || hasDiverged;
}

/// The week as it actually went, day by day — the tally an adaptation is fitted
/// around.
///
/// [statusFor] and [since] mean exactly what they mean to [missedSessions], and
/// [since] is the caller's to decide for the same reason: a plan cannot be
/// behind on days that predate it, and only the caller knows which those are.
/// See `home_shell.dart`, which passes today for a plan still in its first week
/// because nothing stored can date it more precisely.
WeekAsRun weekAsRun({
  required TrainingWeek week,
  required DateTime weekStart,
  required DateTime now,
  required List<RunSummary> runs,
  SessionStatus Function(int weekday)? statusFor,
  DateTime? since,
}) {
  final days = <DayAsRun>[];
  for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++) {
    final date = addDays(weekStart, weekday - 1);
    final prescribed = week.runOn(weekday);

    var ran = 0.0;
    for (final run in runs) {
      if (daysBetweenDates(run.startedAt, date) == 0) {
        ran += run.distanceMeters;
      }
    }

    days.add(
      DayAsRun(
        weekday: weekday,
        date: date,
        // Negative days are days already gone; zero is today, which has not.
        hasPassed: daysBetweenDates(now, date) < 0,
        ranMeters: ran,
        prescribed: prescribed,
        outcome: prescribed == null
            ? null
            : outcomeOn(
                date: date,
                now: now,
                runs: runs,
                status: statusFor?.call(weekday) ?? SessionStatus.planned,
                since: since,
              ),
      ),
    );
  }
  return WeekAsRun(days: days);
}

/// A prescribed day that came and went with no run against it.
class MissedSession {
  const MissedSession({required this.date, required this.session});

  final DateTime date;
  final PlannedSession session;

  /// The sessions the block actually hangs on. Missing an easy run is a Tuesday
  /// that got away; missing the long run is a week that did not happen.
  bool get isKey => session.kind.isHard || session.kind == SessionKind.long;
}

/// The prescribed days of [week] that have passed with no run.
List<MissedSession> missedSessions({
  required TrainingWeek week,
  required DateTime weekStart,
  required DateTime now,
  required List<RunSummary> runs,
  SessionStatus Function(int weekday)? statusFor,
  DateTime? since,
}) {
  final missed = <MissedSession>[];
  for (final session in week.runs) {
    final date = addDays(weekStart, session.weekday - 1);
    final outcome = outcomeOn(
      date: date,
      now: now,
      runs: runs,
      status: statusFor?.call(session.weekday) ?? SessionStatus.planned,
      since: since,
    );
    if (outcome == DayOutcome.missed) {
      missed.add(MissedSession(date: date, session: session));
    }
  }
  return missed;
}

/// What Home should say about missed days, and the two sentences its answers
/// hand to the coach. Null when there is nothing worth raising.
class MissedPrompt {
  const MissedPrompt({
    required this.missed,
    required this.headline,
    required this.logOpener,
    required this.adjustOpener,
  });

  final List<MissedSession> missed;

  /// One line naming what went, e.g. "You missed Tuesday's 8 km long run."
  final String headline;

  /// What "I ran it" says to the coach on the runner's behalf.
  final String logOpener;

  /// What "Adjust" says.
  final String adjustOpener;
}

/// Whether a miss is worth raising, and what to say about it.
///
/// **Graduated on purpose.** Reacting equally to everything is what turns a
/// coach into a nag, so one easy run that got away is carried in the brief and
/// nothing else — the coach can mention it if it becomes a pattern. A key
/// session, or two misses in a week, is a week worth rebalancing (ADR-0017).
///
/// Both answers are sentences rather than actions, because the runner may have
/// done something the app cannot see and the coach's first question is always
/// whether they actually missed it.
MissedPrompt? missedPromptFor({
  required TrainingWeek week,
  required DateTime weekStart,
  required DateTime now,
  required List<RunSummary> runs,
  UnitSystem unit = UnitSystem.metric,
  SessionStatus Function(int weekday)? statusFor,
  DateTime? since,
}) {
  final missed = missedSessions(
    week: week,
    weekStart: weekStart,
    now: now,
    runs: runs,
    statusFor: statusFor,
    since: since,
  );
  if (missed.isEmpty) return null;

  // One easy run is not an incident. It reaches the coach through the brief,
  // which is where a pattern would show up.
  if (missed.length == 1 && !missed.first.isKey) return null;

  final latest = missed.last;
  // The long name: these are sentences, and "You missed Sun's long run" reads
  // as an abbreviation of nothing. The ribbon is where the short form belongs.
  final day = weekdayLongName(latest.session.weekday);
  // Through the prescribed formatter rather than a zero-decimal conversion.
  // The two agree on almost everything, and disagreeing at all is the problem
  // this is: a session under half a unit long reads as "0 km" one way and
  // "1 km" the other, and the sentence goes out to the coach with the number in
  // it. One function decides what a prescription reads like.
  final what =
      '${formatPrescribed(latest.session.distanceMeters, unit)} '
      '${kindLabel(latest.session.kind).toLowerCase()}';

  if (missed.length == 1) {
    return MissedPrompt(
      missed: missed,
      headline: "You missed $day's $what.",
      logOpener:
          "I did run $day's $what — it just wasn't tracked. Can you log it?",
      adjustOpener:
          "I missed $day's $what. Can you rebalance what's left of this week?",
    );
  }

  final days = missed.map((m) => weekdayLongName(m.session.weekday)).join(', ');
  return MissedPrompt(
    missed: missed,
    headline: '${missed.length} sessions missed this week — $days.',
    logOpener:
        "I did run some of what I missed this week ($days) — they just weren't "
        'tracked. Can you log them?',
    adjustOpener:
        'I have missed $days this week. Can you rebalance what is left?',
  );
}
