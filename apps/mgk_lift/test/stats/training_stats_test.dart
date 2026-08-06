import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/stats/domain/training_stats.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';
import 'package:mgk_units/mgk_units.dart';

/// A finished session on [day] with the given sets on one movement.
Session sessionOn(
  DateTime day, {
  String exercise = 'Barbell Bench Press',
  List<SessionSet> sets = const <SessionSet>[],
}) => Session(
  id: '${day.toIso8601String()}-$exercise',
  name: 'Session',
  startedAt: day,
  endedAt: day.add(const Duration(hours: 1)),
  exercises: <SessionExercise>[
    SessionExercise(id: 'e', name: exercise, orderIndex: 0, sets: sets),
  ],
);

SessionSet working(double kg, int reps) => SessionSet(
  id: 'w-$kg-$reps',
  setNumber: 1,
  weightKg: kg,
  reps: reps,
  isCompleted: true,
);

SessionSet warmup(double kg, int reps) => SessionSet(
  id: 'wu-$kg-$reps',
  setNumber: 1,
  weightKg: kg,
  reps: reps,
  isCompleted: true,
  setType: SetType.warmup,
);

void main() {
  group('what counts', () {
    test('warm-ups are logged but excluded from volume', () {
      // Three empty-bar sets before a heavy single must not read as a bigger
      // session than the single.
      final stats = TrainingStats.from(
        <Session>[
          sessionOn(
            DateTime(2026, 8, 3),
            sets: <SessionSet>[
              warmup(20, 10),
              warmup(60, 5),
              working(140, 1),
            ],
          ),
        ],
        now: DateTime(2026, 8, 6),
      );
      expect(stats.totalVolume.kilograms, 140);
      expect(stats.totalSets, 1);
    });

    test('the session header and the stats agree about warm-ups', () {
      // Found by screenshotting the session screen: the header read 2010 kg
      // where the stats read 1410, because "what counts" was defined twice and
      // the two had drifted. Same lifter, two different totals depending which
      // screen they were on.
      final session = sessionOn(
        DateTime(2026, 8, 3),
        sets: <SessionSet>[warmup(60, 10), working(80, 8), working(85, 6)],
      );
      final stats = TrainingStats.from(
        <Session>[session],
        now: DateTime(2026, 8, 6),
      );

      expect(session.volumeKg, 1150);
      expect(stats.totalVolume.kilograms, session.volumeKg);
      expect(session.completedSets, stats.totalSets);
    });

    test('a warm-up cannot be the top set of an exercise', () {
      final session = sessionOn(
        DateTime(2026, 8, 3),
        sets: <SessionSet>[warmup(200, 5), working(100, 5)],
      );
      expect(session.exercises.single.topSet!.weightKg, 100);
    });

    test('an unticked set counts for nothing', () {
      final stats = TrainingStats.from(
        <Session>[
          sessionOn(
            DateTime(2026, 8, 3),
            sets: <SessionSet>[
              working(100, 5),
              const SessionSet(id: 'x', setNumber: 2, weightKg: 100, reps: 5),
            ],
          ),
        ],
        now: DateTime(2026, 8, 6),
      );
      expect(stats.totalVolume.kilograms, 500);
      expect(stats.totalSets, 1);
    });

    test('a session still in progress is not in the totals', () {
      final open = Session(
        id: 'open',
        name: 'Now',
        startedAt: DateTime(2026, 8, 6),
        exercises: <SessionExercise>[
          SessionExercise(
            id: 'e',
            name: 'Squat',
            orderIndex: 0,
            sets: <SessionSet>[working(100, 5)],
          ),
        ],
      );
      final stats = TrainingStats.from(
        <Session>[open],
        now: DateTime(2026, 8, 6),
      );
      expect(stats.sessions, 0);
      expect(stats.totalVolume.kilograms, 0);
    });
  });

  group('week bucketing — the bug ported from Liftio', () {
    test('a week runs Monday to Sunday', () {
      final monday = DateTime(2026, 8, 3);
      final sunday = DateTime(2026, 8, 9, 22);
      expect(
        TrainingStats.startOfWeek(sunday),
        TrainingStats.startOfWeek(monday),
      );
    });

    test('Wednesday and Thursday are the same week', () {
      // Liftio bucketed by `floor(timestamp / msPerWeek)` — weeks counted from
      // the Unix epoch, which was a THURSDAY. So its weeks ran Thursday to
      // Wednesday, and this pair landed in two different ones.
      final wed = DateTime(2026, 8, 5, 18);
      final thu = DateTime(2026, 8, 6, 18);
      expect(TrainingStats.startOfWeek(wed), TrainingStats.startOfWeek(thu));
    });

    test('Monday and the following Sunday are ONE streak week, not two', () {
      final stats = TrainingStats.from(
        <Session>[
          sessionOn(DateTime(2026, 8, 3), sets: <SessionSet>[working(100, 5)]),
          sessionOn(
            DateTime(2026, 8, 9),
            exercise: 'Squat',
            sets: <SessionSet>[working(100, 5)],
          ),
        ],
        now: DateTime(2026, 8, 9, 23),
      );
      expect(stats.currentWeekStreak, 1);
      expect(stats.longestWeekStreak, 1);
    });
  });

  group('streaks', () {
    test('consecutive weeks accumulate', () {
      final stats = TrainingStats.from(
        <Session>[
          for (var w = 0; w < 4; w++)
            sessionOn(
              DateTime(2026, 7, 13).add(Duration(days: 7 * w)),
              sets: <SessionSet>[working(100, 5)],
            ),
        ],
        now: DateTime(2026, 8, 5),
      );
      expect(stats.currentWeekStreak, 4);
      expect(stats.longestWeekStreak, 4);
    });

    test('a missed week resets the current streak but not the record', () {
      final stats = TrainingStats.from(
        <Session>[
          sessionOn(DateTime(2026, 6, 1), sets: <SessionSet>[working(100, 5)]),
          sessionOn(DateTime(2026, 6, 8), sets: <SessionSet>[working(100, 5)]),
          sessionOn(DateTime(2026, 6, 15), sets: <SessionSet>[working(100, 5)]),
          // gap
          sessionOn(DateTime(2026, 8, 3), sets: <SessionSet>[working(100, 5)]),
        ],
        now: DateTime(2026, 8, 5),
      );
      expect(stats.currentWeekStreak, 1);
      expect(stats.longestWeekStreak, 3);
    });

    test('not having trained yet this week does not break the streak', () {
      // It is Tuesday for somebody. The streak breaks when a whole week goes
      // by empty, not the moment a new one starts.
      final stats = TrainingStats.from(
        <Session>[
          sessionOn(DateTime(2026, 7, 27), sets: <SessionSet>[working(100, 5)]),
        ],
        now: DateTime(2026, 8, 4), // Tuesday of the following week
      );
      expect(stats.currentWeekStreak, 1);
    });

    test('two empty weeks does break it', () {
      final stats = TrainingStats.from(
        <Session>[
          sessionOn(DateTime(2026, 7, 20), sets: <SessionSet>[working(100, 5)]),
        ],
        now: DateTime(2026, 8, 4),
      );
      expect(stats.currentWeekStreak, 0);
    });
  });

  group('estimated one-rep max', () {
    test('Epley: weight x (1 + reps / 30)', () {
      final e = TrainingStats.estimateOneRepMax(Mass.kilograms(100), 5);
      expect(e!.kilograms, closeTo(116.667, 0.001));
    });

    test('a single is itself, not an extrapolation', () {
      final e = TrainingStats.estimateOneRepMax(Mass.kilograms(140), 1);
      expect(e!.kilograms, 140);
    });

    test('high reps return nothing rather than an invention', () {
      // Epley is a straight line fitted to low-rep work. Liftio allowed up to
      // 30 reps, where it claims a double — that is not an estimate.
      expect(TrainingStats.estimateOneRepMax(Mass.kilograms(60), 20), isNull);
      expect(TrainingStats.estimateOneRepMax(Mass.kilograms(60), 13), isNull);
      expect(
        TrainingStats.estimateOneRepMax(Mass.kilograms(60), 12),
        isNotNull,
      );
    });

    test('bodyweight and nonsense return nothing', () {
      expect(TrainingStats.estimateOneRepMax(Mass.zero, 10), isNull);
      expect(TrainingStats.estimateOneRepMax(Mass.kilograms(100), 0), isNull);
    });

    test('the best estimate wins, not the heaviest weight', () {
      // 100x5 estimates 116.7; 110x1 estimates 110. The lighter set is the
      // better lift, and reporting the heavier one would hide progress.
      final best = TrainingStats.bestOneRepMax(<Session>[
        sessionOn(
          DateTime(2026, 8, 3),
          sets: <SessionSet>[working(100, 5), working(110, 1)],
        ),
      ], 'Barbell Bench Press');

      expect(best!.estimate.kilograms, closeTo(116.667, 0.001));
      expect(best.weight.kilograms, 100);
      expect(best.reps, 5);
    });

    test('warm-ups cannot set a personal best', () {
      final best = TrainingStats.bestOneRepMax(<Session>[
        sessionOn(
          DateTime(2026, 8, 3),
          sets: <SessionSet>[warmup(200, 5), working(100, 5)],
        ),
      ], 'Barbell Bench Press');
      expect(best!.weight.kilograms, 100);
    });
  });

  group('frequency', () {
    test('counts sessions a movement appears in, not sets', () {
      final rows = TrainingStats.byFrequency(<Session>[
        sessionOn(
          DateTime(2026, 8, 3),
          sets: <SessionSet>[working(100, 5), working(100, 5)],
        ),
        sessionOn(DateTime(2026, 8, 5), sets: <SessionSet>[working(100, 5)]),
        sessionOn(
          DateTime(2026, 8, 6),
          exercise: 'Squat',
          sets: <SessionSet>[working(100, 5)],
        ),
      ]);
      expect(rows.first.name, 'Barbell Bench Press');
      expect(rows.first.sessions, 2);
      expect(rows[1].sessions, 1);
    });
  });

  group('sessions per week', () {
    test('a first week in progress is still a whole week', () {
      // Without the clamp, two sessions on day one reads as 14 a week.
      final stats = TrainingStats.from(
        <Session>[
          sessionOn(DateTime(2026, 8, 3), sets: <SessionSet>[working(100, 5)]),
          sessionOn(
            DateTime(2026, 8, 3, 18),
            exercise: 'Squat',
            sets: <SessionSet>[working(100, 5)],
          ),
        ],
        now: DateTime(2026, 8, 4),
      );
      expect(stats.sessionsPerWeek, 2);
    });
  });
}
