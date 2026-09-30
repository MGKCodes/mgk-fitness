import 'dart:async';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/row_id.dart';
import '../domain/session.dart';
import '../domain/workout_library.dart';
import 'session_hydration.dart';

/// The lifter's saved workouts, stored as workout rows with `isTemplate` set.
///
/// **The same three tables the log uses, not a fourth one.** That is how Liftio
/// stored them and it is the right shape: a saved workout and a session are the
/// same thing at different points in its life, so a session started from a
/// saved workout is a copy of rows the database already knows how to hold.
///
/// ## What a template row looks like
///
/// `isTemplate` true, `endedAt` null forever, and `startedAt` holding the
/// moment it was saved because the column is not nullable — the value is never
/// read as a date. That leaves the row looking exactly like a session in
/// progress to any query that only checks `endedAt`, which is why
/// [DriftSessionRecorder.current] excludes templates explicitly.
///
/// ## Sets are the count
///
/// A movement's set count is **its set rows**: three rows, three sets, each
/// holding the rep target in `reps` (zero for none) and no weight. That is
/// Liftio's own layout — it wrote three empty sets per movement — so the
/// templates already on the server read back with their counts, and a count
/// needs no column the remote schema does not have. A movement with no rows,
/// which this app wrote before counts existed, reads as the default.
class DriftWorkoutLibrary implements WorkoutLibrary {
  DriftWorkoutLibrary(
    this._db, {
    String Function()? idFactory,
    DateTime Function()? clock,
  }) : _newId = idFactory ?? newRowId,
       _now = clock ?? DateTime.now;

  final AppDatabase _db;
  final String Function() _newId;
  final DateTime Function() _now;

  /// Every write in the app goes through the one instance `main.dart` makes,
  /// so an in-process signal is enough — and, unlike watching the tables, it
  /// does not fire on every set ticked in a session.
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<List<SavedWorkout>> all() async {
    final rows =
        await (_db.select(_db.workouts)
              ..where((w) => w.isTemplate.equals(true) & w.deletedAt.isNull())
              // By `createdAt`, not `startedAt` — a template's `startedAt` is a
              // placeholder. **`rowid` is the ordering most of the time**:
              // Drift stores a `DateTime` to the second, and adding a split
              // writes four to six rows in one tap, which then tie.
              ..orderBy([
                (w) => OrderingTerm.desc(w.createdAt),
                (_) => OrderingTerm.desc(const CustomExpression<int>('rowid')),
              ]))
            .get();
    final sessions = await hydrateWorkouts(_db, rows);
    return <SavedWorkout>[
      for (var i = 0; i < rows.length; i++) _toSaved(rows[i], sessions[i]),
    ];
  }

  @override
  Future<SavedWorkout?> byId(String id) async {
    final row =
        await (_db.select(_db.workouts)..where(
              (w) =>
                  w.id.equals(id) &
                  w.isTemplate.equals(true) &
                  w.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    return _toSaved(row, await hydrateWorkout(_db, row));
  }

  @override
  Future<SavedWorkout> save({
    required String name,
    required List<TemplateMovement> movements,
    String? fromPremade,
  }) async {
    final id = _newId();
    final at = _now();
    final clipped = _clip(name);

    // One transaction: a workout row with no movements is a library entry that
    // starts an empty session — the state the library exists to get somebody
    // out of.
    await _db.transaction(() async {
      await _db
          .into(_db.workouts)
          .insert(
            WorkoutsCompanion.insert(
              id: id,
              name: clipped,
              // Not a date: the column is not nullable and a template has none.
              startedAt: at,
              isTemplate: const Value(true),
              premadeId: Value(fromPremade),
              createdAt: Value(at),
              updatedAt: Value(at),
            ),
          );
      await _writeMovements(id, movements);
    });
    _changes.add(null);

    return SavedWorkout(
      id: id,
      name: clipped,
      movements: List<TemplateMovement>.unmodifiable(movements),
      savedAt: at,
      premadeId: fromPremade,
    );
  }

  @override
  Future<SavedWorkout> update(SavedWorkout workout) async {
    final clipped = _clip(workout.name);
    await _db.transaction(() async {
      await (_db.update(_db.workouts)
            ..where((w) => w.id.equals(workout.id) & w.isTemplate.equals(true)))
          .write(
            WorkoutsCompanion(name: Value(clipped), updatedAt: Value(_now())),
          );
      // Movements and their set rows replaced wholesale — the same rule sync
      // follows for a workout's children, which carry no clock of their own.
      await (_db.delete(
        _db.exercises,
      )..where((e) => e.workoutId.equals(workout.id))).go();
      await _writeMovements(workout.id, workout.movements);
    });
    _changes.add(null);
    return workout.copyWith(name: clipped);
  }

  /// Deletes a saved workout — **softly**, now that the library backs up.
  ///
  /// It used to be a hard delete, reasoned from templates never leaving the
  /// phone. They do now, and a row simply removed here would come back down
  /// from the server on the next pull; a tombstone is what tells the other
  /// devices it went. The tombstone is also what makes Undo cheap.
  @override
  Future<void> remove(String id) async {
    final at = _now();
    await (_db.update(_db.workouts)
          ..where((w) => w.id.equals(id) & w.isTemplate.equals(true)))
        .write(WorkoutsCompanion(deletedAt: Value(at), updatedAt: Value(at)));
    _changes.add(null);
  }

  @override
  Future<void> restore(String id) async {
    await (_db.update(
      _db.workouts,
    )..where((w) => w.id.equals(id) & w.isTemplate.equals(true))).write(
      WorkoutsCompanion(deletedAt: const Value(null), updatedAt: Value(_now())),
    );
    _changes.add(null);
  }

  Future<void> _writeMovements(
    String workoutId,
    List<TemplateMovement> movements,
  ) async {
    if (movements.length > SessionLimits.movements) {
      throw const SessionLimitReached('${SessionLimits.movements} movements');
    }
    for (var i = 0; i < movements.length; i++) {
      final m = movements[i];
      final exerciseId = _newId();
      await _db
          .into(_db.exercises)
          .insert(
            ExercisesCompanion.insert(
              id: exerciseId,
              workoutId: workoutId,
              name: m.name,
              orderIndex: Value(i),
            ),
          );
      final count = m.sets.clamp(1, SessionLimits.setsPerMovement);
      for (var n = 1; n <= count; n++) {
        await _db
            .into(_db.exerciseSets)
            .insert(
              ExerciseSetsCompanion.insert(
                id: _newId(),
                exerciseId: exerciseId,
                setNumber: Value(n),
                reps: Value((m.repTarget ?? 0).clamp(0, SessionLimits.maxReps)),
              ),
            );
      }
    }
  }

  /// A template row, read back as the workout it describes.
  static SavedWorkout _toSaved(WorkoutRow row, Session session) => SavedWorkout(
    id: row.id,
    name: row.name,
    movements: <TemplateMovement>[
      for (final e in session.exercises)
        TemplateMovement(
          e.name,
          sets: e.sets.isEmpty
              ? TemplateMovement.defaultSets
              : e.sets.length.clamp(1, SessionLimits.setsPerMovement),
          repTarget: e.sets.isEmpty || e.sets.first.reps <= 0
              ? null
              : e.sets.first.reps,
        ),
    ],
    savedAt: row.createdAt,
    premadeId: row.premadeId,
  );

  static String _clip(String name) {
    final trimmed = name.trim();
    return trimmed.length <= SessionLimits.nameLength
        ? trimmed
        : trimmed.substring(0, SessionLimits.nameLength);
  }
}
