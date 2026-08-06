import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/core/database/app_database.dart';
import 'package:mgk_lift/src/features/tracking/data/drift_session_recorder.dart';
import 'package:mgk_lift/src/features/tracking/domain/session_recorder.dart';

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

  test('there is no session until one is started', () async {
    expect(await recorder.current(), isNull);
  });

  test('starting names the session for the time of day', () async {
    final session = await recorder.start(at: DateTime(2026, 8, 6, 7));
    expect(session.name, 'Morning session');
    expect(session.isInProgress, isTrue);
    expect(session.endedAt, isNull);
  });

  test('a second start is refused rather than abandoning the first', () async {
    await recorder.start();
    expect(() => recorder.start(), throwsA(isA<SessionInProgress>()));
  });

  test('an interrupted session is recoverable', () async {
    // The crash-recovery contract: everything is on disk before the call
    // returns, so a recorder built fresh over the same database finds the
    // session rather than losing it. This is the whole reason `endedAt` is
    // nullable.
    await recorder.start(at: DateTime(2026, 8, 6, 18));
    await recorder.addExercise('Bench press');
    await recorder.addSet('id-2');

    final afterCrash = DriftSessionRecorder(db, idFactory: () => 'x');
    final recovered = await afterCrash.current();

    expect(recovered, isNotNull);
    expect(recovered!.isInProgress, isTrue);
    expect(recovered.exercises.single.name, 'Bench press');
    expect(recovered.exercises.single.sets, hasLength(1));
  });

  test('a new set carries the last one forward, but never its tick', () async {
    await recorder.start();
    await recorder.addExercise('Squat');
    await recorder.addSet('id-2');
    await recorder.updateSet('id-3', reps: 5, weightKg: 100, isCompleted: true);

    final session = await recorder.addSet('id-2');
    final sets = session.exercises.single.sets;

    expect(sets, hasLength(2));
    expect(sets[1].reps, 5, reason: 'reps should carry forward');
    expect(sets[1].weightKg, 100, reason: 'weight should carry forward');
    expect(
      sets[1].isCompleted,
      isFalse,
      reason: 'a set must not arrive already ticked — the tick is the claim '
          'that it actually happened',
    );
    expect(sets[1].setNumber, 2);
  });

  test('volume counts completed sets only', () async {
    await recorder.start();
    await recorder.addExercise('Deadlift');
    await recorder.addSet('id-2');
    await recorder.updateSet('id-3', reps: 5, weightKg: 100, isCompleted: true);
    await recorder.addSet('id-2');
    // id-4 carries 5x100 forward but is NOT completed.
    final session = await recorder.current();

    expect(session!.volumeKg, 500);
    expect(session.completedSets, 1);
    expect(session.totalSets, 2);
  });

  test('removing an exercise takes its sets with it', () async {
    await recorder.start();
    await recorder.addExercise('Row');
    await recorder.addSet('id-2');
    await recorder.addSet('id-2');
    expect((await recorder.current())!.totalSets, 2);

    final session = await recorder.removeExercise('id-2');
    expect(session.exercises, isEmpty);
    // The cascade is enforced by SQLite, and only because the pragma is on.
    expect(await db.select(db.exerciseSets).get(), isEmpty);
  });

  test('finishing stamps the duration and closes the session', () async {
    final start = DateTime(2026, 8, 6, 18);
    await recorder.start(at: start);
    final finished = await recorder.finish(
      at: start.add(const Duration(minutes: 42)),
    );

    expect(finished.isInProgress, isFalse);
    expect(finished.elapsedAt(DateTime.now()), const Duration(minutes: 42));
    expect(await recorder.current(), isNull, reason: 'it is no longer open');
  });

  test('discarding removes the session outright', () async {
    await recorder.start();
    await recorder.addExercise('Curl');
    await recorder.discard();

    expect(await recorder.current(), isNull);
    // Hard, not soft: an abandoned session is not training that happened, so
    // it must not sync anywhere or show up in a log.
    expect(await db.select(db.workouts).get(), isEmpty);
  });

  test('editing a set leaves the fields it was not given alone', () async {
    await recorder.start();
    await recorder.addExercise('Press');
    await recorder.addSet('id-2');
    await recorder.updateSet('id-3', reps: 8, weightKg: 40);
    final session = await recorder.updateSet('id-3', isCompleted: true);

    final set = session.exercises.single.sets.single;
    expect(set.reps, 8);
    expect(set.weightKg, 40);
    expect(set.isCompleted, isTrue);
  });

  test('operations need an open session', () async {
    expect(
      () => recorder.addExercise('Bench'),
      throwsA(isA<NoSessionInProgress>()),
    );
  });
}
