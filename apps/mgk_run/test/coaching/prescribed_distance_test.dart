import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_units/mgk_units.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/prescribed_distance.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';

void main() {
  final now = DateTime(2026, 7, 27);

  RunnerProfile profile({int days = 5, double weekly = 40000}) => RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: DateTime(2026, 11, 16),
    currentWeeklyMeters: weekly,
    longestRecentMeters: weekly * 0.4,
    daysPerWeek: days,
    availableWeekdays: const <int>{1, 2, 3, 4, 5, 6, 7},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );

  group('prescribed distances are round', () {
    test('to the nearest kilometre, never below one', () {
      expect(roundPrescribed(6800), 7000);
      expect(roundPrescribed(7800), 8000);
      expect(roundPrescribed(4400), 4000);
      expect(roundPrescribed(14000), 14000);
      expect(roundPrescribed(200), 1000, reason: 'nothing rounds away to zero');
      expect(roundPrescribed(0), 0);
    });

    // The bug this exists for: a plan that says "run 6.8 km" is claiming a
    // precision it does not have, and invites the runner to chase it.
    test('every session in every week reads as a whole number', () {
      for (var days = 3; days <= 7; days++) {
        for (final weekly in <double>[15000, 40000, 90000]) {
          final p = profile(days: days, weekly: weekly);
          for (final slot in buildSkeleton(p, now: now).weeks) {
            for (final s in buildFallbackWeek(slot, p).runs) {
              for (final unit in UnitSystem.values) {
                expect(
                  prescribedValue(s.distanceMeters, unit) % 1,
                  0,
                  reason: 'days=$days weekly=$weekly week=${slot.index}',
                );
              }
            }
          }
        }
      }
    });

    test('the working is kept, not thrown away', () {
      // 6.8 km is what the plan computed, and it is what explains why the
      // runner was shown 7. Rounding at generation would lose it.
      final p = profile();
      final exact = <double>[
        for (final slot in buildSkeleton(p, now: now).weeks)
          for (final s in buildFallbackWeek(slot, p).runs) s.distanceMeters,
      ];
      expect(
        exact.any((m) => m % 1000 != 0),
        isTrue,
        reason: 'every stored distance landed on a round number by itself',
      );
    });

    test("the week still copies the arc's long run exactly", () {
      final p = profile();
      for (final slot in buildSkeleton(p, now: now).weeks) {
        expect(buildFallbackWeek(slot, p).longRunMeters, slot.longRunMeters);
      }
    });

    test('the long run is always the longest session stored', () {
      // Two rows *displaying* the same rounded number is accepted, and cannot
      // reasonably be prevented: guaranteeing it needs a full display unit of
      // clearance — a mile, on the coarser grid — and with three running days
      // an even split is already 32.5% of the week against a long run at 35%.
      // Those days really are nearly as long as the long run. What must never
      // tie is the stored order, because that is what picks the long run.
      for (var days = 3; days <= 7; days++) {
        final p = profile(days: days);
        for (final slot in buildSkeleton(p, now: now).weeks) {
          final week = buildFallbackWeek(slot, p);
          final long = week.runs.firstWhere((s) => s.kind == SessionKind.long);
          for (final s in week.runs) {
            if (identical(s, long)) continue;
            expect(
              s.distanceMeters,
              lessThan(long.distanceMeters),
              reason: 'days=$days week=${slot.index}',
            );
          }
        }
      }
    });
  });

  group('a distance with a name is called by it', () {
    test('the standard races', () {
      expect(raceName(42195), 'Marathon');
      expect(raceName(21097.5), 'Half marathon');
      expect(raceName(10000), '10K');
      expect(raceName(5000), '5K');
      expect(raceName(30000), isNull);
    });

    test('a name beats a rounding of it, in either unit', () {
      // "26 mi" is a rounding of 26.2 and "42 km" a rounding of 42.195. The
      // word is shorter *and* more accurate than either.
      expect(describeGoal(42195, UnitSystem.imperial), 'Marathon');
      expect(describeGoal(42195, UnitSystem.metric), 'Marathon');
      expect(describeGoal(30000, UnitSystem.metric), '30 km');
    });

    test('the exact distance is still what is stored', () {
      // Every pace projection depends on 42,195 rather than on 42 or on 26.
      const marathon = 42195.0;
      expect(raceName(marathon), 'Marathon');
      expect(marathon, 42195.0);
    });

    test('a profile that stored 21097 is still a half', () {
      expect(raceName(21097), 'Half marathon');
      expect(raceName(21098), 'Half marathon');
    });
  });

  group('the runner reads a round number in their own unit', () {
    test('miles are whole miles, not a converted kilometre', () {
      // 7 km is 4.35 mi. "4.3 mi" is not a round number to anyone who thinks in
      // miles, and the whole point of rounding is ease of use.
      expect(formatPrescribed(7000, UnitSystem.imperial), '4 mi');
      expect(formatPrescribed(7000, UnitSystem.metric), '7 km');
      expect(formatPrescribed(14000, UnitSystem.imperial), '9 mi');
      expect(formatPrescribed(4000, UnitSystem.imperial), '2 mi');
    });

    test('nothing rounds away to nothing', () {
      expect(formatPrescribed(1000, UnitSystem.imperial), '1 mi');
    });

    test('the week total is the sum of the rows, not a converted total', () {
      // Five sessions rounded down to whole miles add to 24; 40 km converts to
      // 25. A header that says 25 over rows adding to 24 is a bug the runner
      // can do the arithmetic on.
      const week = <double>[7000, 4000, 8000, 7000, 14000];
      expect(formatPrescribedTotal(week, UnitSystem.metric), '40 km');
      expect(formatPrescribedTotal(week, UnitSystem.imperial), '24 mi');
    });

    test('switching units never changes what is stored', () {
      // The toggle re-reads the plan; it must not rewrite it, or two runners on
      // the same plan would be on different plans.
      const stored = 7000.0;
      expect(prescribedValue(stored, UnitSystem.metric), 7);
      expect(prescribedValue(stored, UnitSystem.imperial), 4);
      expect(stored, 7000.0);
    });
  });

  group('a run near what was asked counts as that session', () {
    const tenK = PlannedSession(
      weekday: DateTime.tuesday,
      kind: SessionKind.easy,
      distanceMeters: 10000,
    );

    test('9.2 km is a 10 km run', () {
      expect(fulfils(tenK, 9200), isTrue);
    });

    test('the band is symmetric, and it has ends', () {
      expect(fulfils(tenK, 11000), isTrue);
      expect(fulfils(tenK, 8000), isFalse, reason: 'that is an 8 km run');
      expect(fulfils(tenK, 13000), isFalse, reason: 'that is a longer run');
    });

    test('short sessions get a floor, not a tighter standard', () {
      const twoK = PlannedSession(
        weekday: DateTime.tuesday,
        kind: SessionKind.recovery,
        distanceMeters: 2000,
      );
      // 12% of 2 km is 240 m, which is unreasonably tight for a jog.
      expect(fulfils(twoK, 2400), isTrue);
      expect(toleranceFor(2000).high, 2500);
    });

    test('a session with no distance is satisfied by turning up', () {
      const commitment = PlannedSession(
        weekday: DateTime.saturday,
        kind: SessionKind.timeTrial,
        label: 'parkrun',
      );
      expect(fulfils(commitment, 4800), isTrue);
      expect(fulfils(commitment, 0), isFalse);
    });

    test('a miles runner is judged on the miles they were told', () {
      // The trap: a 4 km session reads as "2 mi", and two miles is 3.2 km —
      // nearly 20% under the stored number, outside any sane tolerance on it.
      // They ran the session they were given.
      const fourK = PlannedSession(
        weekday: DateTime.tuesday,
        kind: SessionKind.easy,
        distanceMeters: 4000,
      );
      expect(
        fulfils(fourK, 3219, unit: UnitSystem.imperial),
        isTrue,
        reason: 'two miles, exactly as prescribed',
      );
      expect(
        fulfils(fourK, 3219),
        isFalse,
        reason: 'a metric runner was told 4 km, and 3.2 is not that',
      );
    });

    test('strength is not fulfilled by running', () {
      const strength = PlannedSession(
        weekday: DateTime.wednesday,
        kind: SessionKind.strength,
      );
      expect(fulfils(strength, 8000), isFalse);
    });
  });
}
