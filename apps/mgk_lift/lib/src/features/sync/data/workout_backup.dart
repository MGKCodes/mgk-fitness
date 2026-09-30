import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/backup_remote.dart';
import '../domain/sync_status.dart';
import 'sync_queue.dart';

/// Backup and cross-device restore for the training log **and the library**.
///
/// **The local database is the authority and this is a mirror of it**, not the
/// other way round. A set is logged standing at a rack in a basement; the
/// network is optional and never on the path of a write. Everything here runs
/// after the fact, at checkpoints, and can fail without anybody losing
/// anything.
///
/// ## What goes up
///
/// Finished sessions, saved workouts, and deletions of either — see
/// [SyncQueue.dirtyWorkouts]. Never a session in progress. A saved workout goes
/// up as a template with no date, which is what `workouts_template_has_no_date`
/// requires; until 2026-09-29 none went up at all, and a library did not
/// survive losing the phone.
///
/// ## One workout, one request
///
/// Each workout is sent whole — row, movements, sets — and the server writes it
/// in one transaction (`lift.save_workout`). It was four requests, and a drop
/// between deleting the old movements and inserting the new left the server
/// copy empty until the next run.
///
/// ## One bad row cannot block the rest
///
/// A workout the server **refuses** is set aside with the reason and the run
/// carries on; it is tried again once it is edited. A failure that is not about
/// the row — no connection, a server error, a lapsed sign-in — stops the run,
/// because every row behind it would fail the same way.
///
/// ## Change detection
///
/// `updatedAt > syncedAt` on the workout, and nothing else. `lift.exercises` and
/// `lift.sets` carry no clock and no tombstone of their own, so the workout is
/// the unit of change: when one is dirty its children are replaced wholesale
/// rather than diffed.
///
/// ## Conflicts
///
/// Last write wins, by `updatedAt`. Two devices editing the same past session
/// is rare enough, and the alternative — merging set-by-set — invents a lifter's
/// intent from timestamps. If it happens, the newer edit stands.
class WorkoutBackup implements BackupService {
  WorkoutBackup(this._db, this._remote, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now,
      _queue = SyncQueue(_db, clock: clock);

  final AppDatabase _db;
  final BackupRemote _remote;
  final DateTime Function() _now;

  /// The dirty-tracking rules, split out so they can be tested without a
  /// network. See [SyncQueue].
  final SyncQueue _queue;

  @override
  Future<SyncPending> pending() => _queue.pending();

  /// Pushes local changes, then pulls remote ones.
  ///
  /// Push first, deliberately. If both directions have work, the local device
  /// is where the lifter just was, and pulling first would let a stale remote
  /// copy win a last-write-wins comparison against an edit made seconds ago.
  @override
  Future<SyncReport> run() async {
    if (_remote.userId == null) return const SyncReport.signedOut();

    var pushed = 0;
    var rejected = 0;
    try {
      for (final row in await _queue.dirtyWorkouts()) {
        final payload = await _payloadFor(row);
        try {
          await _remote.save(payload);
        } on BackupFailure catch (failure) {
          if (failure.problem == BackupProblem.rejected) {
            await _queue.markRejected(row.id, failure.detail);
            rejected++;
            continue;
          }
          await _queue.markAttempt(row.id);
          rethrow;
        }
        await _queue.markSynced(row.id, row.updatedAt);
        pushed++;
      }

      final pulled = await _pull();
      await _queue.setLastRun(_now());
      return SyncReport(
        outcome: pushed == 0 && pulled == 0
            ? SyncOutcome.upToDate
            : SyncOutcome.synced,
        pushed: pushed,
        pulled: pulled,
        rejected: rejected,
        at: _now(),
      );
    } on BackupFailure catch (failure) {
      return SyncReport.unavailable(failure.detail, problem: failure.problem);
    } on Object catch (e) {
      // Anything the remote did not classify. Nothing is lost; rows stay dirty
      // and the next checkpoint tries again.
      return SyncReport.unavailable(e.toString());
    }
  }

  /// One workout as the server takes it: the row, then its movements in order
  /// with their sets.
  Future<Map<String, Object?>> _payloadFor(WorkoutRow w) async {
    final exercises =
        await (_db.select(_db.exercises)
              ..where((e) => e.workoutId.equals(w.id))
              ..orderBy([(e) => OrderingTerm.asc(e.orderIndex)]))
            .get();
    final sets = exercises.isEmpty
        ? const <SetRow>[]
        : await (_db.select(_db.exerciseSets)
                ..where((s) => s.exerciseId.isIn(exercises.map((e) => e.id)))
                ..orderBy([(s) => OrderingTerm.asc(s.setNumber)]))
              .get();

    return <String, Object?>{
      'id': w.id,
      'name': w.name,
      // A template has no date, and the server's constraint says so. Its local
      // `startedAt` is only there because the column is not nullable.
      'started_at': w.isTemplate ? null : w.startedAt.toUtc().toIso8601String(),
      'duration_s': w.durationS,
      'notes': w.notes,
      'is_template': w.isTemplate,
      'template_id': w.isTemplate ? null : w.templateId,
      'premade_id': w.isTemplate ? w.premadeId : null,
      'deleted_at': w.deletedAt?.toUtc().toIso8601String(),
      'updated_at': w.updatedAt.toUtc().toIso8601String(),
      'exercises': <Map<String, Object?>>[
        for (final e in exercises)
          <String, Object?>{
            'id': e.id,
            'name': e.name,
            'order_index': e.orderIndex,
            'notes': e.notes,
            'cardio_mode': e.cardioMode,
            'sets': <Map<String, Object?>>[
              for (final s in sets)
                if (s.exerciseId == e.id)
                  <String, Object?>{
                    'id': s.id,
                    'set_number': s.setNumber,
                    'reps': s.reps,
                    'weight_kg': s.weightKg,
                    'is_completed': s.isCompleted,
                    // Without it every warm-up came back a working set and
                    // inflated volume on restore.
                    'set_type': s.setType,
                    'duration_s': s.durationS,
                    'distance_m': s.distanceM,
                  },
            ],
          },
      ],
    };
  }

  /// Pulls everything changed since the last successful pull.
  ///
  /// A row that is dirty locally is skipped: it has an edit that has not been
  /// pushed yet, and overwriting it here would lose the newer change. It gets
  /// resolved on the next run, after the push.
  Future<int> _pull() async {
    final rows = await _remote.changedSince(await _queue.lastPull());

    var applied = 0;
    DateTime? newest;
    for (final raw in rows) {
      final id = raw['id'] as String;
      final stamped = _parse(raw['updated_at']);
      if (stamped != null && (newest == null || stamped.isAfter(newest))) {
        newest = stamped;
      }
      final local = await (_db.select(
        _db.workouts,
      )..where((w) => w.id.equals(id))).getSingleOrNull();

      if (local != null && SyncQueue.isDirty(local)) continue;

      await _applyRemote(raw);
      applied++;
    }

    // The newest server time seen, not this phone's time — see
    // [SyncQueue.lastPullKey]. Nothing seen, nothing moves.
    if (newest != null) await _queue.setLastPull(newest);
    return applied;
  }

  Future<void> _applyRemote(Map<String, dynamic> raw) async {
    final id = raw['id'] as String;
    final now = _now();

    await _db.transaction(() async {
      // Children first, and by delete-then-insert for the same reason the push
      // does it: nothing on the remote children says which of them went away.
      await (_db.delete(
        _db.exercises,
      )..where((e) => e.workoutId.equals(id))).go();

      final durationS = (raw['duration_s'] as num?)?.toInt() ?? 0;
      final createdAt = _parse(raw['created_at']) ?? now;
      final isTemplate = raw['is_template'] as bool? ?? false;

      // **`started_at` is nullable remotely and is null on every template.**
      // This used to be an unguarded `as String`, which threw on the first
      // template the pull met and aborted the run — and there have been 47 of
      // them in `lift.workouts` since the Liftio baseline, so the only reason
      // it never fired is that nothing in this app had ever asked for them.
      //
      // Locally the column is not nullable, so a template borrows its
      // `createdAt`. Nothing reads a template's `startedAt` as a date; see
      // `Workouts.isTemplate`.
      final startedRaw = raw['started_at'] as String?;
      final started = startedRaw == null
          ? createdAt
          : DateTime.parse(startedRaw).toLocal();

      // **A companion with every value stated, not a row object.** Drift
      // inserts a row object with its nulls left out, so on conflict a null
      // from the server never reached the local row: a workout restored on
      // another device stayed deleted here, and a note cleared there stayed.
      // The two left absent are local-only and must survive the pull.
      await _db
          .into(_db.workouts)
          .insertOnConflictUpdate(
            WorkoutsCompanion(
              id: Value(id),
              name: Value(raw['name'] as String? ?? 'Session'),
              startedAt: Value(started),
              // The remote schema has no `ended_at`; a finished session is one
              // with a duration, so it is reconstructed rather than stored.
              // Only finished sessions are ever uploaded, so this is total.
              //
              // A template never ended, because it never happened. Giving it
              // a reconstructed end date would file somebody's saved routine
              // into their training log as a workout they did.
              endedAt: Value(
                isTemplate ? null : started.add(Duration(seconds: durationS)),
              ),
              durationS: Value(durationS),
              notes: Value(raw['notes'] as String?),
              isTemplate: Value(isTemplate),
              templateId: Value(raw['template_id'] as String?),
              // Which of the fifteen a saved workout was added from, for the
              // browser to mark. Liftio wrote this column locally and never
              // uploaded it, so it is null on everything already up there —
              // an old library comes back unattributed rather than not at all.
              premadeId: Value(raw['premade_id'] as String?),
              deletedAt: Value(_parse(raw['deleted_at'])),
              createdAt: Value(createdAt),
              // **This phone's clock, both of them**, not the server's
              // `updated_at`. Dirty-tracking compares these two, and every
              // local edit stamps this phone's time; a server stamp here made
              // a row on a phone running behind look edited, so it went up
              // again on every run, forever.
              updatedAt: Value(now),
              syncedAt: Value(now),
              syncError: const Value(null),
              syncAttempts: const Value(0),
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
