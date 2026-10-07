import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/coach_planner.dart';
import '../domain/plan_intake.dart';
import '../domain/standing_plan.dart';
import '../domain/standing_plan_store.dart';

/// The standing plan, in `lift.plans` and `lift.plan_slots`.
///
/// Two tables, both scoped by RLS to the caller — `own_plans` and
/// `own_plan_slots` — so nothing here filters by user for safety. A plan is
/// written by `lift.replace_plan`, which runs as the caller and takes
/// `user_id` from the session rather than from anything sent.
class SupabaseStandingPlanStore implements StandingPlanStore {
  SupabaseStandingPlanStore(this._client);

  final SupabaseClient _client;

  SupabaseQuerySchema get _lift => _client.schema('lift');

  @override
  Future<StandingPlan?> active() async {
    // Signed out has no plan. Asking anyway is a 401 that reads as "no
    // signal", and the cached store answers that with the last plan on the
    // phone, which may be somebody else's.
    if (_client.auth.currentUser == null) return null;
    try {
      final rows = await _lift
          .from('plans')
          .select(
            'id, split, day_order, rationale, available_weekdays, started_at',
          )
          .eq('status', 'active')
          .limit(1);
      if (rows.isEmpty) return null;

      final plan = rows.first;
      final slots = await _lift
          .from('plan_slots')
          .select(
            'id, day, sort_order, role, movement, is_main, sets, reps, '
            'sessions_at_same_top, last_top_kg, last_top_reps',
          )
          .eq('plan_id', plan['id'] as String)
          // The unique index is (plan_id, day, sort_order), so this is the
          // order the plan was written in rather than whatever the planner
          // happened to return.
          .order('day')
          .order('sort_order');

      return _hydrate(plan, slots);
    } on PlanException {
      rethrow;
    } on Object {
      throw const PlanException(PlanFailure.unavailable);
    }
  }

  @override
  Future<StandingPlan> replace(StandingPlan plan, {PlanIntake? intake}) async {
    if (_client.auth.currentUser == null) {
      throw const PlanException(PlanFailure.signedOut);
    }

    // **One call, one transaction** (`lift.replace_plan`, 20261007201224).
    //
    // This was three requests: supersede the live plan, insert the new one,
    // insert its slots. When the slots failed -- which they did, every time,
    // for seven weeks, on columns the database did not have -- the lifter was
    // left with a live plan holding nothing and their old one superseded. The
    // function supersedes, inserts and writes every slot, or does none of it.
    // `user_id` is the caller's, set by the function; RLS still applies.
    final rows = <Map<String, Object?>>[
      for (final day in plan.slots.entries)
        for (final (i, s) in day.value.indexed)
          <String, Object?>{
            'id': s.id,
            'day': day.key,
            'sort_order': i,
            'role': s.role,
            'movement': s.movement,
            'is_main': s.isMain,
            'sets': s.sets,
            'reps': s.reps,
            'sessions_at_same_top': s.sessionsAtSameTop,
            'last_top_kg': s.lastTopKg,
            'last_top_reps': s.lastTopReps,
          },
    ];

    try {
      await _lift.rpc(
        'replace_plan',
        params: <String, Object?>{
          'plan': <String, Object?>{
            'id': plan.id,
            'split': plan.name,
            'day_order': plan.dayOrder,
            'rationale': plan.rationale,
            'days_per_week': plan.weekdays.length,
            'available_weekdays': plan.weekdays,
            'started_at': (plan.startedAt ?? DateTime.now())
                .toIso8601String()
                .split('T')
                .first,
            // What they told the coach, kept with the plan it produced.
            if (intake != null) ...<String, Object?>{
              'goal': intake.goal,
              'equipment': intake.equipment,
              'injury_notes': intake.injuryNotes,
              'intake': intake.toJson(),
            },
          },
          'slots': rows,
        },
      );
      return plan;
    } on Object catch (e) {
      throw PlanException(_writeFailure(e));
    }
  }

  /// A refusal from the database, an expired session, or no answer at all.
  ///
  /// **Kept apart on purpose.** All three used to read "Could not reach your
  /// coach", which is how a schema fault spent seven weeks looking like bad
  /// signal: nobody checks a column when the app says check your connection.
  static PlanFailure _writeFailure(Object e) => switch (e) {
    PlanException(:final failure) => failure,
    // A session that has run out, or a caller the function does not know.
    PostgrestException(:final code)
        when code == '42501' || code == 'PGRST301' || code == 'PGRST302' =>
      PlanFailure.signedOut,
    PostgrestException() => PlanFailure.notSaved,
    _ => PlanFailure.unavailable,
  };

  @override
  Future<void> recordResult(
    String slotId, {
    required double topKg,
    required int reps,
    required bool improved,
  }) async {
    try {
      if (improved) {
        await _lift
            .from('plan_slots')
            .update(<String, Object?>{
              'last_top_kg': topKg,
              'last_top_reps': reps,
              'sessions_at_same_top': 0,
            })
            .eq('id', slotId);
        return;
      }

      // Incrementing needs the current value, and reading it back first is a
      // race between two devices finishing the same session. It is a benign
      // one -- the worst outcome is a rotation prompt arriving a session late
      // -- and the alternative is an RPC for a counter, which is more machinery
      // than the failure justifies.
      final rows = await _lift
          .from('plan_slots')
          .select('sessions_at_same_top')
          .eq('id', slotId)
          .limit(1);
      final held = rows.isEmpty
          ? 0
          : (rows.first['sessions_at_same_top'] as num?)?.toInt() ?? 0;

      await _lift
          .from('plan_slots')
          .update(<String, Object?>{
            'last_top_kg': topKg,
            'last_top_reps': reps,
            'sessions_at_same_top': held + 1,
          })
          .eq('id', slotId);
    } on Object {
      throw const PlanException(PlanFailure.unavailable);
    }
  }

  StandingPlan _hydrate(
    Map<String, Object?> plan,
    List<Map<String, Object?>> slots,
  ) {
    final byDay = <String, List<MovementSlot>>{};
    for (final r in slots) {
      final day = r['day'] as String? ?? '';
      if (day.isEmpty) continue;
      (byDay[day] ??= <MovementSlot>[]).add(
        MovementSlot(
          id: r['id'] as String,
          role: r['role'] as String? ?? '',
          movement: r['movement'] as String? ?? '',
          isMain: r['is_main'] as bool? ?? false,
          // Falling back rather than throwing: a row written before the
          // columns existed is a plan that still renders, and the next save
          // corrects it.
          sets: (r['sets'] as num?)?.toInt() ?? 3,
          reps: (r['reps'] as num?)?.toInt() ?? 10,
          sessionsAtSameTop: (r['sessions_at_same_top'] as num?)?.toInt() ?? 0,
          lastTopKg: (r['last_top_kg'] as num?)?.toDouble(),
          lastTopReps: (r['last_top_reps'] as num?)?.toInt(),
        ),
      );
    }

    return StandingPlan(
      id: plan['id'] as String,
      name: plan['split'] as String? ?? 'Your plan',
      dayOrder: <String>[
        for (final d in (plan['day_order'] as List?) ?? const [])
          if (d is String) d,
      ],
      rationale: plan['rationale'] as String?,
      weekdays: <int>[
        for (final d in (plan['available_weekdays'] as List?) ?? const [])
          if (d is num) d.toInt(),
      ],
      startedAt: DateTime.tryParse(plan['started_at'] as String? ?? ''),
      slots: byDay,
    );
  }
}
