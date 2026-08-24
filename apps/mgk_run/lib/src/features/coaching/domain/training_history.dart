import '../../recording/domain/run_summary.dart';
import 'stored_plan.dart';
import 'training_plan.dart';
import 'week_progress.dart';

/// One week of the log, for the volume chart.
class WeekVolume {
  const WeekVolume({
    required this.weekStart,
    required this.meters,
    required this.isCurrent,
  });

  /// The Monday the week began.
  final DateTime weekStart;

  /// Everything run in it. Zero is a real answer and is drawn as a real zero —
  /// a week off is part of the shape, not a gap to be smoothed over.
  final double meters;

  /// The week in progress. Its bar is still filling, which is why it is the one
  /// the chart emphasises rather than the tallest.
  final bool isCurrent;
}

/// Weekly totals for the last [weeks] weeks, oldest first, including the week
/// in progress.
///
/// Weeks with nothing in them are present with zero rather than absent: the
/// x-axis is calendar time, so dropping an empty week would slide every bar
/// after it and quietly redraw the runner's history.
List<WeekVolume> weeklyVolumes({
  required List<RunSummary> runs,
  required DateTime now,
  int weeks = 8,
}) {
  final thisMonday = mondayOf(now);
  final first = addDays(thisMonday, -(weeks - 1) * 7);

  final totals = <int, double>{};
  for (final run in runs) {
    final days = daysBetweenDates(first, run.startedAt);
    if (days < 0) continue;
    final index = days ~/ 7;
    if (index >= weeks) continue;
    totals[index] = (totals[index] ?? 0) + run.distanceMeters;
  }

  return <WeekVolume>[
    for (var i = 0; i < weeks; i++)
      WeekVolume(
        weekStart: addDays(first, i * 7),
        meters: totals[i] ?? 0,
        isCurrent: i == weeks - 1,
      ),
  ];
}

/// What a single day was, for the consistency grid.
///
/// Deliberately **not** [DayOutcome]. That one answers "did you do what the plan
/// asked", which needs a plan and only makes sense for the week the plan is
/// materialised for. This answers "did you run", which is true of every runner
/// on every shape — including one with no plan at all.
enum RunDay {
  /// A run is on record for that day.
  ran,

  /// No run. Not a judgement: most days of most weeks are this, by design.
  none,

  /// Today, still open.
  today,

  /// Later this week — not yet anything.
  future,
}

/// One day of the year view: the date, and how far was run on it.
///
/// Carries **metres rather than a yes/no**, which is the whole difference
/// between this and [RunDay]. Over eight weeks "did you turn up" is the
/// question; over a year it is not enough, because a year of 5 km Tuesdays and
/// a year of building to a marathon draw an identical grid otherwise, and the
/// second one is a story.
class RunYearDay {
  const RunYearDay({
    required this.date,
    this.meters = 0,
    this.isToday = false,
    this.isFuture = false,
  });

  final DateTime date;

  /// Everything run on this day, summed. Two runs in a day is a real thing —
  /// a double, or a commute either side of a working day — and showing only
  /// the longer of them would quietly under-report the week.
  final double meters;

  final bool isToday;

  /// True only for the tail of the current week. A year view ends on today, so
  /// the last column is usually part-drawn, and those days are not absences.
  final bool isFuture;

  bool get ran => meters > 0;
}

/// The last [weeks] weeks as **columns** of seven days, oldest week first, each
/// column running Monday to Sunday.
///
/// Columns rather than rows, which is the layout GitHub's contribution graph
/// uses and the reason it works at this length: fifty-two rows of seven is a
/// list nobody scrolls, and seven rows of fifty-two is a shape you take in at
/// once. [consistencyGrid] stays row-major because eight rows is a block rather
/// than a list, and the two surfaces want opposite things.
List<List<RunYearDay>> runYear({
  required List<RunSummary> runs,
  required DateTime now,
  int weeks = 53,
}) {
  final first = addDays(mondayOf(now), -(weeks - 1) * 7);

  // Summed into buckets in one pass, for the reason the sibling gives: a runner
  // with years of history would otherwise be walked 371 times over.
  final metres = <int, double>{};
  for (final run in runs) {
    final day = daysBetweenDates(first, run.startedAt);
    if (day >= 0 && day < weeks * 7) {
      metres[day] = (metres[day] ?? 0) + run.distanceMeters;
    }
  }

  final todayIndex = daysBetweenDates(first, now);
  return <List<RunYearDay>>[
    for (var w = 0; w < weeks; w++)
      <RunYearDay>[
        for (var d = 0; d < 7; d++)
          () {
            final index = w * 7 + d;
            return RunYearDay(
              date: addDays(first, index),
              meters: metres[index] ?? 0,
              isToday: index == todayIndex,
              isFuture: index > todayIndex,
            );
          }(),
      ],
  ];
}

/// The last [weeks] weeks as rows of seven days, oldest week first, each row
/// running Monday to Sunday.
///
/// The long view of turning up, and the one measure that reads the same for a
/// marathon block and a parkrun habit — a rhythm's volume is flat by design, so
/// a volume chart says almost nothing about whether it is being kept.
List<List<RunDay>> consistencyGrid({
  required List<RunSummary> runs,
  required DateTime now,
  int weeks = 8,
}) {
  final first = addDays(mondayOf(now), -(weeks - 1) * 7);

  // Bucketed once rather than scanned per day: a runner with years of history
  // would otherwise be walked 56 times over.
  final ran = <int>{};
  for (final run in runs) {
    final day = daysBetweenDates(first, run.startedAt);
    if (day >= 0 && day < weeks * 7) ran.add(day);
  }

  final todayIndex = daysBetweenDates(first, now);
  return <List<RunDay>>[
    for (var w = 0; w < weeks; w++)
      <RunDay>[
        for (var d = 0; d < 7; d++)
          () {
            final index = w * 7 + d;
            if (ran.contains(index)) return RunDay.ran;
            if (index == todayIndex) return RunDay.today;
            return index > todayIndex ? RunDay.future : RunDay.none;
          }(),
      ],
  ];
}

/// The next prescribed run after [weekday] in [week], or null when the rest of
/// the week is rest.
///
/// A rest day's card used to end on "Nothing scheduled. Rest is part of the
/// plan." — true, and a dead end on the screen a runner opens to find out what
/// is happening. Naming the next session turns the day into a position in a
/// week rather than a blank.
PlannedSession? nextRunAfter(TrainingWeek week, int weekday) {
  PlannedSession? best;
  for (final session in week.runs) {
    if (session.weekday <= weekday) continue;
    if (best == null || session.weekday < best.weekday) best = session;
  }
  return best;
}

/// Where this week stands: what has been run against what was asked.
///
/// Both halves are needed and neither substitutes for the other — three of five
/// sessions can be most of the distance or barely any of it, and a runner
/// deciding whether they are behind wants to know which.
class WeekStanding {
  const WeekStanding({
    required this.ranMeters,
    required this.plannedMeters,
    required this.done,
    required this.sessions,
  });

  final double ranMeters;
  final double plannedMeters;
  final int done;
  final int sessions;

  /// True when there is a plan to be measured against. Without one the distance
  /// still means something and the ratio does not.
  bool get hasPlan => sessions > 0;
}

/// This week's distance and sessions, run against prescribed.
WeekStanding weekStanding({
  required TrainingWeek? week,
  required DateTime weekStart,
  required DateTime now,
  required List<RunSummary> runs,
}) {
  var ranMeters = 0.0;
  for (final run in runs) {
    final day = daysBetweenDates(weekStart, run.startedAt);
    if (day >= 0 && day < 7) ranMeters += run.distanceMeters;
  }

  if (week == null) {
    return WeekStanding(
      ranMeters: ranMeters,
      plannedMeters: 0,
      done: 0,
      sessions: 0,
    );
  }

  final outcomes = weekOutcomes(
    week: week,
    weekStart: weekStart,
    now: now,
    runs: runs,
  );
  return WeekStanding(
    ranMeters: ranMeters,
    plannedMeters: week.volumeMeters,
    done: outcomes.values.where((o) => o == DayOutcome.done).length,
    sessions: week.runs.length,
  );
}
