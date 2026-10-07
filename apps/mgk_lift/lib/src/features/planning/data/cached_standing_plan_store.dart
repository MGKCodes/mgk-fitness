import 'dart:async';
import 'dart:convert';

import '../domain/plan_intake.dart';
import '../domain/standing_plan.dart';
import '../domain/standing_plan_store.dart';

/// Where the live plan is kept on this phone, as one piece of JSON.
abstract interface class PlanCache {
  /// The saved JSON, or null. Must not throw.
  Future<String?> read();

  /// Must not throw.
  Future<void> write(String json);

  /// Must not throw.
  Future<void> clear();
}

/// Forgets on restart. For tests and the preview harness.
class InMemoryPlanCache implements PlanCache {
  InMemoryPlanCache([this._json]);

  String? _json;

  @override
  Future<String?> read() async => _json;

  @override
  Future<void> write(String json) async => _json = json;

  @override
  Future<void> clear() async => _json = null;
}

/// The live plan, with a copy on the phone.
///
/// **Plans lived only on the server** (*Found while planning*): a failed load
/// left the plan null, which was an inconvenience while Plan was where a
/// planned session started, and is a missing session now that it starts from
/// Track — at the gym, in the basement, with no signal. So every load that
/// reaches the server saves what it read, and a load that does not answers
/// with the last one saved.
///
/// **Saved, never edited here.** The copy is only ever the server's last
/// answer, so it cannot disagree with it about anything but freshness; a
/// replacement goes to the server first and is saved from its reply.
class CachedStandingPlanStore implements StandingPlanStore {
  CachedStandingPlanStore({
    required StandingPlanStore remote,
    required PlanCache cache,
  }) : _remote = remote,
       _cache = cache;

  final StandingPlanStore _remote;
  final PlanCache _cache;

  @override
  Future<StandingPlan?> active() async {
    StandingPlan? plan;
    try {
      plan = await _remote.active();
    } on Object {
      // No signal, or the server said no. The last plan it gave is still the
      // plan: nothing on the phone could have changed it.
      return _cached();
    }
    if (plan == null) {
      // No plan any more — replaced elsewhere, or a different account. Kept,
      // it would put a session on Track that nobody is following.
      await _cache.clear();
    } else {
      await _cache.write(jsonEncode(planToJson(plan)));
    }
    return plan;
  }

  Future<StandingPlan?> _cached() async {
    final json = await _cache.read();
    if (json == null) return null;
    try {
      return planFromJson(jsonDecode(json) as Map<String, Object?>);
    } on Object {
      // A copy that cannot be read is no copy.
      await _cache.clear();
      return null;
    }
  }

  @override
  Future<StandingPlan> replace(StandingPlan plan, {PlanIntake? intake}) async {
    final saved = await _remote.replace(plan, intake: intake);
    await _cache.write(jsonEncode(planToJson(saved)));
    return saved;
  }

  @override
  Future<void> recordResult(
    String slotId, {
    required double topKg,
    required int reps,
    required bool improved,
  }) => _remote.recordResult(
    slotId,
    topKg: topKg,
    reps: reps,
    improved: improved,
  );
}

Map<String, Object?> planToJson(StandingPlan p) => <String, Object?>{
  'id': p.id,
  'name': p.name,
  'dayOrder': p.dayOrder,
  'weekdays': p.weekdays,
  'rationale': p.rationale,
  'startedAt': p.startedAt?.toIso8601String(),
  'slots': <String, Object?>{
    for (final e in p.slots.entries)
      e.key: <Object?>[
        for (final s in e.value)
          <String, Object?>{
            'id': s.id,
            'role': s.role,
            'movement': s.movement,
            'isMain': s.isMain,
            'sets': s.sets,
            'reps': s.reps,
            'sessionsAtSameTop': s.sessionsAtSameTop,
            'lastTopKg': s.lastTopKg,
            'lastTopReps': s.lastTopReps,
          },
      ],
  },
};

StandingPlan planFromJson(Map<String, Object?> j) => StandingPlan(
  id: j['id']! as String,
  name: j['name']! as String,
  dayOrder: <String>[
    for (final d in j['dayOrder']! as List<Object?>) d! as String,
  ],
  weekdays: <int>[for (final d in j['weekdays']! as List<Object?>) d! as int],
  rationale: j['rationale'] as String?,
  startedAt: switch (j['startedAt']) {
    final String at => DateTime.parse(at),
    _ => null,
  },
  slots: <String, List<MovementSlot>>{
    for (final e in (j['slots']! as Map<String, Object?>).entries)
      e.key: <MovementSlot>[
        for (final raw in e.value! as List<Object?>)
          switch (raw! as Map<String, Object?>) {
            final s => MovementSlot(
              id: s['id']! as String,
              role: s['role']! as String,
              movement: s['movement']! as String,
              isMain: s['isMain']! as bool,
              sets: s['sets']! as int,
              reps: s['reps']! as int,
              sessionsAtSameTop: s['sessionsAtSameTop']! as int,
              lastTopKg: (s['lastTopKg'] as num?)?.toDouble(),
              lastTopReps: s['lastTopReps'] as int?,
            ),
          },
      ],
  },
);
