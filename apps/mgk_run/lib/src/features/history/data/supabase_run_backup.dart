import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../../core/supabase/paged_select.dart';
import 'run_backup.dart';

/// Mirrors runs to the shared Supabase platform (the `run` schema) so they
/// survive losing the phone.
///
/// This closes a hole rather than adding a feature. Plans, coach memory,
/// profiles and settings all had a mirror; runs never did, while History read
/// from Supabase — so a recorded run was written to Drift, pushed nowhere, and
/// never appeared in the log. The only runs anyone saw were seeded ones.
///
/// **That second half is no longer true, and the difference matters here.** The
/// log is read from Drift now (ADR-0023), so this is a mirror and only a mirror:
/// nothing a runner can see on their own phone depends on a push landing. It
/// was carrying two jobs — surviving a lost phone, and making runs visible at
/// all — and it is left with the one it was built for.
///
/// A **backup, not the source of truth** (CLAUDE.md rule 1), and the same
/// contract as [SupabasePlanBackup]: push-only, never on a read path, called
/// after the local write has already committed, and every failure is a no-op
/// for the caller. A run that fails to push is still a run on the phone — and
/// the failure is recorded by `ReportedRunBackup` on the way past, because a
/// no-op for the caller should not mean invisible to everybody.
///
/// RLS scopes every table to `auth.uid()`, so nothing here filters by user —
/// but rows carry `user_id` because the policies check it on write.
class SupabaseRunBackup implements RunBackup {
  SupabaseRunBackup({required AppDatabase db, SupabaseClient? client})
    : _db = db,
      _client = client ?? Supabase.instance.client;

  final AppDatabase _db;
  final SupabaseClient _client;

  SupabaseQuerySchema get _run => _client.schema('run');

  String? get _userId => _client.auth.currentUser?.id;

  /// How many trace points to send at once.
  ///
  /// A run is a point every few seconds, so an hour is on the order of a
  /// thousand rows and a long trail run several thousand. One request with all
  /// of them is a payload big enough to time out on a phone signal, and a
  /// timeout would lose the whole trace rather than part of it.
  static const int _pointBatch = 500;

  /// Pushes one run and everything belonging to it.
  ///
  /// Returns true when the run itself reached Supabase. The trace is pushed
  /// after and separately: a run whose summary is safe but whose points failed
  /// is a far better outcome than neither, and the summary is what the log,
  /// the standing and the coach's brief are all built from.
  @override
  Future<bool> pushRun(String runId) async {
    final userId = _userId;
    if (userId == null) return false;

    final row = await _db.runById(runId);
    if (row == null) return false;

    await _run.from('runs').upsert(<String, dynamic>{
      'id': row.id,
      'user_id': userId,
      'started_at': row.startedAt.toUtc().toIso8601String(),
      'duration_s': row.durationS,
      'distance_m': row.distanceM,
      'avg_pace_s_per_km': row.avgPaceSPerKm,
      'elevation_gain_m': row.elevationGainM,
      'avg_hr': row.avgHr,
      'max_hr': row.maxHr,
      'cadence': row.cadence,
      'calories_est': row.caloriesEst,
      'source': row.source,
      'type': row.type,
      'external_id': row.externalId,
      'rpe': row.rpe,
      'notes': row.notes,
      'session_id': row.sessionId,
    });
    return true;
  }

  /// Pushes a run's trace, in batches. Safe to repeat: the primary key is
  /// `(run_id, seq)`, so a re-push of a point already there is a no-op rather
  /// than a duplicate.
  @override
  Future<void> pushTrace(String runId) async {
    final userId = _userId;
    if (userId == null) return;

    final points = await _db.pointsForRun(runId);
    for (var i = 0; i < points.length; i += _pointBatch) {
      final slice = points.skip(i).take(_pointBatch);
      await _run.from('run_points').upsert(<Map<String, dynamic>>[
        for (final p in slice)
          <String, dynamic>{
            'run_id': runId,
            'user_id': userId,
            'seq': p.seq,
            'lat': p.lat,
            'lng': p.lng,
            'altitude_m': p.altitudeM,
            'accuracy_m': p.accuracyM,
            'recorded_at': p.timestamp.toUtc().toIso8601String(),
          },
      ]);
    }

    final splits = await _db.splitsForRun(runId);
    if (splits.isEmpty) return;
    await _run.from('run_splits').upsert(<Map<String, dynamic>>[
      for (final s in splits)
        <String, dynamic>{
          'run_id': runId,
          'user_id': userId,
          'seq': s.seq,
          'distance_m': s.distanceM,
          'duration_s': s.durationS,
          'avg_hr': s.avgHr,
        },
    ]);
  }

  /// Sends every local run the backup does not already hold.
  ///
  /// Compares ids rather than tracking a `pushed_at` per row. A column would
  /// be one more piece of state to keep true, and it would still be wrong for
  /// the case that matters most — runs recorded before any of this existed,
  /// which no local flag could know about. Ids are cheap: one paged select of
  /// a single column, and the answer is exact rather than inferred.
  ///
  /// A run the server already has is left alone, including its trace. Diffing
  /// points per run would cost a request each to find a case that only arises
  /// when a push failed halfway; those repair themselves on the next edit.
  @override
  Future<int> backfill() async {
    if (_userId == null) return 0;
    final local = await _db.allRuns();
    if (local.isEmpty) return 0;

    final remote = await fetchAllPages(
      (f, t) => _run.from('runs').select('id').range(f, t),
    );
    final held = remote.map((r) => r['id'] as String).toSet();

    var sent = 0;
    for (final run in local) {
      if (held.contains(run.id)) continue;
      // The whole run: a row absent from the server has no trace there either.
      if (await pushRun(run.id)) {
        await pushTrace(run.id);
        sent++;
      }
    }
    return sent;
  }

  /// Removes a run and its trace, for a run the runner deleted locally.
  ///
  /// Without this, deleting a run on the phone would leave it in the backup and
  /// it would reappear in the log on the next read — the log is read from here.
  @override
  Future<void> deleteRun(String runId) async {
    if (_userId == null) return;
    // Points and splits cascade on the foreign key, so the run is enough.
    await _run.from('runs').delete().eq('id', runId);
  }
}
