import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/stats/domain/activity_window.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';

/// A finished session of a known length on a known day.
Session lifted(
  DateTime day, {
  Duration length = const Duration(hours: 1),
  String tag = '',
}) => Session(
  id: '${day.toIso8601String()}-${length.inMinutes}-$tag',
  name: 'Session',
  startedAt: day,
  endedAt: day.add(length),
);

/// A Monday, so the fixture and the Monday-anchored window agree about which
/// column a date lands in.
final DateTime monday = DateTime(2026, 8, 24);

String _short(DateTime d) => const <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
][d.month - 1];

void main() {
  group('the window', () {
    test('is 52 Monday-to-Sunday columns ending with this week', () {
      final window = ActivityWindow.from(const <Session>[], now: monday);

      expect(window.weeks, 52);
      expect(window.days.length, 52 * 7);
      expect(window.firstDay.weekday, DateTime.monday);
      expect(window.lastDay.weekday, DateTime.sunday);
      // 52 columns of 7, inclusive of both ends.
      expect(window.lastDay.difference(window.firstDay).inDays, 363);
      // Today is in the final column, which is the whole point of a rolling
      // window rather than a calendar year.
      expect(window.lastDay.isBefore(monday), isFalse);
      expect(window.firstDay.isAfter(monday), isFalse);
    });

    test('rolls with the clock rather than sitting on a year boundary', () {
      final august = ActivityWindow.from(const <Session>[], now: monday);
      final september = ActivityWindow.from(
        const <Session>[],
        now: DateTime(2026, 9, 21),
      );

      expect(september.firstDay.isAfter(august.firstDay), isTrue);
      expect(september.lastDay.isAfter(august.lastDay), isTrue);
    });

    test('every square is a distinct midnight', () {
      // The guard against stepping the year with `Duration(days: 1)`. The day
      // the clocks change is 23 or 25 hours long, so adding fixed durations
      // drifts and can land two squares on the same date. Only fails on a
      // machine in a DST zone, which is where it matters.
      final window = ActivityWindow.from(const <Session>[], now: monday);

      expect(
        window.days.map((ActivityDay d) => d.date).toSet().length,
        window.days.length,
      );
      for (final day in window.days) {
        expect(day.date.hour, 0, reason: '${day.date} is not midnight');
        expect(day.date.minute, 0);
      }
    });
  });

  group('what fills a square', () {
    test('a session lands on the day it started', () {
      final window = ActivityWindow.from(<Session>[
        lifted(DateTime(2026, 8, 19)),
      ], now: monday);

      final trained = window.days.where((ActivityDay d) => d.isTrained);
      expect(trained.length, 1);
      expect(trained.first.date, DateTime(2026, 8, 19));
      expect(window.trainedDays, 1);
    });

    test('two sessions on one day add up', () {
      final window = ActivityWindow.from(<Session>[
        lifted(DateTime(2026, 8, 19), length: const Duration(minutes: 40)),
        lifted(
          DateTime(2026, 8, 19, 18),
          length: const Duration(minutes: 20),
          tag: 'evening',
        ),
      ], now: monday);

      expect(window.trainedDays, 1);
      final day = window.days.firstWhere((ActivityDay d) => d.isTrained);
      expect(day.trained, const Duration(minutes: 60));
    });

    test('a session in progress is not a trained day', () {
      // Consistent with TrainingStats, which folds only finished sessions. A
      // square that appears the moment someone opens the app and disappears if
      // they abandon the session is worse than one that appears when they
      // finish.
      final window = ActivityWindow.from(<Session>[
        Session(
          id: 'live',
          name: 'Session',
          startedAt: DateTime(2026, 8, 24, 9),
        ),
      ], now: monday);

      expect(window.trainedDays, 0);
    });

    test('a session older than the window is dropped', () {
      final window = ActivityWindow.from(<Session>[
        lifted(DateTime(2024, 1, 1)),
      ], now: monday);

      expect(window.trainedDays, 0);
    });

    test('a zero-length session still marks the day', () {
      // Liftio drew this day in the rest-day colour — a logged session
      // rendered as a day off. It takes the lowest tier here instead.
      final window = ActivityWindow.from(<Session>[
        lifted(DateTime(2026, 8, 17), length: const Duration(minutes: 90)),
        lifted(DateTime(2026, 8, 18), length: const Duration(minutes: 30)),
        lifted(DateTime(2026, 8, 19), length: Duration.zero),
      ], now: monday);

      expect(window.trainedDays, 3);
      final blank = window.days.firstWhere(
        (ActivityDay d) => d.date == DateTime(2026, 8, 19),
      );
      expect(blank.isTrained, isTrue);
      expect(blank.tier, 0);
      // And it stays out of the sample, or it would drag the median to 30
      // minutes and lighten every other day in the window.
      expect(window.median, const Duration(minutes: 60));
    });
  });

  group('days that have not happened', () {
    test('the rest of this week is absent, not empty', () {
      // Wednesday. Thursday onward has not arrived, and drawing it as a rest
      // day would report a four-day gap every Wednesday.
      final window = ActivityWindow.from(
        const <Session>[],
        now: DateTime(2026, 8, 26),
      );

      final last = window.weeks - 1;
      expect(window.dayAt(last, 0).isFuture, isFalse); // Monday
      expect(window.dayAt(last, 2).isFuture, isFalse); // Wednesday, today
      expect(window.dayAt(last, 3).isFuture, isTrue); // Thursday
      expect(window.dayAt(last, 6).isFuture, isTrue); // Sunday
    });

    test('a Sunday leaves nothing absent', () {
      final window = ActivityWindow.from(
        const <Session>[],
        now: DateTime(2026, 8, 30),
      );

      expect(window.days.every((ActivityDay d) => !d.isFuture), isTrue);
    });
  });

  group('the thresholds', () {
    test('are the window\'s own median and 95th percentile', () {
      // Twenty days at 1 to 20 minutes. Median of an even sample is the mean
      // of the middle pair; the 95th is nearest-rank, ceil(20 × 0.95) - 1 = 18.
      final window = ActivityWindow.from(<Session>[
        for (var i = 1; i <= 20; i++)
          lifted(
            DateTime(2026, 8, 24 - i),
            length: Duration(minutes: i),
            tag: '$i',
          ),
      ], now: monday);

      expect(window.median, const Duration(seconds: 630)); // 10.5 minutes
      expect(window.ninetyFifth, const Duration(minutes: 19));
    });

    test('the 95th ignores a single outlier rather than scaling to it', () {
      // The reason it is not the maximum. Nineteen ordinary days of 40 to 58
      // minutes and one six-hour marathon: scaled to the max, the top of the
      // ramp is out of reach and every ordinary day collapses into the bottom
      // tier.
      final window = ActivityWindow.from(<Session>[
        for (var i = 1; i <= 19; i++)
          lifted(
            DateTime(2026, 8, 24 - i),
            length: Duration(minutes: 39 + i),
            tag: '$i',
          ),
        lifted(
          DateTime(2026, 8, 1),
          length: const Duration(hours: 6),
          tag: 'marathon',
        ),
      ], now: monday);

      expect(window.median, const Duration(seconds: 2970)); // 49.5 minutes
      expect(window.ninetyFifth, const Duration(minutes: 58));

      final tiers = window.days
          .where((ActivityDay d) => d.isTrained)
          .map((ActivityDay d) => d.tier)
          .toSet();
      expect(tiers, <int>{1, 2, 3, 4});
    });

    test('an empty window has no thresholds', () {
      final window = ActivityWindow.from(const <Session>[], now: monday);

      expect(window.isEmpty, isTrue);
      expect(window.median, Duration.zero);
      expect(window.ninetyFifth, Duration.zero);
    });
  });

  group('tierFor', () {
    // Liftio's getTierOpacity, step for step: half the median, the median,
    // halfway to the 95th, and the 95th.
    const median = Duration(minutes: 60);
    const ninetyFifth = Duration(minutes: 120);

    int tier(Duration d) =>
        ActivityWindow.tierFor(d, median: median, ninetyFifth: ninetyFifth);

    test('at or above the 95th is the top tier', () {
      expect(tier(const Duration(minutes: 120)), 4);
      expect(tier(const Duration(hours: 5)), 4);
    });

    test('halfway between median and the 95th is the fourth', () {
      expect(tier(const Duration(minutes: 90)), 3);
      expect(tier(const Duration(minutes: 119)), 3);
    });

    test('at the median is the middle tier', () {
      expect(tier(const Duration(minutes: 60)), 2);
      expect(tier(const Duration(minutes: 89)), 2);
    });

    test('at half the median is the second', () {
      expect(tier(const Duration(minutes: 30)), 1);
      expect(tier(const Duration(minutes: 59)), 1);
    });

    test('below half the median is the lightest', () {
      expect(tier(const Duration(minutes: 29)), 0);
      expect(tier(Duration.zero), 0);
    });

    test('everything is solid when there is nothing to compare', () {
      // One trained day, or every day the same length: the two thresholds sit
      // on top of each other and a ramp between them would be meaningless.
      expect(
        ActivityWindow.tierFor(
          const Duration(minutes: 10),
          median: const Duration(minutes: 60),
          ninetyFifth: const Duration(minutes: 60),
        ),
        4,
      );
      expect(
        ActivityWindow.tierFor(
          const Duration(minutes: 10),
          median: Duration.zero,
          ninetyFifth: Duration.zero,
        ),
        4,
      );
    });

    test('the ramp survives a light trainer and a heavy one alike', () {
      // The reason the thresholds are relative. Two lifters, one training 30
      // to 50 minutes and one training two to four hours, both get the full
      // range of shades rather than a uniformly pale or uniformly solid year.
      List<int> tiersFor(List<int> minutes) {
        final window = ActivityWindow.from(<Session>[
          for (var i = 0; i < minutes.length; i++)
            lifted(
              DateTime(2026, 8, 23 - i),
              length: Duration(minutes: minutes[i]),
              tag: '$i',
            ),
        ], now: monday);
        return window.days
            .where((ActivityDay d) => d.isTrained)
            .map((ActivityDay d) => d.tier!)
            .toList();
      }

      final light = tiersFor(<int>[30, 33, 36, 40, 44, 48, 50]);
      final heavy = tiersFor(<int>[120, 132, 144, 160, 176, 192, 200]);

      expect(light.toSet().length, greaterThan(1));
      expect(heavy.toSet().length, greaterThan(1));
      // Same shape of week, same shape of shading — which is what a fixed
      // scale in minutes could not do.
      expect(light.toSet(), heavy.toSet());
    });
  });

  group('month labels', () {
    test('there are twelve, one per month the window touches', () {
      // 364 days spans twelve or thirteen months. Thirteen means the first and
      // last read the same name, and the stub at the left goes.
      for (final now in <DateTime>[
        DateTime(2026, 8, 24),
        DateTime(2026, 1, 2),
        DateTime(2026, 3, 15),
        DateTime(2027, 11, 30),
      ]) {
        final window = ActivityWindow.from(const <Session>[], now: now);
        expect(window.monthLabels.length, 12, reason: 'window ending $now');
        expect(
          window.monthLabels.map((MonthLabel l) => l.label).toSet().length,
          12,
          reason: 'duplicate month name in the window ending $now',
        );
      }
    });

    test('a label sits over the column its month starts in', () {
      // Not a regular pitch of one label every four or five columns: the label
      // lands where the month actually begins, so it lines up with the squares
      // underneath it.
      final window = ActivityWindow.from(const <Session>[], now: monday);

      for (final label in window.monthLabels) {
        final column = <DateTime>[
          for (var d = 0; d < ActivityWindow.daysPerWeek; d++)
            window.dayAt(label.week, d).date,
        ];
        expect(
          column.any((DateTime d) => _short(d) == label.label),
          isTrue,
          reason:
              '${label.label} is labelled at a column it does not appear in',
        );
        if (label.week == 0) continue;
        final before = <DateTime>[
          for (var d = 0; d < ActivityWindow.daysPerWeek; d++)
            window.dayAt(label.week - 1, d).date,
        ];
        expect(
          before.any((DateTime d) => _short(d) == label.label),
          isFalse,
          reason: '${label.label} had already started a column earlier',
        );
      }
    });

    test('labels run left to right', () {
      final window = ActivityWindow.from(const <Session>[], now: monday);
      final weeks = window.monthLabels.map((MonthLabel l) => l.week).toList();

      expect(weeks, orderedEquals(<int>[...weeks]..sort()));
    });
  });
}
