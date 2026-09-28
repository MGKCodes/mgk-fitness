import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/database/row_id.dart';
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
///
/// ## One transaction, one read-back
///
/// Every change runs inside a transaction and reads the session back **once**,
/// at the end. It used to hydrate the whole session before a change and again
/// after it, one query per movement each time — sixteen reads and two writes
/// for a single keystroke in a six-movement session, measured on 2026-09-28.
/// It is now the open row, the write, the stamp and a two-query read-back.
///
/// The transaction is also what makes the multi-row changes safe: a removal
/// and the renumbering behind it, a swap, a whole selection of movements. A
/// half-applied change cannot reach the disk.
///
/// ## Positions stay contiguous
///
/// Set numbers and movement positions are renumbered in the same write as any
/// removal. Numbering new rows by count was only correct while nothing was ever
/// removed; the first removal produced `1, 3, 3` and movements sharing a
/// position, which SQLite then returned in whatever order it liked.
class DriftSessionRecorder implements SessionRecorder {
  DriftSessionRecorder(this._db, {String Function()? idFactory})
    : _newId = idFactory ?? newRowId;

  final AppDatabase _db;
  final String Function() _newId;

  /// The open workout row, without its children.
  ///
  /// **Three conditions, and the template one is load-bearing.** A saved
  /// workout is stored as a workout row that has never ended, so on `endedAt`
  /// alone it is indistinguishable from a session somebody force-quit out of —
  /// and the moment the library had anything in it, "Resume session" would have
  /// offered the lifter their own routine and finishing it would have filed a
  /// workout they never did. See `Workouts.isTemplate`.
  Future<WorkoutRow?> _openRow() =>
      (_db.select(_db.workouts)
            ..where(
              (w) =>
                  w.endedAt.isNull() &
                  w.deletedAt.isNull() &
                  w.isTemplate.equals(false),
            )
            ..orderBy([(w) => OrderingTerm.desc(w.startedAt)])
            ..limit(1))
          .getSingleOrNull();

  Future<WorkoutRow> _requireOpen() async {
    final row = await _openRow();
    if (row == null) throw const NoSessionInProgress();
    return row;
  }

  @override
  Future<Session?> current() async {
    final row = await _openRow();
    return row == null ? null : hydrateWorkout(_db, row);
  }

  /// Runs [body] against the open session in one transaction, stamps the
  /// session so sync has something to order by, and returns storage's version.
  ///
  /// [renamed] is for the one change that alters the workout row itself — the
  /// read-back reuses the row read inside the transaction rather than selecting
  /// it again, which is what keeps a set edit to five queries.
  Future<Session> _change(
    Future<void> Function(WorkoutRow open) body, {
    String? renamed,
  }) async {
    late WorkoutRow open;
    await _db.transaction(() async {
      open = await _requireOpen();
      await body(open);
      await (_db.update(_db.workouts)..where((w) => w.id.equals(open.id)))
          .write(WorkoutsCompanion(updatedAt: Value(DateTime.now())));
    });
    return hydrateWorkout(
      _db,
      renamed == null ? open : open.copyWith(name: renamed),
    );
  }

  @override
  Future<Session> start({String? name, DateTime? at}) async {
    final now = at ?? DateTime.now();
    final id = _newId();
    await _db.transaction(() async {
      if (await _openRow() != null) throw const SessionInProgress();
      await _db
          .into(_db.workouts)
          .insert(
            WorkoutsCompanion.insert(
              id: id,
              name: _clip(name ?? _defaultName(now)),
              startedAt: now,
            ),
          );
    });
    return (await current())!;
  }

  @override
  Future<Session> addExercise(String name, {String? cardioMode}) =>
      _change((open) => _insertExercises(open.id, <String>[name], cardioMode));

  @override
  Future<Session> addExercises(List<String> names) =>
      _change((open) => _insertExercises(open.id, names, null));

  /// Appends [names] after the last movement, checking the limit for the whole
  /// selection first.
  ///
  /// After the highest position, not at the count: a session opened by an
  /// older build can still hold positions with gaps or ties, and counting
  /// would land a new movement on top of one already there.
  Future<void> _insertExercises(
    String workoutId,
    List<String> names,
    String? cardioMode,
  ) async {
    final existing = await _exerciseRows(workoutId);
    if (existing.length + names.length > SessionLimits.movements) {
      throw const SessionLimitReached('${SessionLimits.movements} movements');
    }
    var next = existing.isEmpty
        ? 0
        : existing.map((e) => e.orderIndex).reduce((a, b) => a > b ? a : b) + 1;
    for (final name in names) {
      await _db
          .into(_db.exercises)
          .insert(
            ExercisesCompanion.insert(
              id: _newId(),
              workoutId: workoutId,
              name: name,
              orderIndex: Value(next++),
              cardioMode: Value(cardioMode),
            ),
          );
    }
  }

  @override
  Future<Session> fillFromLibrary({
    required String workoutId,
    required String name,
    required List<String> movements,
  }) {
    final clipped = _clip(name);
    return _change((open) async {
      // The name and the back-reference together, in one write. `templateId`
      // is what a "how often do I actually run this" figure would later be
      // counted on, so a session filled from the library without it would
      // simply be missing from its own workout's history.
      await (_db.update(
        _db.workouts,
      )..where((w) => w.id.equals(open.id))).write(
        WorkoutsCompanion(name: Value(clipped), templateId: Value(workoutId)),
      );
      await _insertExercises(open.id, movements, null);
    }, renamed: clipped);
  }

  @override
  Future<Session> addSet(
    String exerciseId, {
    int? reps,
    double? weightKg,
  }) => _change((open) async {
    await _requireExercise(open.id, exerciseId);
    final sets = await _setRows(exerciseId);
    if (sets.length >= SessionLimits.setsPerMovement) {
      throw const SessionLimitReached('${SessionLimits.setsPerMovement} sets');
    }
    // Carry the last set's numbers forward. Not the *top* set — the last
    // one, because a lifter dropping weight across sets means the next is
    // more likely to look like what they just did than like their best.
    // With nothing to carry, the seed: what they did last time.
    final last = sets.isEmpty ? null : sets.last;
    await _db
        .into(_db.exerciseSets)
        .insert(
          ExerciseSetsCompanion.insert(
            id: _newId(),
            exerciseId: exerciseId,
            setNumber: Value(sets.length + 1),
            reps: Value(last?.reps ?? _repsInRange(reps ?? 0)),
            weightKg: Value(last?.weightKg ?? _weightInRange(weightKg ?? 0)),
            durationS: Value(last?.durationS),
            distanceM: Value(last?.distanceM),
            // Never carried forward: the whole point of the tick is that
            // it says this one actually happened.
            isCompleted: const Value(false),
          ),
        );
  });

  @override
  Future<Session> updateSet(
    String setId, {
    int? reps,
    double? weightKg,
    bool? isCompleted,
    SetType? setType,
    int? durationS,
    double? distanceM,
  }) {
    // Refused rather than clamped. The field cannot produce these; anything
    // that does is a bug, and a clamped number would hide it as a quietly
    // wrong one.
    if (reps != null) _repsInRange(reps);
    if (weightKg != null) _weightInRange(weightKg);
    return _change((open) async {
      // Scoped to the open session in the same statement. A set id from a
      // finished workout — or a removed one, reached by an edit queued just
      // before it went — writes nothing rather than editing history.
      await (_db.update(_db.exerciseSets)..where(
            (s) =>
                s.id.equals(setId) &
                s.exerciseId.isInQuery(_exerciseIdsOf(open.id)),
          ))
          .write(
            ExerciseSetsCompanion(
              reps: reps == null ? const Value.absent() : Value(reps),
              weightKg: weightKg == null
                  ? const Value.absent()
                  : Value(weightKg),
              isCompleted: isCompleted == null
                  ? const Value.absent()
                  : Value(isCompleted),
              setType: setType == null
                  ? const Value.absent()
                  : Value(setType.stored),
              durationS: durationS == null
                  ? const Value.absent()
                  : Value(durationS),
              distanceM: distanceM == null
                  ? const Value.absent()
                  : Value(distanceM),
            ),
          );
    });
  }

  @override
  Future<Session> removeSet(String setId) => _change((open) async {
    final row =
        await (_db.select(_db.exerciseSets)..where(
              (s) =>
                  s.id.equals(setId) &
                  s.exerciseId.isInQuery(_exerciseIdsOf(open.id)),
            ))
            .getSingleOrNull();
    if (row == null) return;
    await (_db.delete(_db.exerciseSets)..where((s) => s.id.equals(setId))).go();
    await _renumberSets(row.exerciseId);
  });

  @override
  Future<Session> restoreSet(String exerciseId, SessionSet set) => _change((
    open,
  ) async {
    await _requireExercise(open.id, exerciseId);
    final sets = await _setRows(exerciseId);
    if (sets.length >= SessionLimits.setsPerMovement) {
      throw const SessionLimitReached('${SessionLimits.setsPerMovement} sets');
    }
    // Make room at its old position, then put it back exactly as it was.
    for (final s in sets.where((s) => s.setNumber >= set.setNumber)) {
      await (_db.update(_db.exerciseSets)..where((r) => r.id.equals(s.id)))
          .write(ExerciseSetsCompanion(setNumber: Value(s.setNumber + 1)));
    }
    await _db
        .into(_db.exerciseSets)
        .insert(
          ExerciseSetsCompanion.insert(
            id: set.id,
            exerciseId: exerciseId,
            setNumber: Value(set.setNumber),
            reps: Value(set.reps),
            weightKg: Value(set.weightKg),
            isCompleted: Value(set.isCompleted),
            setType: Value(set.setType.stored),
            durationS: Value(set.durationS),
            distanceM: Value(set.distanceM),
          ),
        );
    await _renumberSets(exerciseId);
  });

  @override
  Future<Session> removeExercise(String exerciseId) => _change((open) async {
    // Sets go with it via ON DELETE CASCADE, which is enabled in
    // AppDatabase.migration — without that pragma these would be orphaned.
    await (_db.delete(_db.exercises)
          ..where((e) => e.id.equals(exerciseId) & e.workoutId.equals(open.id)))
        .go();
    await _renumberExercises(open.id);
  });

  @override
  Future<Session> restoreExercise(SessionExercise exercise) => _change((
    open,
  ) async {
    final existing = await _exerciseRows(open.id);
    if (existing.length >= SessionLimits.movements) {
      throw const SessionLimitReached('${SessionLimits.movements} movements');
    }
    for (final e in existing.where(
      (e) => e.orderIndex >= exercise.orderIndex,
    )) {
      await (_db.update(_db.exercises)..where((r) => r.id.equals(e.id))).write(
        ExercisesCompanion(orderIndex: Value(e.orderIndex + 1)),
      );
    }
    await _db
        .into(_db.exercises)
        .insert(
          ExercisesCompanion.insert(
            id: exercise.id,
            workoutId: open.id,
            name: exercise.name,
            orderIndex: Value(exercise.orderIndex),
            notes: Value(exercise.notes),
            cardioMode: Value(exercise.cardioMode),
          ),
        );
    for (final set in exercise.sets) {
      await _db
          .into(_db.exerciseSets)
          .insert(
            ExerciseSetsCompanion.insert(
              id: set.id,
              exerciseId: exercise.id,
              setNumber: Value(set.setNumber),
              reps: Value(set.reps),
              weightKg: Value(set.weightKg),
              isCompleted: Value(set.isCompleted),
              setType: Value(set.setType.stored),
              durationS: Value(set.durationS),
              distanceM: Value(set.distanceM),
            ),
          );
    }
    await _renumberExercises(open.id);
  });

  @override
  Future<Session> replaceExercise(
    String exerciseId,
    String name, {
    int sets = 0,
    int? reps,
    double? weightKg,
  }) => _change((open) async {
    final old = await _requireExercise(open.id, exerciseId);
    final logged =
        await (_db.select(_db.exerciseSets)..where(
              (s) =>
                  s.exerciseId.equals(exerciseId) & s.isCompleted.equals(true),
            ))
            .get();

    // Nothing ticked: it is replaced where it stands. Something ticked: those
    // sets were lifted, so it stays and the replacement goes directly under it.
    final position = logged.isEmpty ? old.orderIndex : old.orderIndex + 1;
    if (logged.isEmpty) {
      await (_db.delete(
        _db.exercises,
      )..where((e) => e.id.equals(exerciseId))).go();
    } else {
      final existing = await _exerciseRows(open.id);
      if (existing.length >= SessionLimits.movements) {
        throw const SessionLimitReached('${SessionLimits.movements} movements');
      }
    }
    for (final e in await _exerciseRows(open.id)) {
      if (e.orderIndex >= position) {
        await (_db.update(_db.exercises)..where((r) => r.id.equals(e.id)))
            .write(ExercisesCompanion(orderIndex: Value(e.orderIndex + 1)));
      }
    }

    final id = _newId();
    await _db
        .into(_db.exercises)
        .insert(
          ExercisesCompanion.insert(
            id: id,
            workoutId: open.id,
            name: name,
            orderIndex: Value(position),
          ),
        );
    final count = sets.clamp(0, SessionLimits.setsPerMovement);
    for (var i = 0; i < count; i++) {
      await _db
          .into(_db.exerciseSets)
          .insert(
            ExerciseSetsCompanion.insert(
              id: _newId(),
              exerciseId: id,
              setNumber: Value(i + 1),
              reps: Value(_repsInRange(reps ?? 0)),
              // Null stays blank rather than becoming a zero: a movement the
              // coach could not put a number on is a real prescription.
              weightKg: Value(_weightInRange(weightKg ?? 0)),
            ),
          );
    }
    await _renumberExercises(open.id);
  });

  @override
  Future<Session> moveExercise(String exerciseId, int toIndex) =>
      _change((open) async {
        final rows = await _exerciseRows(open.id);
        final from = rows.indexWhere((e) => e.id == exerciseId);
        if (from < 0) return;
        final moved = rows.removeAt(from);
        rows.insert(toIndex.clamp(0, rows.length), moved);
        for (var i = 0; i < rows.length; i++) {
          if (rows[i].orderIndex != i) {
            await (_db.update(_db.exercises)
                  ..where((r) => r.id.equals(rows[i].id)))
                .write(ExercisesCompanion(orderIndex: Value(i)));
          }
        }
      });

  @override
  Future<Session> finish({DateTime? at}) async {
    final ended = at ?? DateTime.now();
    late WorkoutRow open;
    await _db.transaction(() async {
      open = await _requireOpen();

      // Sets that were never ticked did not happen (decision D3). Then any
      // movement left holding nothing, for the same reason.
      await (_db.delete(_db.exerciseSets)..where(
            (s) =>
                s.exerciseId.isInQuery(_exerciseIdsOf(open.id)) &
                s.isCompleted.equals(false),
          ))
          .go();
      for (final e in await _exerciseRows(open.id)) {
        final remaining = await _setRows(e.id);
        if (remaining.isEmpty) {
          await (_db.delete(
            _db.exercises,
          )..where((r) => r.id.equals(e.id))).go();
        } else {
          await _renumberSets(e.id);
        }
      }
      await _renumberExercises(open.id);

      await (_db.update(
        _db.workouts,
      )..where((w) => w.id.equals(open.id))).write(
        WorkoutsCompanion(
          endedAt: Value(ended),
          durationS: Value(ended.difference(open.startedAt).inSeconds.abs()),
          updatedAt: Value(ended),
        ),
      );
    });
    final row = await (_db.select(
      _db.workouts,
    )..where((w) => w.id.equals(open.id))).getSingle();
    return hydrateWorkout(_db, row);
  }

  @override
  Future<void> discard() async {
    final open = await _openRow();
    if (open == null) return;
    // Hard delete: an abandoned session is not training that happened, so it
    // must not sync or appear in a log. Deleting a *finished* session is a soft
    // delete, which is a different operation entirely.
    await (_db.delete(_db.workouts)..where((w) => w.id.equals(open.id))).go();
  }

  // ---- helpers --------------------------------------------------------------

  /// The ids of the open session's movements, as a subquery — so a statement
  /// can be scoped to "this session" without a round trip to fetch them.
  BaseSelectStatement _exerciseIdsOf(String workoutId) =>
      _db.selectOnly(_db.exercises)
        ..addColumns([_db.exercises.id])
        ..where(_db.exercises.workoutId.equals(workoutId));

  Future<List<ExerciseRow>> _exerciseRows(String workoutId) =>
      (_db.select(_db.exercises)
            ..where((e) => e.workoutId.equals(workoutId))
            ..orderBy([
              (e) => OrderingTerm.asc(e.orderIndex),
              (e) => OrderingTerm.asc(e.createdAt),
              (_) => OrderingTerm.asc(const CustomExpression<int>('rowid')),
            ]))
          .get();

  Future<List<SetRow>> _setRows(String exerciseId) =>
      (_db.select(_db.exerciseSets)
            ..where((s) => s.exerciseId.equals(exerciseId))
            ..orderBy([
              (s) => OrderingTerm.asc(s.setNumber),
              (s) => OrderingTerm.asc(s.createdAt),
              (_) => OrderingTerm.asc(const CustomExpression<int>('rowid')),
            ]))
          .get();

  Future<ExerciseRow> _requireExercise(String workoutId, String id) async {
    final row =
        await (_db.select(_db.exercises)
              ..where((e) => e.id.equals(id) & e.workoutId.equals(workoutId)))
            .getSingleOrNull();
    if (row == null) throw ArgumentError('No exercise $id in the open session');
    return row;
  }

  Future<void> _renumberSets(String exerciseId) async {
    final sets = await _setRows(exerciseId);
    for (var i = 0; i < sets.length; i++) {
      if (sets[i].setNumber != i + 1) {
        await (_db.update(_db.exerciseSets)
              ..where((s) => s.id.equals(sets[i].id)))
            .write(ExerciseSetsCompanion(setNumber: Value(i + 1)));
      }
    }
  }

  Future<void> _renumberExercises(String workoutId) async {
    final rows = await _exerciseRows(workoutId);
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].orderIndex != i) {
        await (_db.update(_db.exercises)..where((e) => e.id.equals(rows[i].id)))
            .write(ExercisesCompanion(orderIndex: Value(i)));
      }
    }
  }

  static int _repsInRange(int reps) {
    if (reps < 0 || reps > SessionLimits.maxReps) {
      throw ArgumentError.value(
        reps,
        'reps',
        'outside 0–${SessionLimits.maxReps}',
      );
    }
    return reps;
  }

  static double _weightInRange(double kg) {
    if (kg.isNaN || kg < 0 || kg > SessionLimits.maxWeightKg) {
      throw ArgumentError.value(
        kg,
        'weightKg',
        'outside 0–${SessionLimits.maxWeightKg} kg',
      );
    }
    return kg;
  }

  static String _clip(String name) {
    final trimmed = name.trim();
    return trimmed.length <= SessionLimits.nameLength
        ? trimmed
        : trimmed.substring(0, SessionLimits.nameLength);
  }

  static String _defaultName(DateTime at) {
    if (at.hour < 12) return 'Morning session';
    if (at.hour < 17) return 'Afternoon session';
    return 'Evening session';
  }
}
