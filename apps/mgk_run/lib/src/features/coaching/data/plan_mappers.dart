import '../domain/plan_shape.dart';
import '../domain/runner_profile.dart';
import '../domain/session_status.dart';
import '../domain/training_plan.dart';

/// Pure JSON ⇄ domain mapping for the coach `skeleton` and `week` surfaces —
/// the request context sent up, and the model's proposal parsed back. Kept free
/// of Supabase so it is testable without a network (the `run_mappers` pattern).
///
/// Response parsing is **tolerant**: anything malformed returns `null`, which
/// the orchestrator treats as a failed attempt (and ultimately falls back to
/// the deterministic builder). Wire format is metric, `1=Mon..7=Sun`.

// ---- request side (client → function) --------------------------------------

Map<String, dynamic> runnerProfileToJson(RunnerProfile p) => <String, dynamic>{
  if (p.goalDistanceMeters != null)
    'goal_distance_meters': p.goalDistanceMeters,
  // Omitted rather than nulled when there is no race: the model should not be
  // handed a key whose absence it has to reason about.
  if (p.eventDate != null)
    'event_date': p.eventDate!.toIso8601String().split('T').first,
  'shape': shapeOf(p).name,
  'current_weekly_meters': p.currentWeeklyMeters,
  'longest_recent_meters': p.longestRecentMeters,
  'days_per_week': p.daysPerWeek,
  'available_weekdays': p.availableWeekdays.toList()..sort(),
  'strength_days_per_week': p.strengthDaysPerWeek,
  'time_trial_distance_meters': p.timeTrialDistanceMeters,
  'time_trial_seconds': p.timeTrialDuration?.inSeconds,
  'injury_notes': p.injuryNotes,
}..removeWhere((_, v) => v == null);

Map<String, dynamic> skeletonWeekToJson(SkeletonWeek w) => <String, dynamic>{
  'index': w.index,
  'phase': phaseToWire(w.phase),
  'volume_meters': w.volumeMeters,
  'long_run_meters': w.longRunMeters,
  'is_deload': w.isDeload,
};

/// A week's sessions as JSON — sent up so the `adapt` surface can revise them.
Map<String, dynamic> trainingWeekToJson(TrainingWeek w) => <String, dynamic>{
  'sessions': <Map<String, dynamic>>[
    for (final s in w.sessions)
      <String, dynamic>{
        'weekday': s.weekday,
        'kind': sessionKindToWire(s.kind),
        'distance_meters': s.distanceMeters,
      },
  ],
};

// ---- response side (function → client), tolerant: null on any problem ------

PlanSkeleton? planSkeletonFromJson(Map<String, dynamic> json) {
  final weeks = json['weeks'];
  if (weeks is! List || weeks.isEmpty) return null;
  final out = <SkeletonWeek>[];
  for (var i = 0; i < weeks.length; i++) {
    final w = weeks[i];
    if (w is! Map) return null;
    final phase = phaseFromWire(w['phase']);
    final volume = _num(w['volume_meters']);
    final longRun = _num(w['long_run_meters']);
    if (phase == null || volume == null || longRun == null) return null;
    out.add(
      SkeletonWeek(
        index: _int(w['index']) ?? (i + 1),
        phase: phase,
        volumeMeters: volume,
        longRunMeters: longRun,
        isDeload: w['is_deload'] == true,
      ),
    );
  }
  return PlanSkeleton(weeks: out);
}

TrainingWeek? trainingWeekFromJson(
  Map<String, dynamic> json, {
  required int skeletonIndex,
}) {
  final sessions = json['sessions'];
  if (sessions is! List || sessions.isEmpty) return null;
  final out = <PlannedSession>[];
  for (final s in sessions) {
    if (s is! Map) return null;
    final weekday = _int(s['weekday']);
    final kind = sessionKindFromWire(s['kind']);
    if (weekday == null || weekday < 1 || weekday > 7 || kind == null) {
      return null;
    }
    out.add(
      PlannedSession(
        weekday: weekday,
        kind: kind,
        distanceMeters: _num(s['distance_meters']) ?? 0,
      ),
    );
  }
  return TrainingWeek(skeletonIndex: skeletonIndex, sessions: out);
}

// ---- enum wire strings -----------------------------------------------------

String phaseToWire(Phase p) => p.name; // base / build / peak / taper

Phase? phaseFromWire(Object? v) => switch (v) {
  'base' => Phase.base,
  'build' => Phase.build,
  'peak' => Phase.peak,
  'taper' => Phase.taper,
  _ => null,
};

String sessionKindToWire(SessionKind k) => switch (k) {
  SessionKind.marathonPace => 'marathon_pace',
  SessionKind.timeTrial => 'time_trial',
  _ => k.name,
};

SessionKind? sessionKindFromWire(Object? v) => switch (v) {
  'rest' => SessionKind.rest,
  'strength' => SessionKind.strength,
  'time_trial' => SessionKind.timeTrial,
  'recovery' => SessionKind.recovery,
  'easy' => SessionKind.easy,
  'long' => SessionKind.long,
  'marathon_pace' => SessionKind.marathonPace,
  'threshold' => SessionKind.threshold,
  'interval' => SessionKind.interval,
  _ => null,
};

/// The same vocabulary as `plan_sessions.status` locally and in Postgres, so a
/// status crosses the Drift row, the wire, and the check constraint unchanged.
String sessionStatusToWire(SessionStatus s) => s.name;

SessionStatus? sessionStatusFromWire(Object? v) => switch (v) {
  'planned' => SessionStatus.planned,
  'completed' => SessionStatus.completed,
  'skipped' => SessionStatus.skipped,
  _ => null,
};

double? _num(Object? v) => v is num ? v.toDouble() : null;

int? _int(Object? v) => v is num ? v.toInt() : null;
