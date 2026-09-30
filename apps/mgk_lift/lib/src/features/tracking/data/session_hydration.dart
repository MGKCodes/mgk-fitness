import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/session.dart';

/// Builds a [Session] from its stored rows.
///
/// Shared by the recorder and the history reader deliberately. Two copies of
/// this would be two answers to "what is a session", and the day they drifted
/// apart the active screen and the log would disagree about the same workout.
Future<Session> hydrateWorkout(AppDatabase db, WorkoutRow row) async =>
    (await hydrateWorkouts(db, <WorkoutRow>[row])).single;

/// Builds many sessions in **two queries, however many there are**.
///
/// It used to be one query per movement: a session of six movements cost seven
/// reads, the recorder did that twice per change — sixteen reads for one
/// keystroke, measured — and the history screen did it for every session in
/// the log, on every return to Track. Now the movements of every row come in
/// one query and their sets in a second, grouped here.
///
/// Order is total, not merely probable: position, then creation, then rowid.
/// Rows written before positions were kept contiguous can share an index, and
/// SQLite is free to return ties in any order — which on a session screen reads
/// as movements swapping places between two reads of the same data.
Future<List<Session>> hydrateWorkouts(
  AppDatabase db,
  List<WorkoutRow> rows,
) async {
  if (rows.isEmpty) return const <Session>[];

  final exerciseRows = <ExerciseRow>[];
  for (final ids in _chunks(<String>[for (final r in rows) r.id])) {
    exerciseRows.addAll(
      await (db.select(db.exercises)
            ..where((e) => e.workoutId.isIn(ids))
            ..orderBy([
              (e) => OrderingTerm.asc(e.orderIndex),
              (e) => OrderingTerm.asc(e.createdAt),
              (_) => OrderingTerm.asc(const CustomExpression<int>('rowid')),
            ]))
          .get(),
    );
  }

  final setRows = <SetRow>[];
  for (final ids in _chunks(<String>[for (final e in exerciseRows) e.id])) {
    setRows.addAll(
      await (db.select(db.exerciseSets)
            ..where((s) => s.exerciseId.isIn(ids))
            ..orderBy([
              (s) => OrderingTerm.asc(s.setNumber),
              (s) => OrderingTerm.asc(s.createdAt),
              (_) => OrderingTerm.asc(const CustomExpression<int>('rowid')),
            ]))
          .get(),
    );
  }

  final setsByExercise = <String, List<SessionSet>>{};
  for (final s in setRows) {
    (setsByExercise[s.exerciseId] ??= <SessionSet>[]).add(
      SessionSet(
        id: s.id,
        setNumber: s.setNumber,
        reps: s.reps,
        weightKg: s.weightKg,
        isCompleted: s.isCompleted,
        setType: SetType.fromStored(s.setType),
        durationS: s.durationS,
        distanceM: s.distanceM,
      ),
    );
  }

  final exercisesByWorkout = <String, List<SessionExercise>>{};
  for (final e in exerciseRows) {
    (exercisesByWorkout[e.workoutId] ??= <SessionExercise>[]).add(
      SessionExercise(
        id: e.id,
        name: e.name,
        orderIndex: e.orderIndex,
        notes: e.notes,
        cardioMode: e.cardioMode,
        sets: setsByExercise[e.id] ?? const <SessionSet>[],
      ),
    );
  }

  return <Session>[
    for (final row in rows)
      Session(
        id: row.id,
        name: row.name,
        startedAt: row.startedAt,
        endedAt: row.endedAt,
        notes: row.notes,
        exercises: exercisesByWorkout[row.id] ?? const <SessionExercise>[],
        templateId: row.templateId,
        templateSnapshot: row.templateSnapshot,
      ),
  ];
}

/// SQLite caps the variables in one statement. 500 sits under every limit a
/// build of it has shipped with, and a log that needs two chunks is two
/// queries rather than a crash.
Iterable<List<String>> _chunks(List<String> ids) sync* {
  const size = 500;
  for (var i = 0; i < ids.length; i += size) {
    yield ids.sublist(i, i + size > ids.length ? ids.length : i + size);
  }
}
