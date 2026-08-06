import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_shape.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';

/// The calendar arithmetic that turns a stored week index into real dates. Once
/// a plan outlives the session that made it, this is what keeps "today's
/// session" pointing at today.
void main() {
  RunnerProfile aProfile() => RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: DateTime(2026, 11, 15),
    currentWeeklyMeters: 40000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 4, 6, 7},
  );

  StoredPlan planFrom(DateTime monday, {int weeks = 12}) {
    final profile = aProfile();
    return StoredPlan(
      id: 'plan-1',
      profile: profile,
      skeleton: buildSkeleton(profile, now: monday, weeks: weeks),
      startDate: monday,
    );
  }

  group('mondayOf', () {
    test('is the Monday of the same week, whatever day it is', () {
      // 2026-07-20 is a Monday.
      for (var offset = 0; offset < 7; offset++) {
        final day = DateTime(2026, 7, 20 + offset);
        expect(mondayOf(day), DateTime(2026, 7, 20), reason: 'offset $offset');
      }
    });

    test('a Sunday belongs to the week that began the Monday before', () {
      expect(mondayOf(DateTime(2026, 7, 26, 23, 59)), DateTime(2026, 7, 20));
    });

    test('drops the time of day', () {
      expect(
        mondayOf(DateTime(2026, 7, 22, 14, 37, 12)),
        DateTime(2026, 7, 20),
      );
    });
  });

  group('week index', () {
    final plan = planFrom(DateTime(2026, 7, 20));

    test('the start Monday is week 1, and so is the Sunday after it', () {
      expect(plan.weekIndexOn(DateTime(2026, 7, 20)), 1);
      expect(plan.weekIndexOn(DateTime(2026, 7, 26, 22)), 1);
    });

    test('the next Monday rolls over to week 2', () {
      expect(plan.weekIndexOn(DateTime(2026, 7, 27)), 2);
    });

    test('clamps before the start and after the end', () {
      // A date before the plan began still resolves to its first week.
      expect(plan.weekIndexOn(DateTime(2026, 7, 1)), 1);
      expect(
        plan.weekIndexOn(DateTime(2030, 1, 1)),
        plan.skeleton.weeks.length,
      );
    });

    test('hasEndedBy is false inside the block and true past it', () {
      final weeks = plan.skeleton.weeks.length;
      expect(plan.hasEndedBy(DateTime(2026, 7, 20)), isFalse);
      expect(
        plan.hasEndedBy(addDays(DateTime(2026, 7, 20), weeks * 7 - 1)),
        isFalse,
      );
      expect(
        plan.hasEndedBy(addDays(DateTime(2026, 7, 20), weeks * 7)),
        isTrue,
      );
    });
  });

  group('dateFor', () {
    final plan = planFrom(DateTime(2026, 7, 20));

    test('week 1 maps weekdays 1-7 onto that calendar week', () {
      for (var weekday = 1; weekday <= 7; weekday++) {
        final date = plan.dateFor(weekIndex: 1, weekday: weekday);
        expect(date, DateTime(2026, 7, 19 + weekday));
        expect(date.weekday, weekday, reason: 'weekday $weekday');
      }
    });

    test('later weeks keep the weekday they claim', () {
      for (var week = 1; week <= 12; week++) {
        for (var weekday = 1; weekday <= 7; weekday++) {
          final date = plan.dateFor(weekIndex: week, weekday: weekday);
          expect(
            date.weekday,
            weekday,
            reason: 'week $week weekday $weekday gave $date',
          );
          expect(plan.weekIndexOn(date), week, reason: 'round trip week $week');
        }
      }
    });

    test('every date is a local midnight, so it matches a stored date', () {
      // Session lookup compares against a date-only column. A duration-based
      // shift would land on 23:00 or 01:00 across a daylight-saving boundary and
      // silently stop matching.
      for (var week = 1; week <= 12; week++) {
        for (var weekday = 1; weekday <= 7; weekday++) {
          final d = plan.dateFor(weekIndex: week, weekday: weekday);
          expect(<int>[d.hour, d.minute, d.second], <int>[0, 0, 0]);
        }
      }
    });

    test('a plan spanning a daylight-saving change keeps its weekdays', () {
      // The UK moves the clocks on the last Sunday of October (2026-10-25).
      final autumn = planFrom(DateTime(2026, 10, 5), weeks: 8);
      for (var week = 1; week <= 8; week++) {
        for (var weekday = 1; weekday <= 7; weekday++) {
          final d = autumn.dateFor(weekIndex: week, weekday: weekday);
          expect(
            d.weekday,
            weekday,
            reason: 'week $week weekday $weekday → $d',
          );
          expect(d.hour, 0, reason: 'week $week weekday $weekday → $d');
          expect(autumn.weekIndexOn(d), week);
        }
      }
    });

    test('and one spanning the spring change too', () {
      // Clocks go forward on 2027-03-28.
      final spring = planFrom(DateTime(2027, 3, 1), weeks: 8);
      for (var week = 1; week <= 8; week++) {
        for (var weekday = 1; weekday <= 7; weekday++) {
          final d = spring.dateFor(weekIndex: week, weekday: weekday);
          expect(
            d.weekday,
            weekday,
            reason: 'week $week weekday $weekday → $d',
          );
          expect(spring.weekIndexOn(d), week);
        }
      }
    });
  });

  /// A rhythm's weeks repeat instead of running out (ADR-0011), so one skeleton
  /// index names many calendar weeks. [StoredPlan.dateFor] needs to be told
  /// which one is meant — without that it answered from the first cycle
  /// forever, and a parkrun habit recorded in May was still headed
  /// "4 – 10 May" at the end of July.
  group('dateFor on a plan whose weeks cycle', () {
    // No goal distance and no event date, so this profile is a rhythm.
    final profile = const RunnerProfile(
      currentWeeklyMeters: 5000,
      longestRecentMeters: 5000,
      daysPerWeek: 1,
      availableWeekdays: <int>{DateTime.saturday},
      commitments: <PlanCommitment>[
        PlanCommitment(
          weekday: DateTime.saturday,
          distanceMeters: 5000,
          label: 'parkrun',
        ),
      ],
    );

    // 2026-05-04 is a Monday.
    final started = DateTime(2026, 5, 4);
    final plan = StoredPlan(
      id: 'rhythm-1',
      profile: profile,
      skeleton: buildSkeleton(profile, now: started),
      startDate: started,
    );

    test('the fixture really is a rhythm', () {
      expect(shapeOf(profile), PlanShape.rhythm);
    });

    test('with no reference it still answers from the first cycle', () {
      // Unchanged for callers with no clock to offer — the store writes a
      // session's `scheduled_date` this way.
      expect(plan.dateFor(weekIndex: 1, weekday: 1), started);
    });

    test('with a reference it answers in the week being lived in', () {
      // 2026-07-29 is the Wednesday of the week beginning Monday 27 July.
      final july = DateTime(2026, 7, 29);
      final current = plan.weekIndexOn(july);

      expect(
        plan.dateFor(weekIndex: current, weekday: 1, on: july),
        DateTime(2026, 7, 27),
        reason: 'the current week starts on the Monday of the current week',
      );
    });

    test('the current week contains the day asked about, every week', () {
      // Walk a year of Wednesdays. Whatever the cycle length, the week the
      // runner is in must start on that week's Monday.
      for (var offset = 0; offset < 60; offset++) {
        final day = addDays(started, offset * 7 + 2);
        final current = plan.weekIndexOn(day);
        expect(
          plan.dateFor(weekIndex: current, weekday: 1, on: day),
          mondayOf(day),
          reason: 'week $offset after the start ($day)',
        );
      }
    });

    test('weekIndexOn stays the inverse of dateFor', () {
      final total = plan.skeleton.weeks.length;
      for (var offset = 0; offset < 30; offset++) {
        final on = addDays(started, offset * 7 + 3);
        for (var week = 1; week <= total; week++) {
          for (var weekday = 1; weekday <= 7; weekday++) {
            final d = plan.dateFor(weekIndex: week, weekday: weekday, on: on);
            expect(d.weekday, weekday, reason: 'week $week day $weekday → $d');
            expect(
              plan.weekIndexOn(d),
              week,
              reason: 'round trip from $on: week $week day $weekday → $d',
            );
          }
        }
      }
    });

    test('a date before the plan began does not throw the cycle off', () {
      final before = DateTime(2026, 4, 15);
      final current = plan.weekIndexOn(before);
      expect(
        plan.dateFor(weekIndex: current, weekday: 1, on: before),
        mondayOf(before),
      );
    });
  });

  group('dateFor on a plan that goes somewhere', () {
    final plan = planFrom(DateTime(2026, 7, 20));

    test('ignores the reference — a block week happens once', () {
      // A block's week 5 is one week in one place. Passing a reference must not
      // move it, or a runner opening next week's calendar would see it slide.
      for (var week = 1; week <= 12; week++) {
        for (final on in <DateTime>[
          DateTime(2026, 7, 20),
          DateTime(2026, 9, 1),
          DateTime(2027, 1, 1),
        ]) {
          expect(
            plan.dateFor(weekIndex: week, weekday: 1, on: on),
            plan.dateFor(weekIndex: week, weekday: 1),
            reason: 'week $week seen from $on',
          );
        }
      }
    });
  });

  group('daysBetweenDates', () {
    test('counts whole calendar days, ignoring the time of day', () {
      expect(
        daysBetweenDates(
          DateTime(2026, 7, 20, 23, 59),
          DateTime(2026, 7, 21, 0, 1),
        ),
        1,
      );
      expect(
        daysBetweenDates(DateTime(2026, 7, 20), DateTime(2026, 7, 20, 18)),
        0,
      );
    });

    test('is negative before the start', () {
      expect(
        daysBetweenDates(DateTime(2026, 7, 20), DateTime(2026, 7, 18)),
        -2,
      );
    });

    test('is exact across a daylight-saving boundary', () {
      // Whatever the machine's timezone, seven calendar days is seven days —
      // never six-and-23-hours rounded down.
      expect(
        daysBetweenDates(DateTime(2026, 10, 21), DateTime(2026, 10, 28)),
        7,
      );
      expect(daysBetweenDates(DateTime(2027, 3, 24), DateTime(2027, 3, 31)), 7);
    });
  });
}
