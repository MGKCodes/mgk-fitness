import '../../../core/database/app_database.dart'
    show planStatusAbandoned, planStatusCompleted;
import '../domain/plan_shape.dart';
import '../domain/race_day.dart';
import '../domain/runner_profile.dart';
import '../domain/session_status.dart';
import '../domain/training_plan.dart';
import '../domain/week_progress.dart';

/// Pure JSON ⇄ domain mapping for the coach `skeleton` and `week` surfaces —
/// the request context sent up, and the model's proposal parsed back. Kept free
/// of Supabase so it is testable without a network (the same split as `coach_mappers`).
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

/// What has already happened this week, as JSON — sent to the `adapt` surface
/// so a revision is fitted around the runner's real week rather than laid over
/// the top of it.
///
/// **Four lists rather than seven days**, because the model is being asked to do
/// four different things with them: leave `done` exactly as it is, treat
/// `missed` as gone, count `unplanned` as work already banked and ask for less,
/// and rewrite `remaining`. Handing over a day-by-day array would leave it to
/// infer all four, and the failure this exists to fix is precisely a model
/// inferring wrongly about days it could not see.
///
/// A day the plan asked nothing of and nothing happened on appears in none of
/// them. It is a rest day, and there is nothing to say about it.
Map<String, dynamic> weekAsRunToJson(WeekAsRun soFar) => <String, dynamic>{
  'done': <Map<String, dynamic>>[
    for (final d in soFar.done)
      <String, dynamic>{
        'weekday': d.weekday,
        'kind': sessionKindToWire(d.prescribed!.kind),
        'distance_meters': d.prescribed!.distanceMeters,
        // What they actually covered, alongside what was asked. A run on the
        // day completes the day at any distance (see `week_progress.dart`), so
        // the two legitimately differ and the model should see both rather than
        // assume the prescription was met to the metre.
        'ran_meters': d.ranMeters,
      },
  ],
  'missed': <Map<String, dynamic>>[
    for (final d in soFar.missed)
      <String, dynamic>{
        'weekday': d.weekday,
        'kind': sessionKindToWire(d.prescribed!.kind),
        'distance_meters': d.prescribed!.distanceMeters,
      },
  ],
  'unplanned': <Map<String, dynamic>>[
    for (final d in soFar.unplanned)
      <String, dynamic>{'weekday': d.weekday, 'ran_meters': d.ranMeters},
  ],
  'remaining': <Map<String, dynamic>>[
    for (final d in soFar.remaining)
      <String, dynamic>{
        'weekday': d.weekday,
        'kind': sessionKindToWire(d.prescribed!.kind),
        'distance_meters': d.prescribed!.distanceMeters,
      },
  ],
  // The week's running total, so the model does not have to add the lists up to
  // work out how much of the slot is already spent.
  'ran_meters': soFar.ranMeters,
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

/// How a plan's stored status reads as an ending, or null when it is not one.
///
/// Only two of the four statuses are endings. `active` is the plan the runner
/// is on and `superseded` is one that was replaced mid-flight, which is a fact
/// about the *next* plan rather than about this one — see [PlanClosure].
///
/// An unrecognised status answers null rather than throwing, unlike the strict
/// decoding elsewhere in [DriftPlanStore]. A status this app does not know is
/// still a plan the runner had, and refusing to list their own history over a
/// vocabulary mismatch would lose the useful thing to protect a detail.
PlanClosure? planClosureFromWire(Object? v) => switch (v) {
  planStatusCompleted => PlanClosure.raced,
  planStatusAbandoned => PlanClosure.didNotRace,
  _ => null,
};

/// The stored status for an ending.
String planClosureToWire(PlanClosure closure) => switch (closure) {
  PlanClosure.raced => planStatusCompleted,
  PlanClosure.didNotRace => planStatusAbandoned,
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
