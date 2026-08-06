import '../../../core/units/distance.dart';
import '../../../core/units/unit_system.dart';
import '../../recording/domain/run_summary.dart';
import '../presentation/session_labels.dart';
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
  final what =
      '${Distance.meters(latest.session.distanceMeters).format(unit, fractionDigits: 0)} '
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
