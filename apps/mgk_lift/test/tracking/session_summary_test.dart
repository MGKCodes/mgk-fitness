import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';
import 'package:mgk_lift/src/features/tracking/domain/session_summary.dart';

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
    List<Session> log({double bench = 90, int reps = 5}) => <Session>[
      finished(
        'old',
        day.subtract(const Duration(days: 7)),
        exercises: <SessionExercise>[
          movement(
            'Barbell Bench Press',
            sets: <SessionSet>[working(80, 8), working(bench, reps)],
          ),
        ],
      ),
    ];

    test('a movement that goes past its previous best is one', () {
      // 90 × 5 estimates at 105 kg; 100 × 5 at 116.67.
      final summary = SessionSummary.of(
        finished(
          'today',
          day,
          exercises: <SessionExercise>[
            movement(
              'Barbell Bench Press',
              sets: <SessionSet>[working(100, 5)],
            ),
          ],
        ),
        log: log(),
      );

      expect(summary.personalBests, hasLength(1));
      final best = summary.personalBests.single;
      expect(best.movement, 'Barbell Bench Press');
      expect(best.weight.kilograms, 100);
      expect(best.reps, 5);
      expect(best.estimate.kilograms, closeTo(116.667, 0.001));
      expect(best.previous.kilograms, closeTo(105, 0.001));
      expect(best.previousOn, day.subtract(const Duration(days: 7)));
    });

    test('matching a previous best is not setting one', () {
      // A session that repeats last week's top set to the kilogram has not
      // moved, and telling somebody it has is the app flattering them.
      final summary = SessionSummary.of(
        finished(
          'today',
          day,
          exercises: <SessionExercise>[
            movement('Barbell Bench Press', sets: <SessionSet>[working(90, 5)]),
          ],
        ),
        log: log(),
      );

      expect(summary.personalBests, isEmpty);
      // ...and the screen can still tell the difference between "nothing beat
      // it" and "nothing could be measured".
      expect(summary.hasEstimate, isTrue);
    });

    test('a movement with no history is not a personal best', () {
      // Otherwise a first session is nothing but bests — every movement in it,
      // by definition — and the word stops meaning anything.
      final summary = SessionSummary.of(
        finished(
          'today',
          day,
          exercises: <SessionExercise>[
            movement(
              'Barbell Bench Press',
              sets: <SessionSet>[working(100, 5)],
            ),
          ],
        ),
      );

      expect(summary.personalBests, isEmpty);
      expect(summary.hasEstimate, isTrue);
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
      final summary = SessionSummary.of(
        finished(
          'today',
          day,
          exercises: <SessionExercise>[
            movement(
              'Barbell Bench Press',
              sets: <SessionSet>[warmup(120, 5), working(80, 5)],
            ),
          ],
        ),
        log: log(),
      );

      expect(summary.personalBests, isEmpty);
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
      expect(summary.personalBests.single.weight.kilograms, 102.5);
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
  });

  group('no estimate is a real state', () {
    test('a set above twelve reps produces neither an estimate nor a best', () {
      // Epley is a straight line fitted to low-rep work; above twelve it is an
      // invention. `estimateOneRepMax` returns null there, and this session is
      // nothing but such sets — so there is no comparison to report, and the
      // screen must not read it as having gone backwards.
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
                sets: <SessionSet>[working(10, 12)],
              ),
            ],
          ),
        ],
      );

      expect(summary.hasEstimate, isFalse);
      expect(summary.personalBests, isEmpty);
      // The work still counts. Only the estimate is unavailable.
      expect(summary.volume.kilograms, 420);
      expect(summary.workingSets, 2);
    });

    test('a huge weight above the cap still sets nothing', () {
      // The dangerous shape of the same bug: 200 kg for thirteen would estimate
      // at 286 and beat everything, if the cap were not enforced.
      final summary = SessionSummary.of(
        finished(
          'today',
          day,
          exercises: <SessionExercise>[
            movement(
              'Barbell Bench Press',
              sets: <SessionSet>[working(200, 13)],
            ),
          ],
        ),
        log: <Session>[
          finished(
            'old',
            day.subtract(const Duration(days: 7)),
            exercises: <SessionExercise>[
              movement(
                'Barbell Bench Press',
                sets: <SessionSet>[working(90, 5)],
              ),
            ],
          ),
        ],
      );

      expect(summary.hasEstimate, isFalse);
      expect(summary.personalBests, isEmpty);
    });

    test('one estimable set among many is enough to have looked', () {
      final summary = SessionSummary.of(
        finished(
          'today',
          day,
          exercises: <SessionExercise>[
            movement(
              'Dumbbell Bicep Curl',
              sets: <SessionSet>[working(14, 15)],
            ),
            movement(
              'Barbell Bench Press',
              order: 1,
              sets: <SessionSet>[working(80, 5)],
            ),
          ],
        ),
        log: <Session>[
          finished(
            'old',
            day.subtract(const Duration(days: 7)),
            exercises: <SessionExercise>[
              movement(
                'Barbell Bench Press',
                sets: <SessionSet>[working(90, 5)],
              ),
            ],
          ),
        ],
      );

      expect(summary.hasEstimate, isTrue);
      expect(summary.personalBests, isEmpty);
    });
  });
}
