import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/core/database/app_database.dart';
import 'package:mgk_lift/src/features/stats/data/drift_session_history.dart';
import 'package:mgk_lift/src/features/sync/data/sync_queue.dart';
import 'package:mgk_lift/src/features/tracking/data/drift_session_recorder.dart';
import 'package:mgk_lift/src/features/tracking/data/drift_workout_library.dart';
import 'package:mgk_lift/src/features/tracking/data/workout_templates.dart';
import 'package:mgk_lift/src/features/tracking/domain/workout_library.dart';
import 'package:mgk_lift/src/features/tracking/domain/workout_template.dart';

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

  group('the write path', () {
    test('saving writes a template row and its movements', () async {
      final saved = await library.save(
        name: 'Push',
        movements: <String>['Barbell Bench Press', 'Cable Fly'],
      );

      expect(saved.name, 'Push');
      expect(saved.movements, <String>['Barbell Bench Press', 'Cable Fly']);

      final row = await (db.select(
        db.workouts,
      )..where((w) => w.id.equals(saved.id))).getSingle();

      // The half of the schema nothing in the app used to reach.
      expect(row.isTemplate, isTrue);
      // Never ended, because it never happened.
      expect(row.endedAt, isNull);
    });

    test('movements keep the order they were given', () async {
      final saved = await library.save(
        name: 'Legs',
        movements: <String>['Barbell Back Squat', 'Leg Press', 'Calf Raise'],
      );

      final read = (await library.all()).single;
      expect(read.movements, saved.movements);
      expect(read.movements.first, 'Barbell Back Squat');
      expect(read.movements.last, 'Calf Raise');
    });

    test('a saved workout carries no sets', () async {
      // Liftio seeded three empty sets per movement. This does not — a session
      // started from a saved workout should hand the lifter an empty card, not
      // three rows of zeroes to use or delete.
      await library.save(name: 'Push', movements: <String>['Bench']);
      expect(await db.select(db.exerciseSets).get(), isEmpty);
    });

    test('the library is newest first', () async {
      await library.save(name: 'First', movements: <String>['A']);
      await library.save(name: 'Second', movements: <String>['B']);
      await library.save(name: 'Third', movements: <String>['C']);

      expect((await library.all()).map((w) => w.name), <String>[
        'Third',
        'Second',
        'First',
      ]);
    });

    test('deleting takes the movements with it', () async {
      final saved = await library.save(
        name: 'Push',
        movements: <String>['Bench', 'Fly'],
      );
      await library.remove(saved.id);

      expect(await library.all(), isEmpty);
      // Hard, not soft: a template has never been uploaded, so there is nobody
      // to tell about the delete. Orphaned movements would be the cascade not
      // firing.
      expect(await db.select(db.workouts).get(), isEmpty);
      expect(await db.select(db.exercises).get(), isEmpty);
    });
  });

  group('a template is not a session', () {
    test('a saved workout is never offered as the session in progress', () {
      // The collision this storage choice creates. A template row has no
      // `endedAt`, which is also how an interrupted session is recognised —
      // so without the isTemplate check `current()` would hand a lifter one of
      // their own routines to resume, and finishing it would file a workout
      // they never did.
      return expectLater(
        library
            .save(name: 'Push', movements: <String>['Bench'])
            .then((_) => recorder.current()),
        completion(isNull),
      );
    });

    test('a saved workout does not block starting a session', () async {
      await library.save(name: 'Push', movements: <String>['Bench']);

      // `start` throws SessionInProgress if `current()` returns anything, so
      // this is the same bug from the other side.
      final session = await recorder.start();
      expect(session.isInProgress, isTrue);
      expect(session.exercises, isEmpty);
    });

    test('a saved workout never reaches the training log', () async {
      await library.save(name: 'Push', movements: <String>['Bench']);
      expect(await DriftSessionHistory(db).all(), isEmpty);
    });

    test('a saved workout is never queued for upload', () async {
      await library.save(name: 'Push', movements: <String>['Bench']);

      // The remote constraint `workouts_template_has_no_date` requires a
      // template to have no `started_at`, and the push writes one
      // unconditionally — so a template reaching the queue would be rejected
      // by the server and would block every real session behind it.
      expect(await SyncQueue(db).dirtyWorkouts(), isEmpty);
      expect((await SyncQueue(db).pending()).workouts, 0);
    });

    test('a finished session is still queued for upload', () async {
      // The other half of the rule above: tightening the queue must not have
      // stopped anything real from going up.
      await library.save(name: 'Push', movements: <String>['Bench']);
      await recorder.start();
      await recorder.finish();

      expect(await SyncQueue(db).dirtyWorkouts(), hasLength(1));
    });
  });

  group('adding a premade', () {
    test('copies its movements and records where it came from', () async {
      final push = workoutTemplates.firstWhere((t) => t.id == 'push');

      final saved = await library.save(
        name: push.name,
        movements: push.exercises,
        fromPremade: push.id,
      );

      expect(saved.name, 'Push');
      expect(saved.movements, push.exercises);
      // The back-reference, on the template row rather than the session row.
      expect(saved.premadeId, 'push');
      expect((await library.all()).single.premadeId, 'push');
    });

    test('the copy is independent of the premade', () async {
      final push = workoutTemplates.firstWhere((t) => t.id == 'push');
      final saved = await library.save(
        name: push.name,
        movements: push.exercises,
        fromPremade: push.id,
      );

      await library.remove(saved.id);

      // Deleting the copy leaves the fifteen alone — they are const data, not
      // rows, which is the whole point of copying rather than referencing.
      expect(
        workoutTemplates.firstWhere((t) => t.id == 'push').exercises,
        push.exercises,
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
          movements: template.exercises,
          fromPremade: template.id,
        );
        names.add(name);
      }

      final saved = await library.all();
      expect(saved, hasLength(split.templateIds.length));
      expect(saved.map((w) => w.premadeId).toSet(), split.templateIds.toSet());
    });

    test('re-adding the same premade is allowed and disambiguated', () async {
      // Duplicates are deliberately allowed — keeping a heavy and a light Push
      // is a real thing people do. What is not useful is two rows both called
      // `Push` in a list you choose from standing at a rack.
      final push = workoutTemplates.firstWhere((t) => t.id == 'push');

      final names = <String>[];
      for (var i = 0; i < 3; i++) {
        final name = uniqueWorkoutName(push.name, names);
        await library.save(
          name: name,
          movements: push.exercises,
          fromPremade: push.id,
        );
        names.add(name);
      }

      expect((await library.all()).map((w) => w.name).toSet(), <String>{
        'Push',
        'Push (2)',
        'Push (3)',
      });
    });
  });

  group('starting a session from a saved workout', () {
    test('fills the session with its movements, in order', () async {
      final saved = await library.save(
        name: 'Push',
        movements: <String>['Barbell Bench Press', 'Cable Fly', 'Pushdown'],
      );

      await recorder.start();
      final session = await recorder.fillFromLibrary(
        workoutId: saved.id,
        name: saved.name,
        movements: saved.movements,
      );

      expect(session.exercises.map((e) => e.name), saved.movements);
      expect(session.exercises.map((e) => e.orderIndex), <int>[0, 1, 2]);
    });

    test('takes the workout name', () async {
      final saved = await library.save(name: 'Push', movements: <String>['A']);

      await recorder.start(name: 'Evening session');
      final session = await recorder.fillFromLibrary(
        workoutId: saved.id,
        name: saved.name,
        movements: saved.movements,
      );

      expect(session.name, 'Push');
    });

    test('records which saved workout it came from', () async {
      final saved = await library.save(name: 'Push', movements: <String>['A']);

      final started = await recorder.start();
      await recorder.fillFromLibrary(
        workoutId: saved.id,
        name: saved.name,
        movements: saved.movements,
      );

      final row = await (db.select(
        db.workouts,
      )..where((w) => w.id.equals(started.id))).getSingle();

      // `templateId` on a session row means "the saved workout this came
      // from"; `premadeId` on a template row means "the premade this was added
      // from". Two columns, so neither reader has to check a flag to know what
      // the string it is holding means.
      expect(row.templateId, saved.id);
      expect(row.premadeId, isNull);
      expect(row.isTemplate, isFalse);
    });

    test('brings movements but no sets', () async {
      final saved = await library.save(
        name: 'Push',
        movements: <String>['Bench', 'Fly'],
      );

      await recorder.start();
      final session = await recorder.fillFromLibrary(
        workoutId: saved.id,
        name: saved.name,
        movements: saved.movements,
      );

      // A saved workout says what to do, not what to lift. The lifter's first
      // tap adds the set they are about to perform.
      expect(session.exercises, hasLength(2));
      expect(session.exercises.every((e) => e.sets.isEmpty), isTrue);
    });

    test('the saved workout survives the session it started', () async {
      final saved = await library.save(name: 'Push', movements: <String>['A']);

      await recorder.start();
      await recorder.fillFromLibrary(
        workoutId: saved.id,
        name: saved.name,
        movements: saved.movements,
      );
      await recorder.finish();

      // The session is a copy. Doing it must not consume the routine.
      final library2 = await library.all();
      expect(library2, hasLength(1));
      expect(library2.single.movements, <String>['A']);
    });

    test(
      'the finished session appears in the log and the template does not',
      () async {
        final saved = await library.save(
          name: 'Push',
          movements: <String>['A'],
        );

        await recorder.start();
        await recorder.fillFromLibrary(
          workoutId: saved.id,
          name: saved.name,
          movements: saved.movements,
        );
        await recorder.finish();

        final log = await DriftSessionHistory(db).all();
        expect(log, hasLength(1));
        expect(log.single.name, 'Push');
      },
    );
  });

  group('uniqueWorkoutName', () {
    test('leaves a free name alone', () {
      expect(uniqueWorkoutName('Push', <String>['Pull']), 'Push');
    });

    test('suffixes a taken one', () {
      expect(uniqueWorkoutName('Push', <String>['Push']), 'Push (2)');
    });

    test('keeps counting past the first suffix', () {
      expect(
        uniqueWorkoutName('Push', <String>['Push', 'Push (2)', 'Push (3)']),
        'Push (4)',
      );
    });

    test('skips a gap rather than filling it', () {
      // `Push (2)` being free means it is the answer. Nothing depends on the
      // suffixes being contiguous, and looking for the lowest free one is what
      // a person scanning the list would expect.
      expect(
        uniqueWorkoutName('Push', <String>['Push', 'Push (3)']),
        'Push (2)',
      );
    });
  });

  group('InMemoryWorkoutLibrary', () {
    test('matches the Drift implementation on ordering', () async {
      final fake = InMemoryWorkoutLibrary();
      await fake.save(name: 'First', movements: <String>['A']);
      await fake.save(name: 'Second', movements: <String>['B']);

      expect((await fake.all()).map((w) => w.name), <String>[
        'Second',
        'First',
      ]);
    });

    test('carries the premade back-reference', () async {
      final fake = InMemoryWorkoutLibrary();
      await fake.save(
        name: 'Push',
        movements: <String>['A'],
        fromPremade: 'push',
      );
      expect((await fake.all()).single.premadeId, 'push');
    });

    test('removes by id', () async {
      final fake = InMemoryWorkoutLibrary();
      final saved = await fake.save(name: 'Push', movements: <String>['A']);
      await fake.save(name: 'Pull', movements: <String>['B']);

      await fake.remove(saved.id);
      expect((await fake.all()).map((w) => w.name), <String>['Pull']);
    });
  });
}
