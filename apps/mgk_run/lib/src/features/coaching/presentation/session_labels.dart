import 'package:mgk_units/mgk_units.dart';
import '../domain/pace_model.dart';
import '../domain/training_plan.dart';

/// Display helpers shared by the session surfaces (week detail, today card).

const _weekdayNames = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Short name for a weekday (`DateTime.monday`..`sunday`).
String weekdayName(int weekday) => _weekdayNames[weekday - 1];

const _weekdayLongNames = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// Full name for a weekday. For places with room for the word — a day divider
/// in the transcript, where "Tue" reads as an abbreviation of nothing.
String weekdayLongName(int weekday) => _weekdayLongNames[weekday - 1];

/// Short month name, `1`..`12`.
String monthShortName(int month) => _monthNames[month - 1];

/// What a session kind is called: **the activity, not the physiology.**
///
/// "Threshold", "Easy" and "Recovery" name an intensity. They are the coach's
/// vocabulary, and a runner who reads "Easy" on a Wednesday has been told how
/// hard and never what they are doing. Attaching the zone to the activity —
/// "Easy run" — loses none of the prescription and turns it into a thing a
/// person recognises having done.
///
/// The four that are not runs keep their own nouns. "Rest run" is nonsense,
/// intervals and a time trial are already activities, and strength is a session
/// this app deliberately does not prescribe (ADR-0010).
String kindLabel(SessionKind kind) => switch (kind) {
  SessionKind.rest => 'Rest',
  SessionKind.recovery => 'Recovery run',
  SessionKind.easy => 'Easy run',
  SessionKind.long => 'Long run',
  SessionKind.marathonPace => 'Marathon pace run',
  SessionKind.threshold => 'Threshold run',
  SessionKind.interval => 'Intervals',
  SessionKind.timeTrial => 'Time trial',
  SessionKind.strength => 'Strength',
};

/// The part of the day [at] falls in: "Morning", "Afternoon" or "Evening".
///
/// The same three words and the same two boundaries as Home's greeting, on
/// purpose. Two answers to "what time of day is it" in one app is a bug waiting
/// for six o'clock, and a header reading "Evening" over a card reading
/// "Afternoon easy run" is the version of it a runner would actually see.
String timeOfDayName(DateTime at) {
  if (at.hour < 12) return 'Morning';
  return at.hour < 18 ? 'Afternoon' : 'Evening';
}

/// What to call [session] on screen: **the runner's own word where they gave
/// one**, and the activity otherwise.
///
/// A parkrun runner's Saturday is a `SessionKind.timeTrial`, and calling it
/// "Time trial 5.0 km" on their own week renames the thing they already do —
/// which [PlannedSession.label] exists to prevent. Home was doing exactly that
/// in three places while the week list got it right.
///
/// **No time of day, and that is the point.** A planned Wednesday four days out
/// has no hour attached to it, so "Afternoon easy run" over a session its owner
/// might run at half six in the morning would be the app stating a fact it does
/// not hold — the same refusal that leaves an unbarometered climb blank rather
/// than guessing at it. Where the hour genuinely is known, [sessionNameAt] says
/// so instead.
String sessionName(PlannedSession session) =>
    session.label ?? kindLabel(session.kind);

/// [sessionName], prefixed with the time of day — for the surfaces where the
/// app really does know when the session happens.
///
/// There are exactly two of those: **today**, where [at] comes off the clock,
/// and a **run already recorded**, where it comes off the run's start. Anywhere
/// else — a week list of seven planned days, a calendar, the shape of a block —
/// there is no occasion to name and [sessionName] is the honest answer. Passing
/// `DateTime.now()` for a future day would invent the very thing this pair of
/// functions exists to keep apart.
///
/// Two things are never prefixed. A label is the runner's own word and is
/// reproduced exactly as they wrote it. And rest is not an occasion: there is
/// no such thing as an afternoon rest.
String sessionNameAt(PlannedSession session, DateTime at) {
  final own = session.label;
  if (own != null) return own;
  if (session.kind == SessionKind.rest) return kindLabel(SessionKind.rest);
  return '${timeOfDayName(at)} ${kindLabel(session.kind).toLowerCase()}';
}

/// What to call a recorded run that no plan claims: "Afternoon run".
///
/// A finished run is the one case where the occasion is never in doubt — it has
/// a start time, which is what makes it nameable at all. Kept beside
/// [sessionNameAt] so the log and the plan cannot end up with two vocabularies
/// for the same afternoon.
String runName(DateTime startedAt) => '${timeOfDayName(startedAt)} run';

/// The target pace for a session kind, or null when there is none (rest).
Pace? paceFor(SessionKind kind, TrainingPaces paces) => switch (kind) {
  SessionKind.rest => null,
  SessionKind.recovery => paces.recovery,
  SessionKind.easy => paces.easy,
  SessionKind.long => paces.easy,
  SessionKind.marathonPace => paces.marathon,
  SessionKind.threshold => paces.threshold,
  SessionKind.interval => paces.interval,
  // Race effort over a short fixed distance sits above threshold, near where
  // intervals live — not at an hour's pace.
  SessionKind.timeTrial => paces.interval,
  // Strength has no pace, and inventing one would be the plan pretending to
  // prescribe a session it deliberately leaves to Liftio.
  SessionKind.strength => null,
};

/// A training phase as a word. Shared so the plan arc, today's card and the
/// home page cannot disagree about what to call a week.
String phaseLabel(Phase phase) => switch (phase) {
  Phase.base => 'Base',
  Phase.build => 'Build',
  Phase.peak => 'Peak',
  Phase.taper => 'Taper',
};

const _monthNames = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// The seven days of a week as real dates: `27 Jul – 2 Aug`, or `3 – 9 Aug`
/// when both ends share a month.
///
/// **A week is a set of days, not a code.** "W1" is the plan's internal index
/// leaking onto the screen — it tells a runner nothing they can act on, and
/// nothing they could match against a calendar or a race entry. The ordinal
/// still has a job ("volume peaks in week 12"), but it belongs after the dates
/// rather than instead of them.
String weekRangeLabel(DateTime monday) {
  final sunday = DateTime(monday.year, monday.month, monday.day + 6);
  final from = _monthNames[monday.month - 1];
  final to = _monthNames[sunday.month - 1];
  return monday.month == sunday.month
      ? '${monday.day} – ${sunday.day} $to'
      : '${monday.day} $from – ${sunday.day} $to';
}
