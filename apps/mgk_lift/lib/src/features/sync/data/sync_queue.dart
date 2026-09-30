import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/sync_status.dart';

/// Which local rows still need to go up.
///
/// Split out from the uploader so the rule can be tested without a network or a
/// Supabase client — the rule is the part that decides whether a lifter's
/// training is safe, and it should not need a server to prove.
class SyncQueue {
  SyncQueue(this._db, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _now;

  /// The newest server `updated_at` a pull has seen — **the server's clock,
  /// never this phone's**. It was set to the phone's time after each pull and
  /// compared with the server's timestamps; on a phone running ahead, anything
  /// written in that gap was never pulled.
  static const String lastPullKey = 'lift.workouts.pulledAt';

  /// When the last run finished — this phone's clock, for "last backed up".
  static const String lastRunKey = 'lift.workouts.backedUpAt';

  /// What goes up on the next run, oldest change first.
  ///
  /// - **A finished session, or a saved workout.** A session in progress is
  ///   device-local: the remote schema cannot express one
  ///   (`workouts_template_has_no_date` demands a `started_at` on any
  ///   non-template), and the activity trigger would file a half-logged session
  ///   into the cross-app feed the moment it landed. A saved workout goes up as
  ///   a template, with no date at all — which is what that constraint asks of
  ///   one. *Until 2026-09-29 saved workouts never went up, and a library did
  ///   not survive losing the phone.*
  /// - **Changed since it last went up:** `syncedAt` null, or `updatedAt`
  ///   later. No separate outbox to fall out of step with the rows.
  /// - **Not deleted before it ever went up.** There is nothing to tell the
  ///   server about a row it never had.
  /// - **Not refused and unchanged since.** A row the server refused is tried
  ///   again only after it is edited — the same row gets the same answer, and
  ///   retried in a loop it would sit at the front of every run.
  Future<List<WorkoutRow>> dirtyWorkouts() =>
      (_db.select(_db.workouts)
            ..where(
              (w) =>
                  (w.endedAt.isNotNull() | w.isTemplate.equals(true)) &
                  _changed(w) &
                  _notDeletedUnsent(w) &
                  (w.syncError.isNull() |
                      w.lastSyncAttemptAt.isNull() |
                      w.updatedAt.isBiggerThan(w.lastSyncAttemptAt)),
            )
            ..orderBy([(w) => OrderingTerm.asc(w.updatedAt)]))
          .get();

  /// Refused by the server, and not edited since — the rows waiting on the
  /// lifter rather than on the network.
  Future<List<WorkoutRow>> rejectedWorkouts() =>
      (_db.select(_db.workouts)..where(
            (w) =>
                (w.endedAt.isNotNull() | w.isTemplate.equals(true)) &
                _changed(w) &
                _notDeletedUnsent(w) &
                w.syncError.isNotNull() &
                w.lastSyncAttemptAt.isNotNull() &
                w.updatedAt.isSmallerOrEqual(w.lastSyncAttemptAt),
          ))
          .get();

  static Expression<bool> _changed($WorkoutsTable w) =>
      w.syncedAt.isNull() | w.updatedAt.isBiggerThan(w.syncedAt);

  static Expression<bool> _notDeletedUnsent($WorkoutsTable w) =>
      w.deletedAt.isNull() | w.syncedAt.isNotNull();

  Future<SyncPending> pending() async {
    final waiting = await dirtyWorkouts();
    final refused = await rejectedWorkouts();
    return SyncPending(
      workouts: waiting.where((w) => !w.isTemplate).length,
      savedWorkouts: waiting.where((w) => w.isTemplate).length,
      lastSyncedAt: await lastRun(),
      waitingIds: <String>{for (final w in waiting) w.id},
      rejected: <RejectedWorkout>[
        for (final w in refused)
          RejectedWorkout(
            id: w.id,
            name: w.name,
            isTemplate: w.isTemplate,
            detail: w.syncError ?? '',
          ),
      ],
    );
  }

  /// Marks a workout as uploaded **as of [version]** — the `updatedAt` of the
  /// copy that was sent — without touching `updatedAt` itself, which would
  /// make it dirty again at once: a sync that never converges.
  ///
  /// The version, not the time of the reply. An edit made while the upload was
  /// in flight has a later `updatedAt` than the copy that went, so it stays
  /// dirty and goes on the next run; stamping "now" here marked that edit as
  /// sent when it never was.
  Future<void> markSynced(String id, DateTime version) =>
      (_db.update(_db.workouts)..where((w) => w.id.equals(id))).write(
        WorkoutsCompanion(
          syncedAt: Value(version),
          syncError: const Value(null),
          syncAttempts: const Value(0),
          lastSyncAttemptAt: Value(_now()),
        ),
      );

  /// The server refused this row. Kept with its reason, and left alone until
  /// the lifter edits it. `updatedAt` untouched, for the same reason as above.
  Future<void> markRejected(String id, String detail) =>
      (_db.update(_db.workouts)..where((w) => w.id.equals(id))).write(
        WorkoutsCompanion.custom(
          syncError: Variable<String>(detail),
          syncAttempts: _db.workouts.syncAttempts + const Constant(1),
          lastSyncAttemptAt: Variable<DateTime>(_now()),
        ),
      );

  /// An attempt that failed for a reason that was not this row — no
  /// connection, a server error. Counted, and **any old refusal cleared**: the
  /// row is in the queue again, and a stale refusal would take it back out.
  Future<void> markAttempt(String id) =>
      (_db.update(_db.workouts)..where((w) => w.id.equals(id))).write(
        WorkoutsCompanion.custom(
          syncError: const Constant<String>(null),
          syncAttempts: _db.workouts.syncAttempts + const Constant(1),
          lastSyncAttemptAt: Variable<DateTime>(_now()),
        ),
      );

  Future<DateTime?> lastPull() => _meta(lastPullKey);

  Future<void> setLastPull(DateTime at) => _setMeta(lastPullKey, at);

  Future<DateTime?> lastRun() => _meta(lastRunKey);

  Future<void> setLastRun(DateTime at) => _setMeta(lastRunKey, at);

  Future<DateTime?> _meta(String key) async {
    final row = await (_db.select(
      _db.syncMeta,
    )..where((m) => m.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> _setMeta(String key, DateTime at) => _db
      .into(_db.syncMeta)
      .insertOnConflictUpdate(SyncMetaRow(key: key, value: at));

  /// Whether a row has a local edit that has not been pushed.
  ///
  /// Used by the pull to leave it alone: overwriting it with the server's copy
  /// would discard an edit made seconds ago in favour of one made yesterday.
  static bool isDirty(WorkoutRow row) =>
      row.syncedAt == null || row.updatedAt.isAfter(row.syncedAt!);
}
