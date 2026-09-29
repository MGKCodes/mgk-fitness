import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/core/database/app_database.dart';
import 'package:mgk_lift/src/features/stats/data/drift_session_history.dart';
import 'package:mgk_lift/src/features/sync/data/sync_queue.dart';
import 'package:mgk_lift/src/features/tracking/data/drift_session_recorder.dart';
import 'package:mgk_lift/src/features/tracking/data/drift_workout_library.dart';
import 'package:mgk_lift/src/features/tracking/data/workout_templates.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';
import 'package:mgk_lift/src/features/tracking/domain/workout_library.dart';
import 'package:mgk_lift/src/features/tracking/domain/workout_template.dart';

/// Names as movements with the default count — what most of these need.
List<TemplateMovement> moves(List<String> names) => <TemplateMovement>[
  for (final n in names) TemplateMovement(n),
];

void main() {
  late AppDatabase db;
  late DriftWorkoutLibrary library;
  late DriftSessionRecorder recorder;
  var counter = 0;

  setUp(() {
    counter = 0;
    db = AppDatabase.memory();
    // Shared counter, because the two write into the same three tables and a
    // collision between a template's movement and a session's would be exactly
    // the kind of thing this suite exists to catch.
    String nextId() => 'id-${++counter}';
    library = DriftWorkoutLibrary(db, idFactory: nextId);
    recorder = DriftSessionRecorder(db, idFactory: nextId);
  });

  tearDown(() async => db.close());

  /// Starts a session from [saved] the way Track does.
  Future<Session> startFrom(
    SavedWorkout saved, {
    List<Session> log = const <Session>[],
  }) async {
    await recorder.start();
    return recorder.fillFromLibrary(
      workoutId: saved.id,
      name: saved.name,
      movements: seedWorkout(saved.movements, log),
      snapshot: TemplateMovement.encode(saved.movements),
    );
  }

  group('the write path', () {
    test('saving writes a template row and its movements', () async {
      final saved = await library.save(
        name: 'Push',
        movements: moves(<String>['Barbell Bench Press', 'Cable Fly']),
      );

      expect(saved.name, 'Push');
      expect(saved.movementNames, <String>['Barbell Bench Press', 'Cable Fly']);

      final row = await (db.select(
        db.workouts,
      )..where((w) => w.id.equals(saved.id))).getSingle();
      expect(row.isTemplate, isTrue);
      // Never ended, because it never happened.
      expect(row.endedAt, isNull);
    });

    test(
      'movements keep the order they were given, with their counts',
      () async {
        await library.save(
          name: 'Legs',
          movements: const <TemplateMovement>[
            TemplateMovement('Barbell Back Squat', sets: 5, repTarget: 5),
            TemplateMovement('Leg Press', repTarget: 10),
            TemplateMovement('Calf Raise', sets: 4),
          ],
        );

        final read = (await library.all()).single;
        expect(read.movements, const <TemplateMovement>[
          TemplateMovement('Barbell Back Squat', sets: 5, repTarget: 5),
          TemplateMovement('Leg Press', repTarget: 10),
          TemplateMovement('Calf Raise', sets: 4),
        ]);
        expect(read.setCount, 12);
      },
    );

    test(
      'the set count is stored as set rows holding the rep target',
      () async {
        // Liftio's own layout — three empty sets per movement — which is how
        // the templates already on the server read back with their counts.
        await library.save(
          name: 'Push',
          movements: const <TemplateMovement>[
            TemplateMovement('Bench', sets: 3, repTarget: 8),
          ],
        );
        final sets = await db.select(db.exerciseSets).get();
        expect(sets, hasLength(3));
        expect(sets.every((s) => s.reps == 8 && s.weightKg == 0), isTrue);
      },
    );

    test('a movement stored with no sets reads as the default count', () async {
      // What this app wrote before counts existed.
      final saved = await library.save(
        name: 'Old',
        movements: moves(<String>['A']),
      );
      await db.delete(db.exerciseSets).go();
      expect(
        (await library.byId(saved.id))!.movements.single.sets,
        TemplateMovement.defaultSets,
      );
    });

    test('the library is newest first', () async {
      await library.save(name: 'First', movements: moves(<String>['A']));
      await library.save(name: 'Second', movements: moves(<String>['B']));
      await library.save(name: 'Third', movements: moves(<String>['C']));

      expect((await library.all()).map((w) => w.name), <String>[
        'Third',
        'Second',
        'First',
      ]);
    });

    test('a name past the limit is cut to it', () async {
      final saved = await library.save(
        name: 'x' * 80,
        movements: moves(<String>['A']),
      );
      expect(saved.name, hasLength(SessionLimits.nameLength));
    });
  });

  group('editing', () {
    test('keeps the id and the place, and replaces the movements', () async {
      final first = await library.save(
        name: 'A',
        movements: moves(<String>['X']),
      );
      await library.save(name: 'B', movements: moves(<String>['Y']));

      await library.update(
        first.copyWith(
          name: 'A, renamed',
          movements: const <TemplateMovement>[
            TemplateMovement('Z', sets: 2, repTarget: 12),
          ],
        ),
      );

      final all = await library.all();
      expect(all.map((w) => w.name), <String>['B', 'A, renamed']);
      final edited = (await library.byId(first.id))!;
      expect(edited.movements, const <TemplateMovement>[
        TemplateMovement('Z', sets: 2, repTarget: 12),
      ]);
    });
  });

  group('deleting', () {
    test('leaves a tombstone, so the delete can reach other devices', () async {
      final saved = await library.save(
        name: 'Push',
        movements: moves(<String>['Bench', 'Fly']),
      );
      await library.remove(saved.id);

      expect(await library.all(), isEmpty);
      expect(await library.byId(saved.id), isNull);
      // Soft: a row simply removed here would come back down on the next pull.
      final row = await (db.select(
        db.workouts,
      )..where((w) => w.id.equals(saved.id))).getSingle();
      expect(row.deletedAt, isNotNull);
    });

    test('undo brings it back as it was', () async {
      final saved = await library.save(
        name: 'Push',
        movements: moves(<String>['Bench', 'Fly']),
      );
      await library.remove(saved.id);
      await library.restore(saved.id);

      final back = (await library.all()).single;
      expect(back.id, saved.id);
      expect(back.movementNames, <String>['Bench', 'Fly']);
    });
  });

  group('a template is not a session', () {
    test('a saved workout is never offered as the session in progress', () {
      return expectLater(
        library
            .save(name: 'Push', movements: moves(<String>['Bench']))
            .then((_) => recorder.current()),
        completion(isNull),
      );
    });

    test('a saved workout does not block starting a session', () async {
      await library.save(name: 'Push', movements: moves(<String>['Bench']));
      final session = await recorder.start();
      expect(session.isInProgress, isTrue);
      expect(session.exercises, isEmpty);
    });

    test('a saved workout never reaches the training log', () async {
      await library.save(name: 'Push', movements: moves(<String>['Bench']));
      expect(await DriftSessionHistory(db).all(), isEmpty);
    });

    test('a saved workout is queued to back up, as a template', () async {
      // It was kept off the queue until the upload could send one with no
      // date; it can now, and a library that stays on one phone is lost with
      // it.
      final saved = await library.save(
        name: 'Push',
        movements: moves(<String>['Bench']),
      );
      final queued = await SyncQueue(db).dirtyWorkouts();
      expect(queued.single.id, saved.id);
      expect(queued.single.isTemplate, isTrue);
    });

    test('a session in progress is not queued, whatever else is', () async {
      await library.save(name: 'Push', movements: moves(<String>['Bench']));
      final open = await recorder.start();
      final queued = await SyncQueue(db).dirtyWorkouts();
      expect(queued.map((w) => w.id), isNot(contains(open.id)));
    });

    test('a finished session is queued beside the saved workout', () async {
      await library.save(name: 'Push', movements: moves(<String>['Bench']));
      await recorder.start();
      await recorder.finish();
      final pending = await SyncQueue(db).pending();
      expect(pending.workouts, 1);
      expect(pending.savedWorkouts, 1);
    });
  });

  group('adding a premade', () {
    test('copies its movements and records where it came from', () async {
      final push = workoutTemplates.firstWhere((t) => t.id == 'push');
      final saved = await library.save(
        name: push.name,
        movements: moves(push.exercises),
        fromPremade: push.id,
      );

      expect(saved.movementNames, push.exercises);
      expect((await library.all()).single.premadeId, 'push');
      // Each movement arrives with the default count.
      expect(
        (await library.all()).single.movements.every(
          (m) => m.sets == TemplateMovement.defaultSets,
        ),
        isTrue,
      );
    });

    test('adding a whole split adds every session in it', () async {
      final split = workoutSplits.firstWhere((s) => s.id == 'ppl');
      final byId = <String, WorkoutTemplate>{
        for (final t in workoutTemplates) t.id: t,
      };
      final names = <String>[];
      for (final id in split.templateIds) {
        final template = byId[id]!;
        final name = uniqueWorkoutName(template.name, names);
        await library.save(
          name: name,
          movements: moves(template.exercises),
          fromPremade: template.id,
        );
        names.add(name);
      }
      final saved = await library.all();
      expect(saved, hasLength(split.templateIds.length));
      expect(saved.map((w) => w.premadeId).toSet(), split.templateIds.toSet());
    });
  });

  group('starting a session from a saved workout', () {
    test('lays out every movement with its sets, in order', () async {
      final saved = await library.save(
        name: 'Push',
        movements: const <TemplateMovement>[
          TemplateMovement('Barbell Bench Press', sets: 4, repTarget: 5),
          TemplateMovement('Cable Fly', sets: 2),
        ],
      );

      final session = await startFrom(saved);

      // It used to add the names and nothing else: six empty cards for a
      // six-movement workout.
      expect(session.name, 'Push');
      expect(session.exercises.map((e) => e.name), <String>[
        'Barbell Bench Press',
        'Cable Fly',
      ]);
      expect(session.exercises.map((e) => e.sets.length), <int>[4, 2]);
      expect(session.exercises.first.sets.every((s) => s.reps == 5), isTrue);
      expect(
        session.exercises.expand((e) => e.sets).any((s) => s.isCompleted),
        isFalse,
        reason: 'laid out, never logged',
      );
    });

    test('weights and missing reps come from last time', () async {
      final lastWeek = Session(
        id: 'last',
        name: 'Push',
        startedAt: DateTime(2026, 9, 20),
        endedAt: DateTime(2026, 9, 20, 1),
        exercises: const <SessionExercise>[
          SessionExercise(
            id: 'e',
            name: 'Cable Fly',
            orderIndex: 0,
            sets: <SessionSet>[
              SessionSet(
                id: 'a',
                setNumber: 1,
                reps: 12,
                weightKg: 20,
                isCompleted: true,
              ),
              SessionSet(
                id: 'b',
                setNumber: 2,
                reps: 10,
                weightKg: 22.5,
                isCompleted: true,
              ),
            ],
          ),
        ],
      );
      final saved = await library.save(
        name: 'Push',
        movements: const <TemplateMovement>[
          TemplateMovement('Cable Fly', sets: 3),
        ],
      );

      final session = await startFrom(saved, log: <Session>[lastWeek]);

      final sets = session.exercises.single.sets;
      expect(sets.map((s) => s.weightKg), <double>[20, 22.5, 22.5]);
      expect(sets.map((s) => s.reps), <int>[12, 10, 10]);
    });

    test('records the workout and a snapshot of it on the session', () async {
      final saved = await library.save(
        name: 'Push',
        movements: moves(<String>['A', 'B']),
      );
      final started = await startFrom(saved);

      expect(started.templateId, saved.id);
      expect(
        TemplateMovement.decode(started.templateSnapshot),
        saved.movements,
      );

      final row = await (db.select(
        db.workouts,
      )..where((w) => w.id.equals(started.id))).getSingle();
      expect(row.isTemplate, isFalse);
      expect(row.premadeId, isNull);
    });

    test('the saved workout survives the session it started', () async {
      final saved = await library.save(
        name: 'Push',
        movements: moves(<String>['A', 'B']),
      );
      final started = await startFrom(saved);
      // One set of A ticked; the rest never started.
      await recorder.updateSet(
        started.exercises.first.sets.first.id,
        reps: 5,
        isCompleted: true,
      );
      final finished = await recorder.finish();

      // The session keeps only what happened...
      expect(finished.exercises.map((e) => e.name), <String>['A']);
      expect(finished.exercises.single.sets, hasLength(1));
      // ...and the workout it came from is untouched by that.
      expect((await library.byId(saved.id))!.movements, saved.movements);
      expect(await DriftSessionHistory(db).all(), hasLength(1));
    });
  });

  group('the workout learns from the session', () {
    List<TemplateMovement> after(List<TemplateMovement> before, Session s) =>
        TemplateUpdate.between(before, s).after;

    SessionExercise ex(
      String name,
      int rows, {
      int warmups = 0,
      int ticked = 0,
    }) => SessionExercise(
      id: name,
      name: name,
      orderIndex: 0,
      sets: <SessionSet>[
        for (var i = 0; i < warmups; i++)
          SessionSet(
            id: '$name-w$i',
            setNumber: i + 1,
            setType: SetType.warmup,
          ),
        for (var i = 0; i < rows; i++)
          SessionSet(
            id: '$name-$i',
            setNumber: warmups + i + 1,
            reps: 5,
            isCompleted: i < ticked,
          ),
      ],
    );

    Session session(List<SessionExercise> e) => Session(
      id: 's',
      name: 'Push',
      startedAt: DateTime(2026, 9, 29),
      exercises: e,
    );

    const before = <TemplateMovement>[
      TemplateMovement('Bench', sets: 3, repTarget: 5),
      TemplateMovement('Fly', sets: 3),
      TemplateMovement('Dips', sets: 3),
    ];

    test('a movement removed is removed', () {
      final u = TemplateUpdate.between(
        before,
        session(<SessionExercise>[ex('Bench', 3), ex('Dips', 3)]),
      );
      expect(u.after.map((m) => m.name), <String>['Bench', 'Dips']);
      expect(u.removed, <String>['Fly']);
      expect(u.describe(), 'removed Fly');
    });

    test('a movement added and done is added, where it was', () {
      final u = TemplateUpdate.between(
        before,
        session(<SessionExercise>[
          ex('Bench', 3),
          ex('Pushdown', 2, ticked: 1),
          ex('Fly', 3),
          ex('Dips', 3),
        ]),
      );
      expect(u.after.map((m) => m.name), <String>[
        'Bench',
        'Pushdown',
        'Fly',
        'Dips',
      ]);
      expect(u.after[1].sets, 2);
      expect(u.added, <String>['Pushdown']);
    });

    test('a movement added and never done is not added', () {
      // Finish drops it from the session and says so; the workout agrees.
      final u = TemplateUpdate.between(
        before,
        session(<SessionExercise>[
          ex('Bench', 3),
          ex('Pushdown', 2),
          ex('Fly', 3),
          ex('Dips', 3),
        ]),
      );
      expect(u.isEmpty, isTrue);
    });

    test('a swap is the old movement out and the new one in its place', () {
      final u = TemplateUpdate.between(
        before,
        session(<SessionExercise>[
          ex('Bench', 3),
          ex('Pec Deck', 3, ticked: 2),
          ex('Dips', 3),
        ]),
      );
      expect(u.after.map((m) => m.name), <String>['Bench', 'Pec Deck', 'Dips']);
      expect(u.describe(), 'removed Fly, added Pec Deck');
    });

    test('a new order is kept', () {
      final u = TemplateUpdate.between(
        before,
        session(<SessionExercise>[ex('Dips', 3), ex('Bench', 3), ex('Fly', 3)]),
      );
      expect(u.reordered, isTrue);
      expect(u.after.map((m) => m.name), <String>['Dips', 'Bench', 'Fly']);
    });

    test('rows added or removed change the count; warm-ups do not', () {
      final u = TemplateUpdate.between(
        before,
        session(<SessionExercise>[
          ex('Bench', 4, warmups: 2),
          ex('Fly', 2),
          ex('Dips', 3),
        ]),
      );
      expect(u.after.map((m) => m.sets), <int>[4, 2, 3]);
      expect(u.resized, <String>['Bench', 'Fly']);
    });

    test('a movement skipped, or sets left unticked, change nothing', () {
      // Fly kept but never started; Dips with its rows all unticked.
      final u = TemplateUpdate.between(
        before,
        session(<SessionExercise>[
          ex('Bench', 3, ticked: 3),
          ex('Fly', 0),
          ex('Dips', 3),
        ]),
      );
      expect(u.isEmpty, isTrue);
      expect(u.after, before);
    });

    test('rep targets survive; reps and weights never change the workout', () {
      expect(
        after(
          before,
          session(<SessionExercise>[
            ex('Bench', 3),
            ex('Fly', 3),
            ex('Dips', 3),
          ]),
        ).first.repTarget,
        5,
      );
    });

    test('a movement twice is two movements', () {
      const twice = <TemplateMovement>[
        TemplateMovement('Bench'),
        TemplateMovement('Fly'),
        TemplateMovement('Bench', sets: 2),
      ];
      final u = TemplateUpdate.between(
        twice,
        session(<SessionExercise>[
          ex('Bench', 3),
          ex('Fly', 3),
          ex('Bench', 2),
        ]),
      );
      expect(u.isEmpty, isTrue);
    });
  });

  group('saving a session as a workout', () {
    test('keeps each movement once, with the sets worked', () {
      final s = Session(
        id: 's',
        name: 'Push',
        startedAt: DateTime(2026, 9, 29),
        exercises: const <SessionExercise>[
          SessionExercise(
            id: 'a',
            name: 'Bench',
            orderIndex: 0,
            sets: <SessionSet>[
              SessionSet(id: 'w', setNumber: 1, setType: SetType.warmup),
              SessionSet(id: '1', setNumber: 2),
              SessionSet(id: '2', setNumber: 3),
            ],
          ),
          SessionExercise(id: 'b', name: 'Fly', orderIndex: 1),
          SessionExercise(
            id: 'c',
            name: 'bench',
            orderIndex: 2,
            sets: <SessionSet>[SessionSet(id: '3', setNumber: 1)],
          ),
        ],
      );
      expect(movementsOf(s), const <TemplateMovement>[
        TemplateMovement('Bench', sets: 2),
        TemplateMovement('Fly'),
      ]);
    });
  });

  group('uniqueWorkoutName', () {
    test('leaves a free name alone', () {
      expect(uniqueWorkoutName('Push', <String>['Pull']), 'Push');
    });

    test('suffixes a taken one, and keeps counting', () {
      expect(uniqueWorkoutName('Push', <String>['Push']), 'Push (2)');
      expect(
        uniqueWorkoutName('Push', <String>['Push', 'Push (2)', 'Push (3)']),
        'Push (4)',
      );
    });

    test('skips a gap rather than filling it', () {
      expect(
        uniqueWorkoutName('Push', <String>['Push', 'Push (3)']),
        'Push (2)',
      );
    });
  });

  group('InMemoryWorkoutLibrary', () {
    test('matches the Drift implementation on ordering', () async {
      final fake = InMemoryWorkoutLibrary();
      await fake.save(name: 'First', movements: moves(<String>['A']));
      await fake.save(name: 'Second', movements: moves(<String>['B']));
      expect((await fake.all()).map((w) => w.name), <String>[
        'Second',
        'First',
      ]);
    });

    test('removes, restores and updates by id', () async {
      final fake = InMemoryWorkoutLibrary();
      final saved = await fake.save(
        name: 'Push',
        movements: moves(<String>['A']),
      );
      await fake.remove(saved.id);
      expect(await fake.all(), isEmpty);
      await fake.restore(saved.id);
      await fake.update(saved.copyWith(name: 'Push B'));
      expect((await fake.byId(saved.id))!.name, 'Push B');
    });
  });
}
