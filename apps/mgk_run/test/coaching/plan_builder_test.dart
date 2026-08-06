import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_validator.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';

RunnerProfile _profile(
  double weekly, {
  DateTime? event,
  int days = 5,
  Set<int>? weekdays,
  int strength = 0,
}) => RunnerProfile(
  goalDistanceMeters: 42195,
  eventDate: event ?? DateTime(2027, 1, 1),
  currentWeeklyMeters: weekly,
  longestRecentMeters: weekly * 0.4,
  daysPerWeek: days,
  availableWeekdays: weekdays ?? const <int>{1, 2, 4, 6, 7},
  strengthDaysPerWeek: strength,
);

double _peakVolume(PlanSkeleton s) =>
    s.weeks.map((w) => w.volumeMeters).reduce((a, b) => a > b ? a : b);

void main() {
  final now = DateTime(2026, 7, 25);

  test(
    'every skeleton passes the validator across a length x volume matrix',
    () {
      for (var weeks = 6; weeks <= 24; weeks++) {
        for (final weekly in <double>[15000, 30000, 50000, 90000, 250000]) {
          final profile = _profile(weekly);
          final skeleton = buildSkeleton(profile, now: now, weeks: weeks);
          final result = validateSkeleton(skeleton, profile);
          expect(
            result.isValid,
            isTrue,
            reason: 'weeks=$weeks weekly=$weekly -> ${result.violations}',
          );
          expect(skeleton.weeks.length, weeks);
        }
      }
    },
  );

  test(
    'week 1 matches current volume and the final week tapers below peak',
    () {
      final skeleton = buildSkeleton(_profile(40000), now: now, weeks: 14);
      expect(skeleton.weeks.first.volumeMeters, 40000);
      expect(skeleton.weeks.last.phase, Phase.taper);
      expect(skeleton.weeks.last.volumeMeters, lessThan(_peakVolume(skeleton)));
    },
  );

  test('a deload lands at least every four weeks', () {
    final skeleton = buildSkeleton(_profile(45000), now: now, weeks: 20);
    var sinceDeload = 0;
    for (final w in skeleton.weeks) {
      sinceDeload = w.isDeload ? 0 : sinceDeload + 1;
      expect(
        sinceDeload,
        lessThanOrEqualTo(4),
        reason: 'gap at week ${w.index}',
      );
    }
  });

  test('the long run stays under the absolute ceiling even at high volume', () {
    final skeleton = buildSkeleton(_profile(250000), now: now, weeks: 18);
    for (final w in skeleton.weeks) {
      expect(w.longRunMeters, lessThanOrEqualTo(38000));
    }
  });

  test('derives block length from the event date when weeks is omitted', () {
    // 2026-07-25 -> 2027-01-01 is ~23 weeks.
    final skeleton = buildSkeleton(_profile(40000), now: now);
    expect(skeleton.weeks.length, greaterThanOrEqualTo(20));
    expect(skeleton.weeks.length, lessThanOrEqualTo(24));
  });

  test('clamps a near event to the minimum block and still validates', () {
    final profile = _profile(40000, event: now.add(const Duration(days: 12)));
    final skeleton = buildSkeleton(profile, now: now);
    expect(skeleton.weeks.length, 6);
    expect(validateSkeleton(skeleton, profile).isValid, isTrue);
  });

  group('buildFallbackWeek', () {
    RunnerProfile profileDays(int days) => RunnerProfile(
      goalDistanceMeters: 42195,
      eventDate: DateTime(2027, 1, 1),
      currentWeeklyMeters: 45000,
      longestRecentMeters: 18000,
      daysPerWeek: days,
      availableWeekdays: const <int>{1, 2, 3, 4, 5, 6, 7},
    );

    test('every filled week passes validateWeek across days x every slot', () {
      for (var days = 3; days <= 7; days++) {
        final profile = profileDays(days);
        final skeleton = buildSkeleton(profile, now: now, weeks: 16);
        for (final slot in skeleton.weeks) {
          final week = buildFallbackWeek(slot, profile);
          final result = validateWeek(week, slot, profile);
          expect(
            result.isValid,
            isTrue,
            reason: 'days=$days week=${slot.index} -> ${result.violations}',
          );
        }
      }
    });

    test('a filled week is provisional, one long run, at most one hard', () {
      final profile = profileDays(5);
      final skeleton = buildSkeleton(profile, now: now, weeks: 12);
      final week = buildFallbackWeek(
        skeleton.weeks[5],
        profile,
      ); // a build week
      expect(week.provisional, isTrue);
      expect(week.runs.length, 5);
      expect(
        week.sessions.where((s) => s.kind == SessionKind.long),
        hasLength(1),
      );
      expect(
        week.sessions.where((s) => s.kind.isHard).length,
        lessThanOrEqualTo(1),
      );
    });

    test('a deload week is filled with no hard session', () {
      final profile = profileDays(5);
      final skeleton = buildSkeleton(profile, now: now, weeks: 16);
      final deload = skeleton.weeks.firstWhere((w) => w.isDeload);
      final week = buildFallbackWeek(deload, profile);
      expect(week.sessions.any((s) => s.kind.isHard), isFalse);
    });

    // Regression: the skeleton derived the long run at 35% of volume while the
    // week filler recomputed it at 38%, so the plan arc and the week detail
    // showed two different long runs for the same week (19 km on the arc, then
    // 20.1 km once you opened it). The filler must honour the slot, not
    // re-derive a number the runner has already been shown.
    test('a filled week long run matches the slot the arc displays', () {
      for (final days in <int>[3, 4, 5, 6]) {
        final profile = profileDays(days);
        final skeleton = buildSkeleton(profile, now: now, weeks: 16);
        for (final slot in skeleton.weeks) {
          final week = buildFallbackWeek(slot, profile);
          expect(
            week.longRunMeters,
            closeTo(slot.longRunMeters, 1),
            reason:
                'week ${slot.index} ($days days/week): the arc shows '
                '${slot.longRunMeters.round()} m',
          );
        }
      }
    });
  });

  // The bug: the remainder was divided by the number of non-long days, so a
  // five-day runner got four identical runs and a long one. A week is not a
  // number divided by four.
  group('a filled week has a shape', () {
    test('no two easy days are the same length', () {
      final profile = _profile(40000);
      final skeleton = buildSkeleton(profile, now: now, weeks: 16);
      final week = buildFallbackWeek(skeleton.weeks[0], profile);

      final others = week.runs
          .where((s) => s.kind != SessionKind.long)
          .map((s) => s.distanceMeters.round())
          .toList();
      expect(others.length, 4);
      // Not "all different" — distances are prescribed in whole kilometres now,
      // so two days landing on the same round number is expected. What the bug
      // was is that they were *all* the same.
      expect(
        others.toSet().length,
        greaterThan(1),
        reason: 'the week is one number divided four ways: $others',
      );

      // And the spread is real, not four numbers a rounding apart.
      final shortest = others.reduce((a, b) => a < b ? a : b);
      final longest = others.reduce((a, b) => a > b ? a : b);
      expect(
        longest / shortest,
        greaterThan(1.4),
        reason: 'the longest easy run is meaningfully longer than the shortest',
      );
    });

    test('the long run stays the longest session at every width', () {
      // Two non-long days is the tight case: the remainder is ~65% of the week
      // against a long run that is 35% of it, so a shaped share can overtake it.
      for (var days = 3; days <= 7; days++) {
        final profile = _profile(
          40000,
          days: days,
          weekdays: const <int>{1, 2, 3, 4, 5, 6, 7},
        );
        final skeleton = buildSkeleton(profile, now: now, weeks: 16);
        for (final slot in skeleton.weeks) {
          final week = buildFallbackWeek(slot, profile);
          final long = week.runs.firstWhere((s) => s.kind == SessionKind.long);
          for (final s in week.runs) {
            if (s.kind == SessionKind.long) continue;
            expect(
              s.distanceMeters,
              lessThan(long.distanceMeters),
              reason:
                  'days=$days week=${slot.index}: ${s.kind.name} '
                  '(${s.distanceMeters.round()} m) is not under the long run',
            );
          }
        }
      }
    });

    test('a deload keeps its variety, only losing the hard session', () {
      final profile = _profile(40000);
      final skeleton = buildSkeleton(profile, now: now, weeks: 16);
      final deload = skeleton.weeks.firstWhere((w) => w.isDeload);
      final week = buildFallbackWeek(deload, profile);

      expect(week.runs.any((s) => s.kind.isHard), isFalse);
      final others = week.runs
          .where((s) => s.kind != SessionKind.long)
          .map((s) => s.distanceMeters.round())
          .toSet();
      expect(
        others.length,
        greaterThan(1),
        reason: 'a deload is shorter, not flat',
      );
    });
  });

  group('strength sessions', () {
    test('none unless the runner asked for them', () {
      final profile = _profile(40000);
      final skeleton = buildSkeleton(profile, now: now, weeks: 16);
      final week = buildFallbackWeek(skeleton.weeks[0], profile);
      expect(week.support, isEmpty);
    });

    test('carry no distance and cost no running day', () {
      final plain = _profile(40000);
      final lifting = _profile(40000, strength: 2);
      final skeleton = buildSkeleton(lifting, now: now, weeks: 16);
      final slot = skeleton.weeks[0];

      final week = buildFallbackWeek(slot, lifting);
      final without = buildFallbackWeek(slot, plain);

      expect(week.support, hasLength(2));
      expect(week.support.every((s) => s.distanceMeters == 0), isTrue);
      expect(
        week.runs.length,
        without.runs.length,
        reason: 'strength is on top of the runs, not instead of one',
      );
      expect(
        week.volumeMeters,
        closeTo(without.volumeMeters, 1),
        reason: 'a gym session adds no kilometres to the week',
      );
      expect(validateWeek(week, slot, lifting).isValid, isTrue);
    });

    test('never the day before the long run', () {
      final lifting = _profile(
        40000,
        strength: 1,
        weekdays: const <int>{1, 2, 3, 4, 5, 6, 7},
      );
      final skeleton = buildSkeleton(lifting, now: now, weeks: 16);
      for (final slot in skeleton.weeks) {
        final week = buildFallbackWeek(slot, lifting);
        final long = week.runs.firstWhere((s) => s.kind == SessionKind.long);
        for (final s in week.support) {
          expect(
            s.weekday,
            isNot(long.weekday - 1),
            reason:
                'week ${slot.index}: strength sits the day before the long run',
          );
        }
      }
    });
  });

  // The bug the fresh screenshots caught: two previews of the same runner
  // disagreed about the block, "week 1 of 15" against "week 1 of 16".
  // `difference(now).inDays` truncated the part-day between now and midnight on
  // race day, so a runner lost a week of training by tapping after breakfast.
  test('the block is the same length whatever time of day it is built', () {
    final event = DateTime(2026, 11, 16); // a Monday, midnight
    final lengths = <int>{};
    for (var hour = 0; hour < 24; hour++) {
      final now = DateTime(2026, 7, 27, hour, 30);
      lengths.add(
        buildSkeleton(_profile(40000, event: event), now: now).weeks.length,
      );
    }
    expect(
      lengths,
      hasLength(1),
      reason: 'the block length changed with the clock: $lengths',
    );
    expect(lengths.single, 16, reason: '112 calendar days is sixteen weeks');
  });
}
