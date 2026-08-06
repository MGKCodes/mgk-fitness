import '../../../core/units/pace.dart';
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

/// What to call a session: the runner's own name for it where they gave one,
/// and the training kind otherwise.
String sessionLabel(PlannedSession session) =>
    session.label ?? kindLabel(session.kind);

String kindLabel(SessionKind kind) => switch (kind) {
  SessionKind.rest => 'Rest',
  SessionKind.recovery => 'Recovery',
  SessionKind.easy => 'Easy',
  SessionKind.long => 'Long run',
  SessionKind.marathonPace => 'Marathon pace',
  SessionKind.threshold => 'Threshold',
  SessionKind.interval => 'Intervals',
  SessionKind.timeTrial => 'Time trial',
  SessionKind.strength => 'Strength',
};

/// What to call [session] on screen: **the runner's own word where they gave
/// one**, and the kind otherwise.
///
/// A parkrun runner's Saturday is a `SessionKind.timeTrial`, and calling it
/// "Time trial 5.0 km" on their own week renames the thing they already do —
/// which [PlannedSession.label] exists to prevent. Home was doing exactly that
/// in three places while the week list got it right.
String sessionName(PlannedSession session) =>
    session.label ?? kindLabel(session.kind);

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
