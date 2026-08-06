import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/session.dart';
import '../domain/session_recorder.dart';
import 'session_hydration.dart';

/// The real recorder: every change is written to the on-device database before
/// the caller sees it.
///
/// Reads rebuild the whole session from storage rather than mutating a cached
/// copy. That is slightly more work per call and removes an entire category of
/// bug — the in-memory session and the rows on disk cannot disagree, because
/// there is only ever one of them.
class DriftSessionRecorder implements SessionRecorder {
  DriftSessionRecorder(this._db, {String Function()? idFactory})
    : _newId = idFactory ?? _uuid;

  final AppDatabase _db;
  final String Function() _newId;

  @override
  Future<Session?> current() async {
    final row =
        await (_db.select(_db.workouts)
              ..where((w) => w.endedAt.isNull() & w.deletedAt.isNull())
              ..orderBy([(w) => OrderingTerm.desc(w.startedAt)])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    return _hydrate(row);
  }

  @override
  Future<Session> start({String? name, DateTime? at}) async {
    if (await current() != null) throw const SessionInProgress();
    final now = at ?? DateTime.now();
    final id = _newId();
    await _db
        .into(_db.workouts)
        .insert(
          WorkoutsCompanion.insert(
            id: id,
            name: name ?? _defaultName(now),
            startedAt: now,
          ),
        );
    return (await current())!;
  }

  @override
  Future<Session> addExercise(String name, {String? cardioMode}) async {
    final session = await _requireCurrent();
    await _db
        .into(_db.exercises)
        .insert(
          ExercisesCompanion.insert(
            id: _newId(),
            workoutId: session.id,
            name: name,
            orderIndex: Value(session.exercises.length),
            cardioMode: Value(cardioMode),
          ),
        );
    return _touch(session.id);
  }

  @override
  Future<Session> addSet(String exerciseId) async {
    final session = await _requireCurrent();
    final exercise = session.exercises.firstWhere(
      (e) => e.id == exerciseId,
      orElse: () => throw ArgumentError('No exercise $exerciseId'),
    );
    // Carry the last set's numbers forward. Not the *top* set — the last one,
    // because a lifter dropping weight across sets means the next is more likely
    // to look like what they just did than like their best.
    final last = exercise.sets.isEmpty ? null : exercise.sets.last;
    await _db
        .into(_db.exerciseSets)
        .insert(
          ExerciseSetsCompanion.insert(
            id: _newId(),
            exerciseId: exerciseId,
            setNumber: Value(exercise.sets.length + 1),
            reps: Value(last?.reps ?? 0),
            weightKg: Value(last?.weightKg ?? 0),
            // Never carried forward: the whole point of the tick is that it
            // says this one actually happened.
            isCompleted: const Value(false),
          ),
        );
    return _touch(session.id);
  }

  @override
  Future<Session> updateSet(
    String setId, {
    int? reps,
    double? weightKg,
    bool? isCompleted,
    SetType? setType,
    int? durationS,
    double? distanceM,
  }) async {
    final session = await _requireCurrent();
    await (_db.update(_db.exerciseSets)..where((s) => s.id.equals(setId))).write(
      ExerciseSetsCompanion(
        reps: reps == null ? const Value.absent() : Value(reps),
        weightKg: weightKg == null ? const Value.absent() : Value(weightKg),
        isCompleted: isCompleted == null
            ? const Value.absent()
            : Value(isCompleted),
        setType: setType == null
            ? const Value.absent()
            : Value(setType.stored),
        durationS: durationS == null ? const Value.absent() : Value(durationS),
        distanceM: distanceM == null ? const Value.absent() : Value(distanceM),
      ),
    );
    return _touch(session.id);
  }

  @override
  Future<Session> removeSet(String setId) async {
    final session = await _requireCurrent();
    await (_db.delete(_db.exerciseSets)..where((s) => s.id.equals(setId))).go();
    return _touch(session.id);
  }

  @override
  Future<Session> removeExercise(String exerciseId) async {
    final session = await _requireCurrent();
    // Sets go with it via ON DELETE CASCADE, which is enabled in
    // AppDatabase.migration — without that pragma these would be orphaned.
    await (_db.delete(_db.exercises)..where((e) => e.id.equals(exerciseId))).go();
    return _touch(session.id);
  }

  @override
  Future<Session> finish({DateTime? at}) async {
    final session = await _requireCurrent();
    final ended = at ?? DateTime.now();
    await (_db.update(_db.workouts)..where((w) => w.id.equals(session.id))).write(
      WorkoutsCompanion(
        endedAt: Value(ended),
        durationS: Value(ended.difference(session.startedAt).inSeconds.abs()),
        updatedAt: Value(ended),
      ),
    );
    final row = await (_db.select(
      _db.workouts,
    )..where((w) => w.id.equals(session.id))).getSingle();
    return _hydrate(row);
  }

  @override
  Future<void> discard() async {
    final session = await current();
    if (session == null) return;
    // Hard delete: an abandoned session is not training that happened, so it
    // must not sync or appear in a log. Deleting a *finished* session is a soft
    // delete, which is a different operation entirely.
    await (_db.delete(_db.workouts)..where((w) => w.id.equals(session.id))).go();
  }

  Future<Session> _requireCurrent() async {
    final session = await current();
    if (session == null) throw const NoSessionInProgress();
    return session;
  }

  /// Re-reads a session and stamps `updatedAt`, so sync has something to order
  /// by and the caller gets storage's version rather than an assumption.
  Future<Session> _touch(String id) async {
    await (_db.update(_db.workouts)..where((w) => w.id.equals(id))).write(
      WorkoutsCompanion(updatedAt: Value(DateTime.now())),
    );
    final row = await (_db.select(
      _db.workouts,
    )..where((w) => w.id.equals(id))).getSingle();
    return _hydrate(row);
  }

  Future<Session> _hydrate(WorkoutRow row) => hydrateWorkout(_db, row);

  static String _defaultName(DateTime at) {
    if (at.hour < 12) return 'Morning session';
    if (at.hour < 17) return 'Afternoon session';
    return 'Evening session';
  }
}

/// Small, dependency-free id. Not a real UUID and does not need to be — it only
/// has to be unique within one account's rows, and the database enforces that.
String _uuid() {
  final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final salt = identityHashCode(Object()).toRadixString(36);
  return '$now-$salt';
}
