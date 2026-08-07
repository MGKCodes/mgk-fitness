import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mgk_units/mgk_units.dart';

import '../domain/plan.dart';
import '../domain/plan_generator.dart';
import '../domain/plan_store.dart';
import '../domain/plan_validator.dart';

/// Plans, in `lift.*`.
///
/// Written directly rather than through a function: accepting a draft, ticking
/// a session off and rescheduling one are all the lifter's own rows, all scoped
/// by RLS, and none of them costs money. The Edge Function exists to hold a
/// provider key and gate spending, and none of that applies here.
///
/// **A draft becomes active by an UPDATE the lifter causes**, and the partial
/// unique index in the schema is what stops two being active at once — not this
/// code being careful. Any earlier active plan is superseded first, in the same
/// call order every time, because the index would reject the second write
/// otherwise and the error would surface as "could not save your plan".
class SupabasePlanStore implements PlanStore {
  SupabasePlanStore(this._client);

  final SupabaseClient _client;

  SupabaseQuerySchema get _lift => _client.schema('lift');

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const PlanException(PlanFailure.signedOut);
    return id;
  }

  @override
  Future<Plan?> active() async {
    try {
      final rows = await _lift
          .from('plans')
          .select()
          .eq('user_id', _userId)
          .eq('status', PlanStatus.active.wire)
          .limit(1);
      if (rows.isEmpty) return null;
      return _hydrate(rows.first);
    } on PlanException {
      rethrow;
    } on Object {
      throw const PlanException(PlanFailure.unavailable);
    }
  }

  @override
  Future<void> save(Plan plan) async {
    final userId = _userId;
    try {
      await _lift.from('plans').upsert(<String, Object?>{
        'id': plan.id,
        'user_id': userId,
        'goal': plan.goal,
        'start_date': _date(plan.startDate),
        'weeks': plan.weeks,
        'status': plan.status.wire,
        'days_per_week': plan.profile.daysPerWeek,
        'available_weekdays': plan.profile.availableWeekdays,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      if (plan.arc.isNotEmpty) {
        await _lift.from('plan_weeks').upsert(<Map<String, Object?>>[
          for (final week in plan.arc)
            <String, Object?>{
              'id': '${plan.id}-w${week.number}',
              'plan_id': plan.id,
              'user_id': userId,
              'week_number': week.number,
              'phase': week.phase.wire,
              'intent': week.intent,
              'updated_at': DateTime.now().toUtc().toIso8601String(),
            },
        ]);
      }

      if (plan.sessions.isNotEmpty) {
        await _lift.from('plan_sessions').upsert(<Map<String, Object?>>[
          for (final session in plan.sessions)
            _sessionRow(session, plan, userId),
        ]);
      }
    } on PlanException {
      rethrow;
    } on Object {
      throw const PlanException(PlanFailure.unavailable);
    }
  }

  @override
  Future<Plan> accept(Plan draft) async {
    final userId = _userId;
    try {
      // Any incumbent stands down first. The schema's partial unique index
      // would reject the second active plan, and that rejection would reach the
      // lifter as "could not save", which tells them nothing.
      await _lift
          .from('plans')
          .update(<String, Object?>{'status': PlanStatus.superseded.wire})
          .eq('user_id', userId)
          .eq('status', PlanStatus.active.wire);

      await _lift
          .from('plans')
          .update(<String, Object?>{
            'status': PlanStatus.active.wire,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', draft.id)
          .eq('user_id', userId);

      return draft.copyWith(status: PlanStatus.active);
    } on PlanException {
      rethrow;
    } on Object {
      throw const PlanException(PlanFailure.unavailable);
    }
  }

  @override
  Future<void> markTrained(PlanSession session, String workoutId) async {
    try {
      await _lift
          .from('plan_sessions')
          .update(<String, Object?>{
            'status': PlanSessionStatus.completed.wire,
            'status_at': DateTime.now().toUtc().toIso8601String(),
            // The join that makes "did they do the plan" answerable.
            'workout_id': workoutId,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', session.id)
          .eq('user_id', _userId);
    } on PlanException {
      rethrow;
    } on Object {
      throw const PlanException(PlanFailure.unavailable);
    }
  }

  @override
  Future<void> replaceMovements(
    PlanSession session,
    List<PlannedMovement> movements,
  ) async {
    try {
      await _lift
          .from('plan_sessions')
          .update(<String, Object?>{
            'movements': <Map<String, Object?>>[
              for (final m in movements) _movementJson(m),
            ],
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', session.id)
          .eq('user_id', _userId);
    } on PlanException {
      rethrow;
    } on Object {
      throw const PlanException(PlanFailure.unavailable);
    }
  }

  Map<String, Object?> _sessionRow(
    PlanSession session,
    Plan plan,
    String userId,
  ) => <String, Object?>{
    'id': session.id,
    'plan_id': plan.id,
    'user_id': userId,
    'week_number': session.weekNumber,
    'weekday': session.weekday,
    'scheduled_date': _date(session.scheduledDate),
    'kind': session.kind,
    'movements': <Map<String, Object?>>[
      for (final m in session.movements) _movementJson(m),
    ],
    'rationale': session.rationale,
    'status': session.status.wire,
    'workout_id': session.workoutId,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  /// A movement as it is stored.
  ///
  /// `target_kg` is written here even though no model may produce one: by this
  /// point it has been derived from the lifter's own log, so storing it is
  /// recording what was prescribed rather than accepting what was claimed.
  static Map<String, Object?> _movementJson(PlannedMovement m) =>
      <String, Object?>{
        'name': m.name,
        'sets': m.sets,
        'reps': m.reps,
        'target_kg': m.target?.kilograms,
        'note': m.note,
      };

  Future<Plan> _hydrate(Map<String, dynamic> row) async {
    final planId = row['id'] as String;
    final weeks = await _lift
        .from('plan_weeks')
        .select()
        .eq('plan_id', planId)
        .order('week_number');
    final sessions = await _lift
        .from('plan_sessions')
        .select()
        .eq('plan_id', planId)
        .order('scheduled_date');

    return Plan(
      id: planId,
      startDate: DateTime.parse(row['start_date'] as String),
      weeks: (row['weeks'] as num).toInt(),
      status: PlanStatus.fromWire(row['status'] as String? ?? 'draft'),
      goal: row['goal'] as String?,
      profile: PlanProfile(
        daysPerWeek: (row['days_per_week'] as num?)?.toInt() ?? 3,
        availableWeekdays: <int>[
          for (final d in (row['available_weekdays'] as List? ?? <Object?>[]))
            if (d is num) d.toInt(),
        ],
      ),
      arc: <PlanWeek>[
        for (final w in weeks)
          PlanWeek(
            number: (w['week_number'] as num).toInt(),
            phase: PlanPhase.fromWire(w['phase'] as String? ?? 'base'),
            intent: w['intent'] as String?,
          ),
      ],
      sessions: <PlanSession>[
        for (final s in sessions)
          PlanSession(
            id: s['id'] as String,
            weekNumber: (s['week_number'] as num).toInt(),
            weekday: (s['weekday'] as num).toInt(),
            scheduledDate: DateTime.parse(s['scheduled_date'] as String),
            kind: s['kind'] as String?,
            rationale: s['rationale'] as String?,
            status: PlanSessionStatus.fromWire(s['status'] as String? ?? ''),
            workoutId: s['workout_id'] as String?,
            movements: _movements(s['movements']),
          ),
      ],
    );
  }

  static List<PlannedMovement> _movements(Object? raw) => <PlannedMovement>[
    if (raw is List)
      for (final m in raw)
        if (m is Map)
          PlannedMovement(
            name: m['name'] as String? ?? '',
            sets: (m['sets'] as num?)?.toInt() ?? 0,
            reps: (m['reps'] as num?)?.toInt() ?? 0,
            target: m['target_kg'] is num
                ? Mass.kilograms((m['target_kg'] as num).toDouble())
                : null,
            note: m['note'] as String?,
          ),
  ];

  static String _date(DateTime at) =>
      '${at.year.toString().padLeft(4, '0')}-'
      '${at.month.toString().padLeft(2, '0')}-'
      '${at.day.toString().padLeft(2, '0')}';
}
