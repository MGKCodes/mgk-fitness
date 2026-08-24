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

    group('a week goes on the grid without losing kilometres', () {
      test('the total survives, where rounding each session would not', () {
        // Seven days of 1.14 km. Rounded one at a time each falls to 1 km and
        // an 8 km week arrives as 7; apportioned, the leftover kilometre is
        // handed out and the week is still 8. That is the difference between a
        // display decision and deleting an eighth of somebody's training.
        final week = List<double>.filled(7, 8000 / 7);
        expect(week.map(roundPrescribed).reduce((a, b) => a + b), 7000);
        expect(prescribeAcross(week).reduce((a, b) => a + b), 8000);
      });

      test('every session is still a whole number, and none is zero', () {
        final out = prescribeAcross(<double>[4137, 200, 8900, 12480]);
        expect(out.every((m) => m % 1000 == 0), isTrue);
        expect(out.every((m) => m >= 1000), isTrue);
      });

      test('the longer session never comes back the shorter one', () {
        // What the largest-remainder order buys: with equal whole parts the
        // bigger raw number also has the bigger remainder, so it is served
        // first and cannot be overtaken by the day beneath it.
        final raw = <double>[13580, 13100, 9400, 4137, 2600];
        final out = prescribeAcross(raw);
        for (var i = 1; i < raw.length; i++) {
          expect(
            out[i],
            lessThanOrEqualTo(out[i - 1]),
            reason: 'raw $raw came back as $out',
          );
        }
      });

      test('a total too small for a kilometre each keeps the kilometres', () {
        // The one case the week cannot be held: three sessions and 1.2 km
        // between them. Nothing rounds away to nothing wins over the total.
        expect(prescribeAcross(<double>[400, 400, 400]), <double>[
          1000,
          1000,
          1000,
        ]);
      });

      test('nothing to apportion is not an error', () {
        expect(prescribeAcross(const <double>[]), isEmpty);
      });
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

    test('a stored session is already on the grid, not rounded on the way out', () {
      // The bug behind the bug. `roundPrescribed` documented a whole-kilometre
      // stored grid that nothing ever applied, so a session really was 4,137 m
      // and every formatter in the app was faithfully reporting it — which made
      // "4 km on Plan, 4.1 km on Home" a difference of opinion between call
      // sites rather than something one function decided.
      for (var days = 3; days <= 7; days++) {
        for (final weekly in <double>[15000, 40000, 90000]) {
          final p = profile(days: days, weekly: weekly);
          for (final slot in buildSkeleton(p, now: now).weeks) {
            for (final s in buildFallbackWeek(slot, p).runs) {
              expect(
                s.distanceMeters % 1000,
                0,
                reason:
                    'days=$days weekly=$weekly week=${slot.index}: stored '
                    '${s.distanceMeters} m',
              );
            }
          }
        }
      }
    });

    test('the working is kept — in the arc, which is where it belongs', () {
      // 6.8 km is what the plan computed, and it is what explains why the
      // runner was shown 7. The skeleton keeps it. The week does not need it:
      // a week is what the runner is asked to run, and nobody is asked to run
      // 6.8 km.
      final p = profile();
      final arc = buildSkeleton(p, now: now).weeks;
      expect(
        arc.any((w) => w.longRunMeters % 1000 != 0),
        isTrue,
        reason: 'the arc rounded its own long runs away',
      );
      expect(
        arc.any((w) => w.volumeMeters % 1000 != 0),
        isTrue,
        reason: 'the arc rounded its own weekly volumes away',
      );
    });

    test("the week prescribes the arc's long run, on the grid", () {
      // Not a re-derivation: the filler once recomputed the long run at 38% of
      // volume against the skeleton's 35%, and the arc and the week detail
      // showed two different long runs for the same week. It still takes the
      // arc's number — it just states it in whole kilometres.
      final p = profile();
      for (final slot in buildSkeleton(p, now: now).weeks) {
        expect(
          buildFallbackWeek(slot, p).longRunMeters,
          roundPrescribed(slot.longRunMeters),
        );
      }
    });

    test('no session is ever longer than the long run', () {
      // Ties are accepted, and cannot reasonably be prevented: keeping the long
      // run clear needs a full grid step of clearance — a whole kilometre — and
      // with three running days an even split is already 32.5% of the week
      // against a long run at 35%. Those days really are nearly as long as the
      // long run. What must hold is that nothing *exceeds* it, and that the
      // week's `longRunMeters` is still the long run's own number, because that
      // is the figure the arc and the week have to agree on.
      for (var days = 3; days <= 7; days++) {
        final p = profile(days: days);
        for (final slot in buildSkeleton(p, now: now).weeks) {
          final week = buildFallbackWeek(slot, p);
          final long = week.runs.firstWhere((s) => s.kind == SessionKind.long);
          for (final s in week.runs) {
            if (identical(s, long)) continue;
            expect(
              s.distanceMeters,
              lessThanOrEqualTo(long.distanceMeters),
              reason: 'days=$days week=${slot.index}',
            );
          }
          expect(
            week.longRunMeters,
            long.distanceMeters,
            reason: 'days=$days week=${slot.index}',
          );
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
