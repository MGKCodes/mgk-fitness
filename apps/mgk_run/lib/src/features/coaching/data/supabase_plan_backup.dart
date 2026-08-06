import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/session_status.dart';
import '../domain/stored_plan.dart';
import '../domain/training_plan.dart';
import 'plan_backup_rows.dart';
import 'plan_mappers.dart';
import 'plan_store.dart';

/// Mirrors the plan to the shared Supabase platform (the `runSchema` schema) so it
/// survives losing the phone.
///
/// This is a **backup, not the source of truth** (CLAUDE.md rule 1). It is
/// push-only and never on a read path: [PlanRepository] calls it after the local
/// write has already committed, and treats any failure as a no-op.
///
/// RLS scopes every table to `auth.uid()`, so no query here filters by user —
/// but the rows still carry `user_id` because the policies check it on write.
///
/// The rows themselves live in `plan_backup_rows.dart` as pure functions, so
/// the column set is something a test can hold up against the schema. It was
/// inline here while two column bugs kept every push failing silently for a
/// year; see that file.
class SupabasePlanBackup implements PlanBackup {
  SupabasePlanBackup({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  SupabaseQuerySchema get _run => _client.schema('run');

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw StateError('cannot back up a plan while signed out');
    }
    return id;
  }

  @override
  Future<void> pushPlan(StoredPlan plan) async {
    final userId = _userId;

    // Only one plan per runner may be active (enforced by a partial unique
    // index), so retire the previous one before inserting this one.
    await _run
        .from('plans')
        .update(<String, dynamic>{'status': 'superseded'})
        .eq('status', 'active')
        .neq('id', plan.id);

    await _run.from('plans').upsert(planRow(plan, userId));
    await _run.from('plan_weeks').upsert(weekRows(plan, userId));
    // Kept in step with the plan, and last: it is the least important of the
    // three, and it was the one whose unknown column used to take the other two
    // down with it.
    await _run
        .from('runner_profiles')
        .upsert(profileRow(plan, userId, DateTime.now()));
  }

  @override
  Future<void> pushWeek(StoredPlan plan, TrainingWeek week) async {
    final rows = sessionRows(plan, week, _userId);
    if (rows.isEmpty) return;
    // Upsert rather than delete-and-insert: a status already recorded against a
    // session must not be lost, and these columns are left untouched.
    await _run.from('plan_sessions').upsert(rows);
  }

  @override
  Future<void> pushStatus({
    required StoredPlan plan,
    required int weekIndex,
    required int weekday,
    required DateTime date,
    required SessionStatus status,
  }) async {
    await _run
        .from('plan_sessions')
        .update(<String, dynamic>{
          'status': sessionStatusToWire(status),
          'status_at': status == SessionStatus.planned
              ? null
              : DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', sessionId(plan.id, weekIndex, weekday));
  }
}
