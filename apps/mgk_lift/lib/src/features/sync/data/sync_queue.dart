import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/sync_status.dart';

/// Which local rows still need to go up.
///
/// Split out from the uploader so the rule can be tested without a network or a
/// Supabase client — the rule is the part that decides whether a lifter's
/// training is safe, and it should not need a server to prove.
class SyncQueue {
  SyncQueue(this._db);

  final AppDatabase _db;

  static const String lastPullKey = 'lift.workouts.pulledAt';

  /// Finished sessions that have changed since they were last uploaded.
  ///
  /// Three rules, and all of them matter:
  ///
  /// - **`endedAt` is not null.** A session in progress is device-local. The
  ///   remote schema cannot express one — `workouts_template_has_no_date`
  ///   demands a `started_at` on any non-template, and the activity trigger
  ///   would file a half-logged session into the cross-app feed the moment it
  ///   landed.
  /// - **`isTemplate` is false.** A saved workout goes up nowhere *yet*, and
  ///   this says so outright rather than leaving it to fall out of the rule
  ///   above. It would already be excluded — a template's `endedAt` is null
  ///   forever — but that is a coincidence of two unrelated decisions, and the
  ///   day somebody gives templates an end date to satisfy a different query
  ///   they would start uploading with a `started_at` the remote constraint
  ///   forbids. See the class comment on `SupabaseSync` for why the upload of
  ///   a template is not written yet.
  /// - **`syncedAt` is null, or `updatedAt` is later.** Null means never
  ///   uploaded. Later means edited since. There is no separate outbox to fall
  ///   out of step with the rows it describes.
  Future<List<WorkoutRow>> dirtyWorkouts() =>
      (_db.select(_db.workouts)..where(
            (w) =>
                w.endedAt.isNotNull() &
                w.isTemplate.equals(false) &
                (w.syncedAt.isNull() | w.updatedAt.isBiggerThan(w.syncedAt)),
          ))
          .get();

  Future<SyncPending> pending() async => SyncPending(
    workouts: (await dirtyWorkouts()).length,
    lastSyncedAt: await lastPull(),
  );

  /// Marks a workout as uploaded **without touching `updatedAt`**, which would
  /// immediately make it dirty again — a sync that never converges.
  Future<void> markSynced(String id, DateTime at) =>
      (_db.update(_db.workouts)..where((w) => w.id.equals(id))).write(
        WorkoutsCompanion(syncedAt: Value(at)),
      );

  Future<DateTime?> lastPull() async {
    final row = await (_db.select(
      _db.syncMeta,
    )..where((m) => m.key.equals(lastPullKey))).getSingleOrNull();
    return row?.value;
  }

  Future<void> setLastPull(DateTime at) => _db
      .into(_db.syncMeta)
      .insertOnConflictUpdate(SyncMetaRow(key: lastPullKey, value: at));

  /// Whether a row has a local edit that has not been pushed.
  ///
  /// Used by the pull to leave it alone: overwriting it with the server's copy
  /// would discard an edit made seconds ago in favour of one made yesterday.
  static bool isDirty(WorkoutRow row) =>
      row.syncedAt == null || row.updatedAt.isAfter(row.syncedAt!);
}
