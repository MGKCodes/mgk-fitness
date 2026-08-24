import 'package:meta/meta.dart';

import '../../tracking/domain/session.dart';
import 'training_stats.dart';

/// The last 52 weeks of training, bucketed by day and shaded by how hard each
/// day was — the data behind the activity grid.
///
/// Ported from Liftio's `components/shared/YearActivityGrid.tsx`, with the
/// arithmetic pulled out of the component. In Liftio the window building, the
/// percentile maths and the rendering were one 400-line file, so the part worth
/// getting right — the shading — could only be checked by looking at it.
///
/// ## A rolling window, not a calendar year
///
/// The window ends on the Sunday of the current week and runs back 52 columns
/// from there, so today is always in the last column. A calendar year would put
/// today halfway along in July and leave five months of empty squares on the
/// right, which reads as five months of not training.
///
/// Liftio had both: the rolling window as the default and stacked calendar
/// years behind a "VIEW ALL YEARS" toggle. Only the rolling one is ported. The
/// yearly view answers "what did 2024 look like", which needs years of history
/// to be worth a control, and this app's log starts empty.
///
/// ## Why the tiers are relative
///
/// Five shades, thresholded against the **window's own** median and 95th
/// percentile session length rather than a fixed scale in minutes. A fixed
/// scale makes someone who trains for 40 minutes uniformly pale and someone who
/// trains for two hours uniformly solid, and in both cases the grid stops
/// carrying information — every square looks the same, so the shading says
/// nothing the presence of a square did not already say.
///
/// The 95th percentile rather than the maximum, because one three-hour session
/// pushes the top of a max-scaled ramp out of reach and flattens everything
/// else into the bottom two tiers.
@immutable
class ActivityWindow {
  const ActivityWindow._({
    required this.firstDay,
    required this.lastDay,
    required this.weeks,
    required this.days,
    required this.monthLabels,
    required this.trainedDays,
    required this.median,
    required this.ninetyFifth,
  });

  /// Folds a log into the window ending on the week containing [now].
  ///
  /// [now] is injected for the same reason [TrainingStats.from] injects it: a
  /// window that reads the wall clock cannot be tested, and this one has a
  /// today-shaped edge in it.
  factory ActivityWindow.from(
    List<Session> log, {
    required DateTime now,
    int weeks = defaultWeeks,
  }) {
    assert(weeks > 0, 'a window of no weeks has nothing to draw');

    final today = _startOfDay(now);
    // Monday-anchored, borrowed from [TrainingStats.startOfWeek] rather than
    // re-derived — the streak and the grid disagreeing about where a week
    // starts would put a session in a different column than the one that
    // extended the streak.
    final lastDay = _addDays(TrainingStats.startOfWeek(today), 6);
    final firstDay = _addDays(lastDay, -(weeks * daysPerWeek - 1));

    // A day can hold more than one session. Their lengths add up: two hours in
    // the gym is two hours in the gym whether it was logged once or twice.
    final byDay = <DateTime, Duration>{};
    for (final session in log) {
      if (session.isInProgress) continue;
      final day = _startOfDay(session.startedAt);
      if (day.isBefore(firstDay) || day.isAfter(today)) continue;
      byDay[day] = (byDay[day] ?? Duration.zero) + session.elapsedAt(now);
    }

    // Zero-length days are excluded from the sample but not from the grid — see
    // [ActivityDay.tier]. A session with no measurable length would otherwise
    // drag the median toward zero and lighten every other day in the window.
    final sample = byDay.values.where((d) => d > Duration.zero).toList()
      ..sort();
    final median = _median(sample);
    final ninetyFifth = _percentile(sample, 0.95);

    final days = <ActivityDay>[];
    var trained = 0;
    for (var i = 0; i < weeks * daysPerWeek; i++) {
      final date = _addDays(firstDay, i);
      // Strictly after today, so today itself is a live square rather than an
      // absent one. The rest of this week has not happened yet, and drawing it
      // as a rest day would report a Thursday-to-Sunday gap every Wednesday.
      final isFuture = date.isAfter(today);
      final duration = isFuture ? null : byDay[date];
      if (duration != null) trained++;
      days.add(
        ActivityDay(
          date: date,
          isFuture: isFuture,
          trained: duration,
          tier: duration == null
              ? null
              : tierFor(duration, median: median, ninetyFifth: ninetyFifth),
        ),
      );
    }

    return ActivityWindow._(
      firstDay: firstDay,
      lastDay: lastDay,
      weeks: weeks,
      days: List<ActivityDay>.unmodifiable(days),
      monthLabels: List<MonthLabel>.unmodifiable(_monthLabels(days, weeks)),
      trainedDays: trained,
      median: median,
      ninetyFifth: ninetyFifth,
    );
  }

  /// One year of columns. Liftio's number, and the reason the grid is as wide
  /// as a phone: 52 columns at a readable square size is about a screen.
  static const int defaultWeeks = 52;

  static const int daysPerWeek = 7;

  /// How many shades a trained day can take. Liftio's five, evenly spread.
  static const int tiers = 5;

  /// The Monday of the leftmost column.
  final DateTime firstDay;

  /// The Sunday of the rightmost column, which is on or after today.
  final DateTime lastDay;

  final int weeks;

  /// Every day in the window, chronological — `weeks * 7` of them. Column-major
  /// when read seven at a time, which is how [dayAt] reads it.
  final List<ActivityDay> days;

  final List<MonthLabel> monthLabels;

  /// Days with a finished session on them, within the window.
  final int trainedDays;

  /// The middle session length in the window, and the length only one day in
  /// twenty beats. The two thresholds the shading is built from; exposed so a
  /// caller can say what the ramp means rather than only drawing it.
  final Duration median;
  final Duration ninetyFifth;

  bool get isEmpty => trainedDays == 0;

  /// The day at column [week], row [weekday] — row 0 is Monday.
  ActivityDay dayAt(int week, int weekday) =>
      days[week * daysPerWeek + weekday];

  /// Which of the five shades a day of this length earns, 0 (lightest) to 4.
  ///
  /// Liftio's `getTierOpacity`, kept step for step so a ported year looks like
  /// the year it looked like:
  ///
  /// - at or above the 95th percentile → 4
  /// - halfway between median and the 95th → 3
  /// - at or above the median → 2
  /// - at or above half the median → 1
  /// - below that → 0
  ///
  /// **Everything is the top tier when there is nothing to compare.** With one
  /// trained day, or with every day the same length, the median and the 95th
  /// percentile collapse onto each other and a ramp between them would be
  /// meaningless. A uniformly solid grid is the honest answer there: the days
  /// really were all the same.
  static int tierFor(
    Duration duration, {
    required Duration median,
    required Duration ninetyFifth,
  }) {
    final mid = median.inMicroseconds;
    final top = ninetyFifth.inMicroseconds;
    if (mid <= 0 || top <= 0 || top <= mid) return tiers - 1;

    final value = duration.inMicroseconds;
    if (value >= top) return 4;
    if (value >= mid + (top - mid) ~/ 2) return 3;
    if (value >= mid) return 2;
    if (value >= mid ~/ 2) return 1;
    return 0;
  }

  /// A label per column where a month first appears.
  ///
  /// Liftio's rule, which is subtler than "label every 4th column": a column is
  /// labelled when any of its seven days opens a month not yet seen, and the
  /// label sits at that column. Months land where they actually start rather
  /// than on a regular pitch, so a label lines up with the squares under it.
  static List<MonthLabel> _monthLabels(List<ActivityDay> days, int weeks) {
    final labels = <MonthLabel>[];
    final seen = <int>{};
    for (var w = 0; w < weeks; w++) {
      for (var d = 0; d < daysPerWeek; d++) {
        final date = days[w * daysPerWeek + d].date;
        if (seen.add(date.year * 12 + date.month)) {
          labels.add(MonthLabel(label: _months[date.month - 1], week: w));
          break;
        }
      }
    }
    // 52 weeks is 364 days, so the window opens partway through a month and
    // closes partway through the same month a year later — thirteen labels,
    // the first and last reading the same. The first one goes: it is the one
    // sitting over a stub of a column rather than over a whole month.
    if (labels.length > 12 && labels.first.label == labels.last.label) {
      labels.removeAt(0);
    }
    return labels;
  }

  static Duration _median(List<Duration> sorted) {
    if (sorted.isEmpty) return Duration.zero;
    final n = sorted.length;
    if (n.isOdd) return sorted[n ~/ 2];
    return Duration(
      microseconds:
          (sorted[n ~/ 2 - 1].inMicroseconds + sorted[n ~/ 2].inMicroseconds) ~/
          2,
    );
  }

  /// The nearest-rank percentile, which is Liftio's `ceil(n × p) - 1` index.
  ///
  /// Nearest-rank rather than interpolated because the answer has to be a
  /// session that actually happened — a threshold halfway between two real
  /// sessions is a length nobody trained for.
  static Duration _percentile(List<Duration> sorted, double p) {
    if (sorted.isEmpty) return Duration.zero;
    final n = sorted.length;
    final index = ((n * p).ceil() - 1).clamp(0, n - 1);
    return sorted[index];
  }

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Calendar arithmetic, not `Duration` arithmetic.
  ///
  /// `d.add(Duration(days: 1))` adds 24 hours, and the day the clocks change is
  /// 23 or 25. Stepping a year of squares that way drifts an hour twice and can
  /// land two squares on the same date. Rebuilding through the constructor lets
  /// Dart normalise the overflow and keeps every square on midnight local.
  static DateTime _addDays(DateTime d, int days) =>
      DateTime(d.year, d.month, d.day + days);

  static const List<String> _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
}

/// One square.
@immutable
class ActivityDay {
  const ActivityDay({
    required this.date,
    required this.isFuture,
    this.trained,
    this.tier,
  });

  /// Midnight local on the day this square stands for.
  final DateTime date;

  /// A day later this week that has not arrived.
  ///
  /// **Absent, not empty.** A future square drawn as a rest day tells a lifter
  /// they missed days they have not reached yet, which on a Monday is the whole
  /// week.
  final bool isFuture;

  /// Total finished session time on this day, or null for a rest day.
  final Duration? trained;

  /// The shade, 0 to 4, or null for a rest day.
  ///
  /// A trained day always has one, including a day whose sessions sum to no
  /// measurable time. Liftio drew that day in the rest-day colour — a logged
  /// session rendered as a day off — and it is drawn here at the lowest tier
  /// instead: the session happened, and the grid is a record of what happened.
  final int? tier;

  bool get isTrained => trained != null;
}

/// A month name and the column it starts in.
@immutable
class MonthLabel {
  const MonthLabel({required this.label, required this.week});

  final String label;
  final int week;
}
