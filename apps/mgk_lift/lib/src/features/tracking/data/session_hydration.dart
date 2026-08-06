import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/session.dart';

/// Builds a [Session] from its stored rows.
///
/// Shared by the recorder and the history reader deliberately. Two copies of
/// this would be two answers to "what is a session", and the day they drifted
/// apart the active screen and the log would disagree about the same workout.
Future<Session> hydrateWorkout(AppDatabase db, WorkoutRow row) async {
  final exerciseRows =
      await (db.select(db.exercises)
            ..where((e) => e.workoutId.equals(row.id))
            ..orderBy([(e) => OrderingTerm.asc(e.orderIndex)]))
          .get();

  final exercises = <SessionExercise>[];
  for (final e in exerciseRows) {
    final setRows =
        await (db.select(db.exerciseSets)
              ..where((s) => s.exerciseId.equals(e.id))
              ..orderBy([(s) => OrderingTerm.asc(s.setNumber)]))
            .get();
    exercises.add(
      SessionExercise(
        id: e.id,
        name: e.name,
        orderIndex: e.orderIndex,
        notes: e.notes,
        cardioMode: e.cardioMode,
        sets: <SessionSet>[
          for (final s in setRows)
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
        ],
      ),
    );
  }

  return Session(
    id: row.id,
    name: row.name,
    startedAt: row.startedAt,
    endedAt: row.endedAt,
    notes: row.notes,
    exercises: exercises,
  );
}
