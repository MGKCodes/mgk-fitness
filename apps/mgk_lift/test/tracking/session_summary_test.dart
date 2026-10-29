import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/stats/domain/training_stats.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';
import 'package:mgk_lift/src/features/tracking/domain/session_summary.dart';
import 'package:mgk_units/mgk_units.dart';

/// A finished session. Finished matters: `TrainingStats` reads finished
/// sessions only, so an open fixture would report no bests however good it was.
Session finished(
  String id,
  DateTime day, {
  String name = 'Push',
  Duration ran = const Duration(minutes: 62),
  List<SessionExercise> exercises = const <SessionExercise>[],
}) => Session(
  id: id,
  name: name,
  startedAt: day,
  endedAt: day.add(ran),
  exercises: exercises,
);

SessionExercise movement(
  String name, {
  String? id,
  int order = 0,
  List<SessionSet> sets = const <SessionSet>[],
}) =>
    SessionExercise(id: id ?? name, name: name, orderIndex: order, sets: sets);

var _setId = 0;

SessionSet working(double kg, int reps) => SessionSet(
  id: 'w${_setId++}',
  setNumber: 1,
  weightKg: kg,
  reps: reps,
  isCompleted: true,
);

SessionSet warmup(double kg, int reps) => SessionSet(
  id: 'wu${_setId++}',
  setNumber: 1,
  weightKg: kg,
  reps: reps,
  isCompleted: true,
  setType: SetType.warmup,
);

SessionSet planned(double kg, int reps) =>
    SessionSet(id: 'p${_setId++}', setNumber: 1, weightKg: kg, reps: reps);

void main() {
  final day = DateTime(2026, 8, 6, 18);

  group('the totals', () {
    test('are the four the running header carried', () {
      // The numbers a lifter watched climb have to be the numbers they land
      // on. A different four appearing at the end reads as the app having
      // changed its mind about what happened.
      final session = finished(
        's',
        day,
        ran: const Duration(minutes: 47, seconds: 30),
        exercises: <SessionExercise>[
          movement(
            'Barbell Bench Press',
            sets: <SessionSet>[
              warmup(60, 10),
              working(80, 8),
              working(85, 6),
              planned(85, 6),
            ],
          ),
          movement('Cable Fly', order: 1),
        ],
      );

      final summary = SessionSummary.of(session);

      expect(summary.duration, const Duration(minutes: 47, seconds: 30));
      // 80×8 + 85×6. The warm-up and the set that was never ticked are both
      // out, which is Session.workingSets rather than a second opinion.
      expect(summary.volume.kilograms, 1150);
      expect(summary.workingSets, 2);
      // Cable Fly was added and never worked. It was still in the session.
      expect(summary.movements, 2);
      expect(summary.volume.kilograms, session.volumeKg);
      expect(summary.workingSets, session.completedSets);
    });

    test('the duration is the stamped one, not the clock', () {
      // A summary must not grow while it is being read.
      final summary = SessionSummary.of(
        finished('s', day, ran: const Duration(hours: 1, minutes: 5)),
      );
      expect(summary.duration, const Duration(hours: 1, minutes: 5));
    });
  });

  group('personal bests', () {
    /// Last week's bench: 80 × 8, then 90 × 5. Its top set is 90 × 5.
    List<Session> log() => <Session>[
      finished(
        'old',
        day.subtract(const Duration(days: 7)),
        exercises: <SessionExercise>[
          movement(
            'Barbell Bench Press',
            sets: <SessionSet>[working(80, 8), working(90, 5)],
          ),
        ],
      ),
    ];

    SessionSummary bench(List<SessionSet> sets, {List<Session>? before}) =>
        SessionSummary.of(
          finished(
            'today',
            day,
            exercises: <SessionExercise>[
              movement('Barbell Bench Press', sets: sets),
            ],
          ),
          log: before ?? log(),
        );

    test('a heavier weight than ever before is one', () {
      final summary = bench(<SessionSet>[working(92.5, 3)]);

      expect(summary.personalBests, hasLength(1));
      final best = summary.personalBests.single;
      expect(best.movement, 'Barbell Bench Press');
      expect(best.set.weight.kilograms, 92.5);
      expect(best.set.reps, 3);
      expect(best.isHeavier, isTrue);
      expect(best.beat.weight.kilograms, 90);
      expect(best.beat.reps, 5);
      expect(best.beat.on, day.subtract(const Duration(days: 7)));
    });

    test('as heavy for more reps is one', () {
      final best = bench(<SessionSet>[working(90, 6)]).personalBests.single;
      expect(best.isHeavier, isFalse);
      expect(best.set.reps, 6);
      expect(best.beat.reps, 5);
    });

    test('a bigger estimate at a lighter weight is not one (#3)', () {
      // 85 × 10 estimates at 113 kg against 90 × 5's 105, and 2.0.0 called it
      // a best. Nothing heavier went on the bar, so it is not.
      expect(bench(<SessionSet>[working(85, 10)]).personalBests, isEmpty);
    });

    test('the heaviest set of the day is the one compared', () {
      // A back-off set for more reps does not hide the top set ahead of it.
      final best = bench(<SessionSet>[
        working(95, 2),
        working(85, 10),
      ]).personalBests.single;
      expect(best.set.weight.kilograms, 95);
    });

    test('matching a previous best is not setting one', () {
      // A session that repeats last week's top set to the kilogram has not
      // moved, and telling somebody it has is the app flattering them.
      expect(bench(<SessionSet>[working(90, 5)]).personalBests, isEmpty);
    });

    test('the same weight typed in pounds twice is the same weight', () {
      // 225 lb is stored as its exact kilograms, and arrives by a different
      // sum each time. One more rep at it is more reps at the same weight —
      // not a heavier weight by a rounding error.
      final best = bench(
        <SessionSet>[working(Mass.pounds(225).kilograms, 6)],
        before: <Session>[
          finished(
            'old',
            day.subtract(const Duration(days: 7)),
            exercises: <SessionExercise>[
              movement(
                'Barbell Bench Press',
                // The same 225 lb by another sum, a hair apart.
                sets: <SessionSet>[working(225 / 2.20462262185, 5)],
              ),
            ],
          ),
        ],
      ).personalBests.single;
      expect(best.isHeavier, isFalse);
    });

    test('a movement with no history is not a personal best', () {
      // Otherwise a first session is nothing but bests — every movement in it,
      // by definition — and the word stops meaning anything.
      expect(
        bench(<SessionSet>[
          working(100, 5),
        ], before: const <Session>[]).personalBests,
        isEmpty,
      );
    });

    test('the session is not compared against itself', () {
      // The log the shell holds is refreshed the moment a session finishes, so
      // it can already contain this one. Without the filter, every session
      // would tie with itself and nothing could ever be a best.
      final today = finished(
        'today',
        day,
        exercises: <SessionExercise>[
          movement('Barbell Bench Press', sets: <SessionSet>[working(100, 5)]),
        ],
      );

      final summary = SessionSummary.of(today, log: <Session>[...log(), today]);

      expect(summary.personalBests, hasLength(1));
    });

    test('a heavy warm-up does not become a personal best', () {
      // Warm-ups are out of every total, and a best is a total. A single at
      // 120 marked as a warm-up is somebody correcting their log, not a
      // record.
      expect(
        bench(<SessionSet>[warmup(120, 5), working(80, 5)]).personalBests,
        isEmpty,
      );
    });

    test('a movement done twice in a session is reported once', () {
      // Coming back to the bench at the end is one movement that had a good
      // day, not two claims on the same record.
      final summary = SessionSummary.of(
        finished(
          'today',
          day,
          exercises: <SessionExercise>[
            movement(
              'Barbell Bench Press',
              id: 'first',
              sets: <SessionSet>[working(100, 5)],
            ),
            movement(
              'Barbell Bench Press',
              id: 'second',
              order: 1,
              sets: <SessionSet>[working(102.5, 5)],
            ),
          ],
        ),
        log: log(),
      );

      expect(summary.personalBests, hasLength(1));
      // The best of the two visits, not the first of them.
      expect(summary.personalBests.single.set.weight.kilograms, 102.5);
    });

    test('the bests are in the order they were trained', () {
      final summary = SessionSummary.of(
        finished(
          'today',
          day,
          exercises: <SessionExercise>[
            movement(
              'Barbell Bench Press',
              sets: <SessionSet>[working(100, 5)],
            ),
            movement(
              'Barbell Back Squat',
              order: 1,
              sets: <SessionSet>[working(140, 5)],
            ),
          ],
        ),
        log: <Session>[
          ...log(),
          finished(
            'old-legs',
            day.subtract(const Duration(days: 5)),
            exercises: <SessionExercise>[
              movement(
                'Barbell Back Squat',
                sets: <SessionSet>[working(120, 5)],
              ),
            ],
          ),
        ],
      );

      expect(summary.personalBests.map((b) => b.movement), <String>[
        'Barbell Bench Press',
        'Barbell Back Squat',
      ]);
    });

    test('high reps count: a best is a weight, not an estimate', () {
      // 2.0.0 could not see a best above twelve reps, because Epley stops
      // there. A heavier dumbbell is heavier at fifteen.
      final summary = SessionSummary.of(
        finished(
          'today',
          day,
          exercises: <SessionExercise>[
            movement(
              'Dumbbell Bicep Curl',
              sets: <SessionSet>[working(14, 15), working(14, 15)],
            ),
          ],
        ),
        log: <Session>[
          finished(
            'old',
            day.subtract(const Duration(days: 4)),
            exercises: <SessionExercise>[
              movement(
                'Dumbbell Bicep Curl',
                sets: <SessionSet>[working(12, 15)],
              ),
            ],
          ),
        ],
      );

      expect(summary.personalBests.single.set.weight.kilograms, 14);
      expect(summary.volume.kilograms, 420);
    });

    test('bodyweight work has no weight to have beaten', () {
      final summary = SessionSummary.of(
        finished(
          'today',
          day,
          exercises: <SessionExercise>[
            movement('Pull Up', sets: <SessionSet>[working(0, 12)]),
          ],
        ),
        log: <Session>[
          finished(
            'old',
            day.subtract(const Duration(days: 4)),
            exercises: <SessionExercise>[
              movement('Pull Up', sets: <SessionSet>[working(0, 8)]),
            ],
          ),
        ],
      );

      expect(summary.personalBests, isEmpty);
    });
  });

  group('what a best says', () {
    TopSet top(Mass weight, int reps) =>
        TopSet(weight: weight, reps: reps, on: day);

    test('heavier says the weight it went past', () {
      expect(
        bestDetail(
          top(const Mass.kilograms(92.5), 3),
          top(const Mass.kilograms(90), 5),
          MassUnit.kilograms,
        ),
        '92.5 kg × 3. Your heaviest yet, past 90 kg.',
      );
    });

    test('more reps says the count it went past', () {
      expect(
        bestDetail(
          top(const Mass.kilograms(90), 6),
          top(const Mass.kilograms(90), 5),
          MassUnit.kilograms,
        ),
        '90 kg × 6. Your most reps at that weight, up from 5.',
      );
    });

    test('in the unit the lifter works in', () {
      expect(
        bestDetail(
          top(Mass.pounds(225), 3),
          top(Mass.pounds(220), 5),
          MassUnit.pounds,
        ),
        '225 lb × 3. Your heaviest yet, past 220 lb.',
      );
    });
  });
}
