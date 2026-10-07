import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/coach_planner.dart';
import '../domain/plan_intake.dart';
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
    final userId = _userId;

    // **Draft, slots, then live** -- so nothing is half-replaced.
    //
    // This used to supersede the old plan, insert the new one as active, and
    // only then write its slots. When the slots failed -- which they did, every
    // time, for seven weeks, on columns the database did not have -- the lifter
    // was left with a live plan holding nothing, and their old one superseded.
    // A draft is invisible to [active], so until the last step the old plan is
    // still the plan.
    try {
      await _lift.from('plans').insert(<String, Object?>{
        'id': plan.id,
        'user_id': userId,
        'status': 'draft',
        'split': plan.name,
        'day_order': plan.dayOrder,
        'rationale': plan.rationale,
        'days_per_week': plan.weekdays.length,
        'available_weekdays': plan.weekdays,
        'started_at': (plan.startedAt ?? DateTime.now())
            .toIso8601String()
            .split('T')
            .first,
        // What they told the coach. The columns have been here since the
        // block model; nothing wrote them, so every answer was lost the moment
        // the plan was built.
        if (intake != null) ...<String, Object?>{
          'goal': intake.goal,
          'equipment': intake.equipment,
          'injury_notes': intake.injuryNotes,
          'intake': intake.toJson(),
        },
      });
    } on Object catch (e) {
      throw PlanException(_writeFailure(e));
    }

    try {
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
              'sets': s.sets,
              'reps': s.reps,
              'sessions_at_same_top': s.sessionsAtSameTop,
              'last_top_kg': s.lastTopKg,
              'last_top_reps': s.lastTopReps,
            },
      ];
      if (rows.isNotEmpty) await _lift.from('plan_slots').insert(rows);

      // Supersede, then promote. The other order trips the partial unique
      // index on (user_id) where status = 'active' -- the index doing its job,
      // surfacing as a write failure rather than as the plan being replaced.
      await _lift
          .from('plans')
          .update(<String, Object?>{'status': 'superseded'})
          .eq('status', 'active');
      await _lift
          .from('plans')
          .update(<String, Object?>{'status': 'active'})
          .eq('id', plan.id);

      return plan;
    } on Object catch (e) {
      // Best effort. A draft is harmless -- [active] never reads one -- but a
      // draft nobody will finish is clutter in somebody's history.
      try {
        await _lift.from('plans').delete().eq('id', plan.id);
      } on Object {
        // Nothing to add: the failure that matters is the one being thrown.
      }
      throw PlanException(_writeFailure(e));
    }
  }

  /// A refusal from the database, or no answer at all.
  ///
  /// **Kept apart on purpose.** Both used to read "Could not reach your
  /// coach", which is how a schema fault spent seven weeks looking like bad
  /// signal: nobody checks a column when the app says check your connection.
  static PlanFailure _writeFailure(Object e) => switch (e) {
    PlanException(:final failure) => failure,
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
