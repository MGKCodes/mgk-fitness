import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/app_database.dart';
import '../domain/sync_status.dart';
import 'sync_queue.dart';

/// Backup and cross-device restore for the training log.
///
/// **The local database is the authority and this is a mirror of it**, not the
/// other way round. A set is logged standing at a rack in a basement; the
/// network is optional and never on the path of a write. Everything here runs
/// after the fact and can fail without anybody losing anything.
///
/// ## What syncs, and what does not
///
/// Only **finished** sessions. A workout with no `endedAt` is one in progress,
/// which is a device-local concept — the remote schema has no way to express it
/// (`workouts_template_has_no_date` requires a `started_at` on anything that is
/// not a template, and the activity trigger would file a half-logged session
/// into the cross-app feed). Uploading it would also mean two devices both
/// think they own the same live session.
///
/// ## Change detection
///
/// `updatedAt > syncedAt` on the workout, and nothing else. `lift.exercises` and
/// `lift.sets` carry no clock and no tombstone of their own, so the workout is
/// the unit of change: when one is dirty its children are replaced wholesale
/// rather than diffed. That is cheap — a session is a few dozen rows — and it
/// removes a whole class of bug where a set deleted locally lingers remotely
/// because nothing recorded that it went.
///
/// ## Conflicts
///
/// Last write wins, by `updatedAt`. Two devices editing the same past session
/// is rare enough, and the alternative — merging set-by-set — invents a lifter's
/// intent from timestamps. If it happens, the newer edit stands.
class SupabaseSync implements BackupService {
  SupabaseSync(this._db, this._client) : _queue = SyncQueue(_db);

  final AppDatabase _db;
  final SupabaseClient _client;

  /// The dirty-tracking rules, split out so they can be tested without a
  /// network. See [SyncQueue].
  final SyncQueue _queue;

  /// `lift` is not the default schema and is not `public`; PostgREST only
  /// serves it because it is listed under Exposed Schemas in the dashboard.
  /// Getting this wrong is a 404 on every call, not a compile error.
  SupabaseQuerySchema get _lift => _client.schema('lift');

  /// What is waiting to go up.
  @override
  Future<SyncPending> pending() => _queue.pending();

  /// Pushes local changes, then pulls remote ones.
  ///
  /// Push first, deliberately. If both directions have work, the local device
  /// is where the lifter just was, and pulling first would let a stale remote
  /// copy win a last-write-wins comparison against an edit made seconds ago.
  @override
  Future<SyncReport> run() async {
    final user = _client.auth.currentUser;
    if (user == null) return const SyncReport.signedOut();

    try {
      final pushed = await _push(user.id);
      final pulled = await _pull(user.id);
      return SyncReport(
        outcome: pushed == 0 && pulled == 0
            ? SyncOutcome.upToDate
            : SyncOutcome.synced,
        pushed: pushed,
        pulled: pulled,
        at: DateTime.now(),
      );
    } on PostgrestException catch (e) {
      // Includes the schema-not-exposed 404, which is a deployment mistake
      // rather than a network one but reaches the lifter the same way.
      return SyncReport.unavailable('${e.code}: ${e.message}');
    } on AuthException catch (e) {
      return SyncReport.unavailable(e.message);
    } on Object catch (e) {
      // Socket failures, DNS, timeouts. Nothing is lost; the rows stay dirty.
      return SyncReport.unavailable(e.toString());
    }
  }

  Future<int> _push(String userId) async {
    final dirty = await _queue.dirtyWorkouts();
    if (dirty.isEmpty) return 0;

    for (final workout in dirty) {
      await _lift.from('workouts').upsert(<String, Object?>{
        'id': workout.id,
        'user_id': userId,
        'name': workout.name,
        'started_at': workout.startedAt.toUtc().toIso8601String(),
        'duration_s': workout.durationS,
        'notes': workout.notes,
        'is_template': workout.isTemplate,
        'template_id': workout.templateId,
        'deleted_at': workout.deletedAt?.toUtc().toIso8601String(),
        'updated_at': workout.updatedAt.toUtc().toIso8601String(),
      });

      // Children replaced wholesale rather than diffed. They have no clock of
      // their own, so there is nothing to diff against; deleting first is also
      // what makes a locally removed set actually disappear from the server.
      await _lift.from('exercises').delete().eq('workout_id', workout.id);

      final exercises = await (_db.select(
        _db.exercises,
      )..where((e) => e.workoutId.equals(workout.id))).get();
      if (exercises.isEmpty) continue;

      await _lift.from('exercises').insert(<Map<String, Object?>>[
        for (final e in exercises)
          <String, Object?>{
            'id': e.id,
            'user_id': userId,
            'workout_id': e.workoutId,
            'name': e.name,
            'order_index': e.orderIndex,
            'notes': e.notes,
            'cardio_mode': e.cardioMode,
          },
      ]);

      final sets = await (_db.select(
        _db.exerciseSets,
      )..where((s) => s.exerciseId.isIn(exercises.map((e) => e.id)))).get();
      if (sets.isNotEmpty) {
        await _lift.from('sets').insert(<Map<String, Object?>>[
          for (final s in sets)
            <String, Object?>{
              'id': s.id,
              'user_id': userId,
              'exercise_id': s.exerciseId,
              'set_number': s.setNumber,
              'reps': s.reps,
              'weight_kg': s.weightKg,
              'is_completed': s.isCompleted,
              // Added by 20260807120000. Without it every warm-up came back a
              // working set and inflated volume on restore.
              'set_type': s.setType,
              'duration_s': s.durationS,
              'distance_m': s.distanceM,
            },
        ]);
      }

      await _queue.markSynced(workout.id, DateTime.now());
    }
    return dirty.length;
  }

  /// Pulls everything changed since the last successful pull.
  ///
  /// A row that is dirty locally is skipped: it has an edit that has not been
  /// pushed yet, and overwriting it here would lose the newer change. It gets
  /// resolved on the next run, after the push.
  Future<int> _pull(String userId) async {
    final since = await _queue.lastPull();
    var query = _lift
        .from('workouts')
        .select('*, exercises(*, sets(*))')
        .eq('user_id', userId);
    if (since != null) {
      query = query.gt('updated_at', since.toUtc().toIso8601String());
    }

    final rows = await query.order('updated_at') as List<dynamic>;
    if (rows.isEmpty) {
      await _queue.setLastPull(DateTime.now());
      return 0;
    }

    var applied = 0;
    for (final raw in rows.cast<Map<String, dynamic>>()) {
      final id = raw['id'] as String;
      final local = await (_db.select(
        _db.workouts,
      )..where((w) => w.id.equals(id))).getSingleOrNull();

      if (local != null && SyncQueue.isDirty(local)) continue;

      await _applyRemote(raw);
      applied++;
    }

    await _queue.setLastPull(DateTime.now());
    return applied;
  }

  Future<void> _applyRemote(Map<String, dynamic> raw) async {
    final id = raw['id'] as String;
    final now = DateTime.now();

    await _db.transaction(() async {
      // Children first, and by delete-then-insert for the same reason the push
      // does it: nothing on the remote children says which of them went away.
      await (_db.delete(
        _db.exercises,
      )..where((e) => e.workoutId.equals(id))).go();

      final started = DateTime.parse(raw['started_at'] as String).toLocal();
      final durationS = (raw['duration_s'] as num?)?.toInt() ?? 0;

      await _db
          .into(_db.workouts)
          .insertOnConflictUpdate(
            WorkoutRow(
              id: id,
              name: raw['name'] as String? ?? 'Session',
              startedAt: started,
              // The remote schema has no `ended_at`; a finished session is one
              // with a duration, so it is reconstructed rather than stored.
              // Only finished sessions are ever uploaded, so this is total.
              endedAt: started.add(Duration(seconds: durationS)),
              durationS: durationS,
              notes: raw['notes'] as String?,
              isTemplate: raw['is_template'] as bool? ?? false,
              templateId: raw['template_id'] as String?,
              deletedAt: _parse(raw['deleted_at']),
              createdAt: _parse(raw['created_at']) ?? now,
              updatedAt: _parse(raw['updated_at']) ?? now,
              syncedAt: now,
            ),
          );

      for (final e
          in (raw['exercises'] as List<dynamic>? ?? <dynamic>[])
              .cast<Map<String, dynamic>>()) {
        await _db
            .into(_db.exercises)
            .insertOnConflictUpdate(
              ExerciseRow(
                id: e['id'] as String,
                workoutId: id,
                name: e['name'] as String? ?? '',
                orderIndex: (e['order_index'] as num?)?.toInt() ?? 0,
                notes: e['notes'] as String?,
                cardioMode: e['cardio_mode'] as String?,
                createdAt: _parse(e['created_at']) ?? now,
              ),
            );

        for (final s
            in (e['sets'] as List<dynamic>? ?? <dynamic>[])
                .cast<Map<String, dynamic>>()) {
          await _db
              .into(_db.exerciseSets)
              .insertOnConflictUpdate(
                SetRow(
                  id: s['id'] as String,
                  exerciseId: e['id'] as String,
                  setNumber: (s['set_number'] as num?)?.toInt() ?? 1,
                  reps: (s['reps'] as num?)?.toInt() ?? 0,
                  weightKg: (s['weight_kg'] as num?)?.toDouble() ?? 0,
                  isCompleted: s['is_completed'] as bool? ?? false,
                  // Anything unrecognised reads as a working set, so a lifter's
                  // totals are only ever reduced deliberately.
                  setType: s['set_type'] as String? ?? 'working',
                  durationS: (s['duration_s'] as num?)?.toInt(),
                  distanceM: (s['distance_m'] as num?)?.toDouble(),
                  createdAt: _parse(s['created_at']) ?? now,
                ),
              );
        }
      }
    });
  }

  static DateTime? _parse(Object? value) =>
      value is String ? DateTime.parse(value).toLocal() : null;
}
