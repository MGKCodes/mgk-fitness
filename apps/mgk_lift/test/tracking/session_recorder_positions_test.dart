import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/core/database/app_database.dart';
import 'package:mgk_lift/src/features/tracking/data/drift_session_recorder.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';

/// The recorder's positions, limits and read cost — the part of the 2026-09-28
/// audit that was measured rather than seen. Each test here failed against the
/// recorder it replaced.
void main() {
  late AppDatabase db;
  late DriftSessionRecorder recorder;
  var counter = 0;

  setUp(() {
    counter = 0;
    db = AppDatabase.memory();
    recorder = DriftSessionRecorder(db, idFactory: () => 'id-${++counter}');
  });

  tearDown(() async => db.close());

  /// A session with one movement holding [n] sets. Returns the movement's id.
  Future<String> movementWithSets(int n, {String name = 'Bench'}) async {
    if (await recorder.current() == null) await recorder.start();
    final s = await recorder.addExercise(name);
    final id = s.exercises.last.id;
    for (var i = 0; i < n; i++) {
      await recorder.addSet(id);
    }
    return id;
  }

  List<int> numbers(Session s, String exerciseId) => <int>[
    for (final set in s.exercises.firstWhere((e) => e.id == exerciseId).sets)
      set.setNumber,
  ];

  group('set numbers', () {
    test(
      'removing the middle set closes the gap, and the next one is last',
      () async {
        final ex = await movementWithSets(3);
        var s = (await recorder.current())!;
        s = await recorder.removeSet(s.exercises.single.sets[1].id);
        expect(numbers(s, ex), <int>[1, 2]);

        // The measured failure: numbered by count with no renumbering, this read
        // 1, 3, 3.
        s = await recorder.addSet(ex);
        expect(numbers(s, ex), <int>[1, 2, 3]);
      },
    );

    test(
      'removing the first, the last and the only set all stay contiguous',
      () async {
        final ex = await movementWithSets(3);
        var s = (await recorder.current())!;
        s = await recorder.removeSet(s.exercises.single.sets.first.id);
        expect(numbers(s, ex), <int>[1, 2]);
        s = await recorder.removeSet(s.exercises.single.sets.last.id);
        expect(numbers(s, ex), <int>[1]);
        s = await recorder.removeSet(s.exercises.single.sets.single.id);
        expect(s.exercises.single.sets, isEmpty);
      },
    );

    test('undo puts a set back where it was, exactly as it was', () async {
      final ex = await movementWithSets(3);
      var s = (await recorder.current())!;
      final middle = s.exercises.single.sets[1];
      await recorder.updateSet(
        middle.id,
        reps: 7,
        weightKg: 62.5,
        isCompleted: true,
      );
      final removed = (await recorder.current())!.exercises.single.sets[1];

      s = await recorder.removeSet(removed.id);
      s = await recorder.restoreSet(ex, removed);

      final back = s.exercises.single.sets;
      expect(<int>[for (final x in back) x.setNumber], <int>[1, 2, 3]);
      expect(back[1].id, removed.id);
      expect(back[1].reps, 7);
      expect(back[1].weightKg, 62.5);
      expect(back[1].isCompleted, isTrue);
    });

    test(
      'a carry-forward after a removal copies the set that is now last',
      () async {
        final ex = await movementWithSets(2);
        var s = (await recorder.current())!;
        await recorder.updateSet(
          s.exercises.single.sets[0].id,
          reps: 8,
          weightKg: 80,
        );
        await recorder.updateSet(
          s.exercises.single.sets[1].id,
          reps: 6,
          weightKg: 90,
        );
        s = await recorder.removeSet(s.exercises.single.sets[1].id);
        s = await recorder.addSet(ex);
        expect(s.exercises.single.sets.last.reps, 8);
        expect(s.exercises.single.sets.last.weightKg, 80);
      },
    );

    test(
      'the first set takes the seed; later ones ignore it and carry forward',
      () async {
        await recorder.start();
        final ex = (await recorder.addExercise('Squat')).exercises.single.id;
        var s = await recorder.addSet(ex, reps: 5, weightKg: 120);
        expect(s.exercises.single.sets.single.reps, 5);
        expect(s.exercises.single.sets.single.weightKg, 120);

        s = await recorder.addSet(ex, reps: 1, weightKg: 1);
        expect(
          s.exercises.single.sets.last.reps,
          5,
          reason: 'carried, not seeded',
        );
      },
    );
  });

  group('labels', () {
    test('warm-ups and marked sets take no number: W, 1, 2, D, 3', () {
      const e = SessionExercise(
        id: 'e',
        name: 'Bench',
        orderIndex: 0,
        sets: <SessionSet>[
          SessionSet(id: 'a', setNumber: 1, setType: SetType.warmup),
          SessionSet(id: 'b', setNumber: 2),
          SessionSet(id: 'c', setNumber: 3),
          SessionSet(id: 'd', setNumber: 4, setType: SetType.dropSet),
          SessionSet(id: 'f', setNumber: 5),
        ],
      );
      // It used to print setNumber: `W, 2, 3, 4` — seen on the emulator.
      expect(
        <String>[for (final s in e.sets) e.labelFor(s)],
        <String>['W', '1', '2', 'D', '3'],
      );
    });
  });

  group('movement positions', () {
    test(
      'remove one, add one: positions stay contiguous and the new one is last',
      () async {
        await recorder.start();
        await recorder.addExercises(<String>['A', 'B', 'C']);
        var s = (await recorder.current())!;
        s = await recorder.removeExercise(s.exercises[1].id);
        s = await recorder.addExercise('D');
        // Measured before the fix: A@0, C@2, D@2 — two movements in one place.
        expect(
          <String>[for (final e in s.exercises) '${e.name}@${e.orderIndex}'],
          <String>['A@0', 'C@1', 'D@2'],
        );
      },
    );

    test('undo puts a movement back at its position, sets and all', () async {
      await recorder.start();
      await recorder.addExercises(<String>['A', 'B', 'C']);
      var s = (await recorder.current())!;
      final b = s.exercises[1];
      await recorder.addSet(b.id);
      final withSet = (await recorder.current())!.exercises[1];

      await recorder.removeExercise(withSet.id);
      s = await recorder.restoreExercise(withSet);

      expect(
        <String>[for (final e in s.exercises) e.name],
        <String>['A', 'B', 'C'],
      );
      expect(s.exercises[1].sets, hasLength(1));
    });

    test('moving a movement reorders the rest around it', () async {
      await recorder.start();
      await recorder.addExercises(<String>['A', 'B', 'C']);
      var s = (await recorder.current())!;
      s = await recorder.moveExercise(s.exercises[2].id, 0);
      expect(
        <String>[for (final e in s.exercises) '${e.name}@${e.orderIndex}'],
        <String>['C@0', 'A@1', 'B@2'],
      );
    });
  });

  group('swap', () {
    test('with nothing logged, the replacement takes the same place', () async {
      await recorder.start();
      await recorder.addExercises(<String>['A', 'B', 'C']);
      var s = (await recorder.current())!;
      s = await recorder.replaceExercise(
        s.exercises.first.id,
        'X',
        sets: 3,
        reps: 8,
        weightKg: 40,
      );

      // Measured before the fix: the replacement went to the end.
      expect(
        <String>[for (final e in s.exercises) e.name],
        <String>['X', 'B', 'C'],
      );
      expect(s.exercises.first.sets, hasLength(3));
      expect(s.exercises.first.sets.first.reps, 8);
      expect(s.exercises.first.sets.first.weightKg, 40);
    });

    test(
      'with sets logged, those sets stay and the replacement goes beneath',
      () async {
        await recorder.start();
        await recorder.addExercises(<String>['Squat', 'Row']);
        var s = (await recorder.current())!;
        final squat = s.exercises.first;
        s = await recorder.addSet(squat.id);
        await recorder.updateSet(
          s.exercises.first.sets.single.id,
          reps: 5,
          weightKg: 100,
          isCompleted: true,
        );

        s = await recorder.replaceExercise(squat.id, 'Leg press');

        // The sets were lifted. A swap used to delete them.
        expect(
          <String>[for (final e in s.exercises) e.name],
          <String>['Squat', 'Leg press', 'Row'],
        );
        expect(s.exercises.first.workingSets, hasLength(1));
      },
    );
  });

  group('limits', () {
    test(
      'a movement holds twenty sets, and the twenty-first is refused',
      () async {
        final ex = await movementWithSets(SessionLimits.setsPerMovement);
        expect(() => recorder.addSet(ex), throwsA(isA<SessionLimitReached>()));
        expect(
          (await recorder.current())!.exercises.single.sets,
          hasLength(SessionLimits.setsPerMovement),
        );
      },
    );

    test(
      'a session holds thirty movements; a selection that would overflow adds nothing',
      () async {
        await recorder.start();
        await recorder.addExercises(<String>[
          for (var i = 0; i < SessionLimits.movements - 1; i++) 'M$i',
        ]);
        expect(
          () => recorder.addExercises(<String>['X', 'Y']),
          throwsA(isA<SessionLimitReached>()),
        );
        expect(
          (await recorder.current())!.exercises,
          hasLength(SessionLimits.movements - 1),
          reason: 'not half a selection',
        );
        await recorder.addExercise('Last');
        expect(
          () => recorder.addExercise('One more'),
          throwsA(isA<SessionLimitReached>()),
        );
      },
    );

    test(
      'reps and weight outside the limits are refused, never clamped',
      () async {
        final ex = await movementWithSets(1);
        final set = (await recorder.current())!.exercises
            .firstWhere((e) => e.id == ex)
            .sets
            .single;
        expect(
          () => recorder.updateSet(set.id, reps: SessionLimits.maxReps + 1),
          throwsArgumentError,
        );
        expect(
          () => recorder.updateSet(set.id, weightKg: 1000.5),
          throwsArgumentError,
        );
        expect(() => recorder.updateSet(set.id, reps: -1), throwsArgumentError);
        // The edges themselves are legal.
        await recorder.updateSet(
          set.id,
          reps: SessionLimits.maxReps,
          weightKg: 1000,
        );
        await recorder.updateSet(set.id, weightKg: 0);
      },
    );
  });

  group('finish', () {
    test(
      'sets never ticked are dropped, and so is a movement left empty',
      () async {
        await recorder.start();
        await recorder.addExercises(<String>['Bench', 'Fly', 'Dips']);
        var s = (await recorder.current())!;
        final bench = s.exercises[0].id;
        final fly = s.exercises[1].id;
        for (var i = 0; i < 3; i++) {
          s = await recorder.addSet(bench);
        }
        s = await recorder.addSet(fly);
        // Ticked: bench set 1 and 3. Fly's one set is left unticked.
        final sets = s.exercises[0].sets;
        await recorder.updateSet(
          sets[0].id,
          reps: 5,
          weightKg: 80,
          isCompleted: true,
        );
        await recorder.updateSet(
          sets[2].id,
          reps: 5,
          weightKg: 80,
          isCompleted: true,
        );

        final done = await recorder.finish();

        expect(
          <String>[for (final e in done.exercises) e.name],
          <String>['Bench'],
        );
        expect(
          <int>[for (final x in done.exercises.single.sets) x.setNumber],
          <int>[1, 2],
        );
        expect(done.exercises.single.orderIndex, 0);
      },
    );
  });

  group('cost', () {
    test('one set edit is five statements, not eighteen', () async {
      final counting = _Counting();
      final countedDb = AppDatabase(
        NativeDatabase.memory().interceptWith(counting),
      );
      addTearDown(countedDb.close);
      var n = 0;
      final r = DriftSessionRecorder(countedDb, idFactory: () => 'c-${++n}');

      await r.start();
      await r.addExercises(<String>['M0', 'M1', 'M2', 'M3', 'M4', 'M5']);
      var s = (await r.current())!;
      for (final e in s.exercises) {
        for (var i = 0; i < 3; i++) {
          s = await r.addSet(e.id);
        }
      }

      counting.reset();
      await r.updateSet(s.exercises.first.sets.first.id, weightKg: 100);

      // Measured on 2026-09-28 with the same six movements: 16 reads and 2
      // writes per keystroke. Now: the open row, the write, the stamp, and a
      // two-query read-back — whatever the session holds.
      expect(counting.reads, lessThanOrEqualTo(3));
      expect(counting.writes, lessThanOrEqualTo(2));
    });
  });

  group('indexes', () {
    test('a fresh database has every index an upgraded one has', () async {
      final rows = await db
          .customSelect("select name from sqlite_master where type = 'index'")
          .get();
      final names = <String>{for (final r in rows) r.read<String>('name')};
      // progress_photos_slot is the one that used to exist only after an
      // upgrade — every install that started at version 3 or later lacked it.
      expect(
        names,
        containsAll(<String>[
          'exercises_workout_order',
          'exercise_sets_exercise_number',
          'progress_photos_slot',
        ]),
      );
    });
  });
}

/// Counts statements by kind, so a test can pin what a change costs.
class _Counting extends QueryInterceptor {
  int reads = 0;
  int writes = 0;

  void reset() => reads = writes = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    reads++;
    return executor.runSelect(statement, args);
  }

  @override
  Future<int> runUpdate(QueryExecutor e, String s, List<Object?> a) {
    writes++;
    return e.runUpdate(s, a);
  }

  @override
  Future<int> runInsert(QueryExecutor e, String s, List<Object?> a) {
    writes++;
    return e.runInsert(s, a);
  }

  @override
  Future<int> runDelete(QueryExecutor e, String s, List<Object?> a) {
    writes++;
    return e.runDelete(s, a);
  }
}
