import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/profile/domain/runner_stats.dart';
import 'package:mgk_run/src/features/recording/domain/best_effort.dart';
import 'package:mgk_run/src/features/recording/domain/run_race.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

/// **A race counts as its own time** (ADR-0049).
///
/// The phone's fastest 21.0975 km inside a half it measured as 21.69 km is
/// shorter than the course: on 11 October that stretch was 1:57:40 against a
/// chip time of 2:00:30. Profile's half marathon figure was the stretch. These
/// pin that it is now the race, and that nothing else moves.
void main() {
  const half = 21097.5;

  RunSummary sunday({RunRace? race}) => RunSummary(
    id: 'sunday',
    startedAt: DateTime(2026, 10, 11, 9, 31),
    duration: const Duration(hours: 2, minutes: 0, seconds: 47),
    distanceMeters: 21685.8,
    bestEfforts: const <BestEffort>[
      BestEffort(
        distanceMeters: 5000,
        duration: Duration(minutes: 25, seconds: 16),
      ),
      BestEffort(
        distanceMeters: 10000,
        duration: Duration(minutes: 52, seconds: 4),
      ),
      BestEffort(
        distanceMeters: half,
        duration: Duration(hours: 1, minutes: 57, seconds: 40),
      ),
    ],
    race: race,
  );

  test('a training run keeps its stretches', () {
    final stats = RunnerStats.from(<RunSummary>[sunday()]);
    expect(
      stats.averageEffortAt(half),
      const Duration(hours: 1, minutes: 57, seconds: 40),
    );
  });

  test('a race counts its official time at its distance', () {
    final stats = RunnerStats.from(<RunSummary>[
      sunday(
        race: const RunRace(
          distanceMeters: half,
          officialTime: Duration(hours: 2, minutes: 0, seconds: 30),
        ),
      ),
    ]);

    expect(
      stats.averageEffortAt(half),
      const Duration(hours: 2, minutes: 0, seconds: 30),
    );
    expect(
      stats.bestEffortAt(half),
      const Duration(hours: 2, minutes: 0, seconds: 30),
    );
    // The 5K and 10K inside it are untouched.
    expect(stats.bestEffortAt(5000), const Duration(minutes: 25, seconds: 16));
  });

  test('and the phone’s time where there is no official one', () {
    final stats = RunnerStats.from(<RunSummary>[
      sunday(race: const RunRace(distanceMeters: half)),
    ]);
    expect(
      stats.bestEffortAt(half),
      const Duration(hours: 2, minutes: 0, seconds: 47),
    );
  });

  test('a race with no route still counts at its distance', () {
    final typed = RunSummary(
      id: 'typed',
      startedAt: DateTime(2026, 4, 12, 9),
      duration: const Duration(hours: 2, minutes: 4),
      distanceMeters: half,
      type: 'manual',
      race: const RunRace(distanceMeters: half),
    );
    final stats = RunnerStats.from(<RunSummary>[typed]);

    expect(stats.bestEffortAt(half), const Duration(hours: 2, minutes: 4));
    expect(stats.hasRecordlessRuns, isFalse);
  });

  test('a race at a distance with no record changes nothing', () {
    final tenMiler = RunSummary(
      id: 'ten',
      startedAt: DateTime(2026, 5, 3, 9),
      duration: const Duration(hours: 1, minutes: 25),
      distanceMeters: 16200,
      bestEfforts: const <BestEffort>[
        BestEffort(distanceMeters: 5000, duration: Duration(minutes: 25)),
        BestEffort(distanceMeters: 10000, duration: Duration(minutes: 51)),
      ],
      race: const RunRace(distanceMeters: 16093),
    );
    expect(tenMiler.recordEfforts, tenMiler.bestEfforts);
  });
}
