import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/plan_generator.dart';
import '../domain/standing_plan.dart';
import '../domain/standing_plan_store.dart';

/// The standing plan, in `lift.plans` and `lift.plan_slots`.
///
/// Two tables, both scoped by RLS to the caller — `own_plans` and
/// `own_plan_slots` — so nothing here filters by user for safety. The
/// `user_id` in the writes is there because the column is `not null` and the
/// policy checks it, not because it is the security boundary.
class SupabaseStandingPlanStore implements StandingPlanStore {
  SupabaseStandingPlanStore(this._client);

  final SupabaseClient _client;

  SupabaseQuerySchema get _lift => _client.schema('lift');

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const PlanException(PlanFailure.signedOut);
    return id;
  }

  @override
  Future<StandingPlan?> active() async {
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
            'id, day, sort_order, role, movement, is_main, '
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
  Future<StandingPlan> replace(StandingPlan plan) async {
    final userId = _userId;
    try {
      // Supersede first, then insert. The other order trips the partial unique
      // index on (user_id) where status = 'active' -- which is the index doing
      // its job, but it would surface as a write failure rather than as the
      // plan being replaced.
      await _lift
          .from('plans')
          .update(<String, Object?>{'status': 'superseded'})
          .eq('status', 'active');

      await _lift.from('plans').insert(<String, Object?>{
        'id': plan.id,
        'user_id': userId,
        'status': 'active',
        'split': plan.name,
        'day_order': plan.dayOrder,
        'rationale': plan.rationale,
        'days_per_week': plan.weekdays.length,
        'available_weekdays': plan.weekdays,
        'started_at': (plan.startedAt ?? DateTime.now())
            .toIso8601String()
            .split('T')
            .first,
      });

      final rows = <Map<String, Object?>>[
        for (final day in plan.slots.entries)
          for (final (i, s) in day.value.indexed)
            <String, Object?>{
              'id': s.id,
              'plan_id': plan.id,
              'user_id': userId,
              'day': day.key,
              'sort_order': i,
              'role': s.role,
              'movement': s.movement,
              'is_main': s.isMain,
              'sessions_at_same_top': s.sessionsAtSameTop,
              'last_top_kg': s.lastTopKg,
              'last_top_reps': s.lastTopReps,
            },
      ];
      if (rows.isNotEmpty) await _lift.from('plan_slots').insert(rows);

      return plan;
    } on PlanException {
      rethrow;
    } on Object {
      throw const PlanException(PlanFailure.unavailable);
    }
  }

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
