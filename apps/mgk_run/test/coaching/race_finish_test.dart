import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_history.dart';
import 'package:mgk_run/src/features/coaching/domain/race_day.dart';
import 'package:mgk_run/src/features/coaching/domain/race_finish.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/recording/domain/best_effort.dart';
import 'package:mgk_run/src/features/recording/domain/race_breakdown.dart';
import 'package:mgk_run/src/features/recording/domain/run_race.dart';
import 'package:mgk_run/src/features/recording/domain/run_split.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

/// What the race screen says about a race (ADR-0049).
///
/// Everything here is a sentence somebody will read about the run they will
/// quote for years, so the tests mostly pin what must *not* be said: a best
/// that has since been beaten, a half marathon time that is really the
/// phone's, a race offered on a treadmill, a shakeout filed as a marathon.
void main() {
  const half = 21097.5;

  RunSummary race({
    String id = 'sunday',
    DateTime? at,
    Duration phone = const Duration(hours: 2, minutes: 0, seconds: 47),
    Duration? official = const Duration(hours: 2, minutes: 0, seconds: 30),
    double meters = 21685.8,
    double raceMeters = half,
  }) => RunSummary(
    id: id,
    startedAt: at ?? DateTime(2026, 10, 11, 9, 31),
    duration: phone,
    distanceMeters: meters,
    race: RunRace(distanceMeters: raceMeters, officialTime: official),
  );

  group('where the race stands', () {
    test('the first at a distance says so, and gives the time to beat', () {
      final s = raceStandingFor(race(), const <RunSummary>[])!;

      expect(s.headline, 'Your first half marathon.');
      expect(s.detail, contains('2:00:30'));
      expect(s.isFirst, isTrue);
    });

    test('the official time is the one compared, not the phone’s', () {
      final earlier = race(
        id: 'spring',
        at: DateTime(2026, 4, 12, 9),
        phone: const Duration(hours: 2, minutes: 1),
        official: const Duration(hours: 2, minutes: 0, seconds: 40),
      );
      // Sunday's phone time (2:00:47) is slower than spring's official
      // 2:00:40; its official 2:00:30 is quicker. Official wins.
      final s = raceStandingFor(race(), <RunSummary>[earlier])!;

      expect(s.headline, 'Your fastest half marathon.');
      expect(s.detail, '0:10 quicker than your previous best of 2:00:40.');
    });

    test('a best that has since been beaten is not called one', () {
      final later = race(
        id: 'next-spring',
        at: DateTime(2027, 4, 11, 9),
        official: const Duration(hours: 1, minutes: 55),
      );
      final s = raceStandingFor(race(), <RunSummary>[later])!;

      // Still the first: that stays true for ever.
      expect(s.headline, 'Your first half marathon.');
      expect(s.isBest, isFalse);
    });

    test('a slower one says what the best is', () {
      final best = race(
        id: 'spring',
        at: DateTime(2026, 4, 12, 9),
        official: const Duration(hours: 1, minutes: 58, seconds: 16),
      );
      final s = raceStandingFor(race(), <RunSummary>[best])!;

      expect(s.headline, 'Half marathon number 2.');
      expect(s.detail, 'Your best is 1:58:16, 2:14 quicker than this one.');
    });

    test('races at other distances are not compared', () {
      final tenK = race(
        id: 'tenk',
        at: DateTime(2026, 6, 1, 9),
        raceMeters: 10000,
        meters: 10100,
        official: const Duration(minutes: 50),
      );
      expect(
        raceStandingFor(race(), <RunSummary>[tenK])!.headline,
        'Your first half marathon.',
      );
    });

    test('a run that is not a race has no standing', () {
      final run = RunSummary(
        startedAt: DateTime(2026, 10, 11),
        duration: const Duration(hours: 2),
        distanceMeters: 21685.8,
      );
      expect(raceStandingFor(run, const <RunSummary>[]), isNull);
    });
  });

  group('records inside a race', () {
    test('the race distance itself is left to the result', () {
      // The phone's fastest 21.0975 km inside a race it measured as 21.69 km
      // is shorter than the course. Beside the official time it would be a
      // second, wrong, half marathon time.
      final kept = recordsInsideRace(const <BestEffort>[
        BestEffort(distanceMeters: 5000, duration: Duration(minutes: 25)),
        BestEffort(distanceMeters: 10000, duration: Duration(minutes: 52)),
        BestEffort(distanceMeters: half, duration: Duration(minutes: 117)),
      ], const RunRace(distanceMeters: half));

      expect(kept.map((r) => r.distanceMeters), <double>[5000, 10000]);
    });
  });

  group('offering to mark a race', () {
    RunSummary run(double meters, {String type = 'outdoor'}) => RunSummary(
      startedAt: DateTime(2026, 10, 11),
      duration: const Duration(hours: 1),
      distanceMeters: meters,
      type: type,
    );

    test('Sunday’s 21.69 km is offered as a half marathon', () {
      expect(suggestedRaceDistance(run(21685.8)), half);
    });

    test('a 5.3 km parkrun is offered as a 5K', () {
      expect(suggestedRaceDistance(run(5300)), 5000);
    });

    test('a 7 km run is not offered as anything', () {
      expect(suggestedRaceDistance(run(7000)), isNull);
    });

    test('a treadmill run never is', () {
      expect(suggestedRaceDistance(run(5000, type: 'treadmill')), isNull);
    });

    test('a run already marked is not offered again', () {
      expect(suggestedRaceDistance(race()), isNull);
    });
  });

  group('how it was run', () {
    RaceBreakdown breakdownOf(List<int> secondsPerKm) {
      final splits = <RunSplit>[
        for (var i = 0; i < secondsPerKm.length; i++)
          RunSplit(
            index: i + 1,
            distanceMeters: 1000,
            duration: Duration(seconds: secondsPerKm[i]),
          ),
      ];
      return raceBreakdownFor(splits, secondsPerKm.length * 1000.0)!;
    }

    test('Sunday: a fade, with the biggest drop after 10K', () {
      final b = raceBreakdownFor(<RunSplit>[
        for (final (i, s) in <int>[
          323, 307, 309, 302, 292, 306, 339, 320, 326, 311, //
          347, 325, 356, 346, 338, 356, 346, 349, 353, 355, 371,
        ].indexed)
          RunSplit(
            index: i + 1,
            distanceMeters: 1000,
            duration: Duration(seconds: s),
          ),
        const RunSplit(
          index: 22,
          distanceMeters: 685.8,
          duration: Duration(seconds: 260),
        ),
      ], half)!;
      final note = raceNoteFor(b);

      expect(note.headline, 'You slowed in the second half.');
      expect(note.detail, contains('First half 5:25 /km'));
      expect(note.detail, contains('The biggest drop came after 10K.'));
    });

    test('a negative split is named as the right way round', () {
      final note = raceNoteFor(
        breakdownOf(<int>[310, 305, 300, 300, 295, 290, 290, 285, 280, 275]),
      );
      expect(note.headline, 'You finished faster than you started.');
    });

    test('an even race is said to be one', () {
      final note = raceNoteFor(breakdownOf(List<int>.filled(10, 300)));
      expect(note.headline, 'An even race.');
    });
  });

  group('the plan behind it', () {
    PlanRecord record({
      String id = 'p1',
      DateTime? event,
      double? goal = half,
      int weeks = 12,
      DateTime? start,
    }) => PlanRecord(
      id: id,
      startDate: start ?? DateTime(2026, 7, 20),
      weeks: weeks,
      isActive: false,
      goalDistanceMeters: goal,
      eventDate: event ?? DateTime(2026, 10, 11),
    );

    test('a block aimed at the day is the plan behind the race', () {
      final plans = <LabelledPlan>[
        LabelledPlan(record: record(), label: 'Half marathon plan'),
      ];
      expect(planBehindRace(plans, race())?.label, 'Half marathon plan');
    });

    test('a plan aimed at another day is not', () {
      final plans = <LabelledPlan>[
        LabelledPlan(
          record: record(event: DateTime(2026, 10, 18)),
          label: 'Half marathon plan',
        ),
      ];
      expect(planBehindRace(plans, race()), isNull);
    });

    test('a plan with no date was never aimed at a race', () {
      final plans = <LabelledPlan>[
        LabelledPlan(
          record: PlanRecord(
            id: 'h',
            startDate: DateTime(2026, 7, 20),
            weeks: 12,
            isActive: true,
            goalDistanceMeters: half,
          ),
          label: 'Half marathon plan',
        ),
      ];
      expect(planBehindRace(plans, race()), isNull);
    });

    test('the training totals the plan window and leaves race day out', () {
      final plan = LabelledPlan(record: record(), label: 'Half marathon plan');
      RunSummary run(DateTime at, double meters) => RunSummary(
        startedAt: at,
        duration: const Duration(minutes: 50),
        distanceMeters: meters,
      );
      final runs = <RunSummary>[
        run(DateTime(2026, 7, 19), 9000), // the day before the plan
        run(DateTime(2026, 7, 21), 6000), // week 1
        run(DateTime(2026, 7, 26), 12000), // week 1
        run(DateTime(2026, 9, 27), 18000), // week 10, the longest
        run(DateTime(2026, 10, 7), 5000), // race week
        race(), // race day: the race itself
      ];
      final b = buildUpFor(plan, runs);

      expect(b.runs, 4);
      expect(b.meters, 41000);
      expect(b.longest?.distanceMeters, 18000);
      expect(b.weeklyMeters, hasLength(12));
      expect(b.weeklyMeters.first, 18000);
      expect(b.weeklyMeters[9], 18000);
      expect(b.weeklyMeters.last, 5000);
    });
  });

  group('the plan’s race-day run', () {
    final raceDay = DateTime(2026, 10, 11);
    final start = DateTime(2026, 7, 20);
    final profile = RunnerProfile(
      goalDistanceMeters: half,
      eventDate: raceDay,
      currentWeeklyMeters: 30000,
      longestRecentMeters: 14000,
      daysPerWeek: 4,
      availableWeekdays: const <int>{2, 4, 6, 7},
    );
    final plan = StoredPlan(
      id: 'plan',
      profile: profile,
      skeleton: buildSkeleton(profile, now: start),
      startDate: mondayOf(start),
    );
    RunSummary run(String id, double meters, {int hour = 9}) => RunSummary(
      id: id,
      startedAt: DateTime(2026, 10, 11, hour),
      duration: const Duration(minutes: 30),
      distanceMeters: meters,
    );

    test('the race is the longest run of the day', () {
      final shakeout = run('shakeout', 2000, hour: 7);
      final theRace = run('race', 21600);
      expect(isPlanRaceRun(plan, theRace, <RunSummary>[shakeout]), isTrue);
      expect(isPlanRaceRun(plan, shakeout, <RunSummary>[theRace]), isFalse);
    });

    test('a shakeout before the race exists is never filed as the race', () {
      // At 7am the shakeout is the longest run of the day, because the race
      // has not happened yet. Half the distance is the floor.
      final shakeout = run('shakeout', 3000, hour: 7);
      expect(isPlanRaceRun(plan, shakeout, const <RunSummary>[]), isFalse);
    });

    test('a run on another day is not the race', () {
      final saturday = RunSummary(
        id: 'sat',
        startedAt: DateTime(2026, 10, 10, 9),
        duration: const Duration(hours: 2),
        distanceMeters: 21600,
      );
      expect(isPlanRaceRun(plan, saturday, const <RunSummary>[]), isFalse);
    });

    test('the time given on the run is what Home’s card opens on', () {
      final marked = RunSummary(
        id: 'race',
        startedAt: DateTime(2026, 10, 11, 9),
        duration: const Duration(hours: 2, minutes: 0, seconds: 47),
        distanceMeters: 21685.8,
        race: const RunRace(
          distanceMeters: half,
          officialTime: Duration(hours: 2, minutes: 0, seconds: 30),
        ),
      );
      final result = raceResultFor(plan, <RunSummary>[marked])!;

      expect(result.time, const Duration(hours: 2, minutes: 0, seconds: 30));
      expect(
        result.watchTime,
        const Duration(hours: 2, minutes: 0, seconds: 47),
      );
    });
  });
}
