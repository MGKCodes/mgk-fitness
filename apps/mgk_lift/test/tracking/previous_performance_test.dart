import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/tracking/domain/previous_performance.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';

SessionSet _set(
  int number,
  double weightKg,
  int reps, {
  SetType type = SetType.working,
}) => SessionSet(
  id: 's$number-$weightKg-$reps-${type.stored}',
  setNumber: number,
  reps: reps,
  weightKg: weightKg,
  isCompleted: true,
  setType: type,
);

Session _session(
  String id,
  DateTime day, {
  String exercise = 'Barbell Bench Press',
  List<SessionSet> sets = const <SessionSet>[],
  bool inProgress = false,
}) => Session(
  id: id,
  name: 'Session',
  startedAt: day,
  endedAt: inProgress ? null : day.add(const Duration(hours: 1)),
  exercises: <SessionExercise>[
    SessionExercise(id: 'e-$id', name: exercise, orderIndex: 0, sets: sets),
  ],
);

void main() {
  final monday = DateTime(2026, 8, 10);
  final thursday = DateTime(2026, 8, 13);

  test('nothing to show when the movement has never been trained', () {
    expect(PreviousPerformance.of(<Session>[], 'Barbell Bench Press'), isNull);
  });

  test('the most recent finished session wins, not the first in the list', () {
    // Deliberately out of order: the log is not promised sorted, and reading
    // whichever came first in the list is the bug this pins.
    final log = <Session>[
      _session('old', monday, sets: <SessionSet>[_set(1, 60, 10)]),
      _session('new', thursday, sets: <SessionSet>[_set(1, 65, 8)]),
    ];

    final previous = PreviousPerformance.of(log, 'Barbell Bench Press')!;
    expect(previous.on, thursday);
    expect(previous.sets.single.weightKg, 65);
  });

  test('the session in progress is not its own history', () {
    // Without the exclusion the first set logged today becomes "last time",
    // and the line reports what happened ninety seconds ago.
    final log = <Session>[
      _session('done', monday, sets: <SessionSet>[_set(1, 60, 10)]),
      _session(
        'today',
        thursday,
        sets: <SessionSet>[_set(1, 62.5, 9)],
        inProgress: true,
      ),
    ];

    final previous = PreviousPerformance.of(
      log,
      'Barbell Bench Press',
      excludeSessionId: 'today',
    )!;
    expect(previous.on, monday);
    expect(previous.sets.single.weightKg, 60);
  });

  test('matching is case-insensitive, because a typed name is first class', () {
    final log = <Session>[
      _session(
        'a',
        monday,
        exercise: 'barbell bench press',
        sets: <SessionSet>[_set(1, 60, 10)],
      ),
    ];
    expect(PreviousPerformance.of(log, 'Barbell Bench Press'), isNotNull);
  });

  test('warm-ups are excluded, so it never reports an empty bar', () {
    final log = <Session>[
      _session(
        'a',
        monday,
        sets: <SessionSet>[
          _set(1, 20, 12, type: SetType.warmup),
          _set(2, 60, 10),
        ],
      ),
    ];

    final previous = PreviousPerformance.of(log, 'Barbell Bench Press')!;
    expect(previous.sets.length, 1);
    expect(previous.sets.single.weightKg, 60);
  });

  test('drop sets and failure sets are kept — they were the work', () {
    final log = <Session>[
      _session(
        'a',
        monday,
        sets: <SessionSet>[
          _set(1, 60, 10),
          _set(2, 45, 8, type: SetType.dropSet),
          _set(3, 60, 6, type: SetType.failure),
        ],
      ),
    ];
    expect(PreviousPerformance.of(log, 'Barbell Bench Press')!.sets.length, 3);
  });

  test(
    'a session where the movement was added but never worked falls through',
    () {
      // The useful answer is the session before it, not "you did nothing".
      final log = <Session>[
        _session('empty', thursday),
        _session('real', monday, sets: <SessionSet>[_set(1, 60, 10)]),
      ];

      final previous = PreviousPerformance.of(log, 'Barbell Bench Press')!;
      expect(previous.on, monday);
    },
  );

  test('best is the heaviest set, not the last one', () {
    final log = <Session>[
      _session(
        'a',
        monday,
        sets: <SessionSet>[_set(1, 60, 10), _set(2, 70, 3), _set(3, 55, 12)],
      ),
    ];
    expect(
      PreviousPerformance.of(log, 'Barbell Bench Press')!.best.weightKg,
      70,
    );
  });
}
