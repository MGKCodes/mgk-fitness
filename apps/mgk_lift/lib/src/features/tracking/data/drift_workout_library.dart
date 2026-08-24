import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/row_id.dart';
import '../domain/workout_library.dart';

/// The lifter's saved workouts, stored as workout rows with `isTemplate` set.
///
/// **The same three tables the log uses, not a fourth one.** That is how Liftio
/// stored them and it is the right shape: a saved workout and a session are the
/// same thing at different points in its life, so a session started from a
/// saved workout is a copy of rows the database already knows how to hold. A
/// separate `templates` table would have needed a second definition of what a
/// movement is, and the day the two drifted apart a saved workout would have
/// stopped being startable.
///
/// ## What a template row looks like
///
/// `isTemplate` true, `endedAt` null forever, and `startedAt` holding the
/// moment it was saved because the column is not nullable — the value is never
/// read as a date and nothing should start reading it as one. That leaves the
/// row looking exactly like a session in progress to any query that only checks
/// `endedAt`, which is why [DriftSessionRecorder.current] excludes templates
/// explicitly. It is the one collision this storage choice creates and it is
/// worth knowing about rather than discovering.
///
/// ## Sets
///
/// None are written. Liftio created three empty sets per movement as a
/// scaffold; this does not, because a session started from a saved workout
/// hands the lifter an empty card and the first tap adds the set they are
/// about to do. Three rows of zeroes would have to be either used or deleted,
/// and either way somebody has to look at them.
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

  @override
  Future<List<SavedWorkout>> all() async {
    final rows =
        await (_db.select(_db.workouts)
              ..where((w) => w.isTemplate.equals(true) & w.deletedAt.isNull())
              // By `createdAt`, not `startedAt`. They are the same value today
              // and only one of them is guaranteed to stay that way — a
              // template's `startedAt` is a placeholder for a non-nullable
              // column and carries no promise about what it means.
              //
              // **`rowid` is not a tiebreaker for an edge case; it is the
              // ordering most of the time.** Drift stores a `DateTime` as unix
              // *seconds*, and adding a split writes four to six rows in one
              // tap — so they tie, and on `createdAt` alone SQLite is free to
              // return a Push/Pull/Legs split in any order it likes. Insertion
              // order descending is what "newest first" actually means here.
              ..orderBy([
                (w) => OrderingTerm.desc(w.createdAt),
                (_) => OrderingTerm.desc(const CustomExpression<int>('rowid')),
              ]))
            .get();

    final saved = <SavedWorkout>[];
    for (final row in rows) {
      final movements =
          await (_db.select(_db.exercises)
                ..where((e) => e.workoutId.equals(row.id))
                ..orderBy([(e) => OrderingTerm.asc(e.orderIndex)]))
              .get();
      saved.add(
        SavedWorkout(
          id: row.id,
          name: row.name,
          movements: <String>[for (final e in movements) e.name],
          savedAt: row.createdAt,
          premadeId: row.premadeId,
        ),
      );
    }
    return saved;
  }

  @override
  Future<SavedWorkout> save({
    required String name,
    required List<String> movements,
    String? fromPremade,
  }) async {
    final id = _newId();
    final at = _now();

    // One transaction, because a workout row with no movements is a library
    // entry that starts an empty session — the exact state a lifter would have
    // to notice and delete themselves.
    await _db.transaction(() async {
      await _db
          .into(_db.workouts)
          .insert(
            WorkoutsCompanion.insert(
              id: id,
              name: name,
              // Not a date. See the class comment: the column is not nullable
              // and a template has no date, remotely or in principle.
              startedAt: at,
              isTemplate: const Value(true),
              premadeId: Value(fromPremade),
              createdAt: Value(at),
              updatedAt: Value(at),
            ),
          );

      for (var i = 0; i < movements.length; i++) {
        await _db
            .into(_db.exercises)
            .insert(
              ExercisesCompanion.insert(
                id: _newId(),
                workoutId: id,
                name: movements[i],
                orderIndex: Value(i),
              ),
            );
      }
    });

    return SavedWorkout(
      id: id,
      name: name,
      movements: <String>[...movements],
      savedAt: at,
      premadeId: fromPremade,
    );
  }

  /// Deletes a saved workout outright, movements and all.
  ///
  /// **A hard delete, unlike deleting a finished session.** The soft delete
  /// exists so that removing something which has already been uploaded reaches
  /// the other devices rather than reappearing from the backup. A template has
  /// never been uploaded — see `SyncQueue.dirtyWorkouts` — so there is nobody
  /// to tell, and a tombstone would be a hidden row kept forever for a sync
  /// that cannot happen. Same reasoning as `SessionRecorder.discard`.
  @override
  Future<void> remove(String id) async {
    // Movements go with it via ON DELETE CASCADE, enabled in
    // AppDatabase.migration.
    await (_db.delete(
      _db.workouts,
    )..where((w) => w.id.equals(id) & w.isTemplate.equals(true))).go();
  }
}
