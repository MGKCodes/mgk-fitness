/// The rows `SupabasePlanBackup` writes, built as pure data.
///
/// Extracted from the writer after a year in which **not one plan reached
/// Supabase**. Two things were wrong at once and neither could be seen: the
/// profile row carried a `strength_days_per_week` column that did not exist, so
/// PostgREST rejected the statement and took the plans and plan_weeks upserts
/// down with it; and `plans.goal_distance_m` and `event_date` were `NOT NULL`,
/// which is only true of a block (ADR-0011 retired that assumption for rhythm
/// and horizon runners).
///
/// A push failure is swallowed on purpose — the plan is the device's and the
/// network must never fail a write (CLAUDE.md rule 1) — so nothing was ever
/// going to complain. That is precisely why the payload does not belong inside
/// an un-runnable method: built here, the column set is a value a test can hold
/// up against the schema, and adding a key becomes a visible diff rather than a
/// silent outage.
///
/// If you change a key in this file, there is a migration to write.
library;

import '../domain/stored_plan.dart';
import '../domain/training_plan.dart';
import 'plan_mappers.dart';

/// The `runio.plans` row for a plan.
///
/// `goal_distance_m` and `event_date` are **written as null rather than
/// omitted**: a runner who was training for a marathon and is now keeping a
/// rhythm needs the old values cleared on the upsert, and an omitted key on a
/// PostgREST upsert leaves the previous one in place.
Map<String, dynamic> planRow(StoredPlan plan, String userId) {
  final p = plan.profile;
  return <String, dynamic>{
    'id': plan.id,
    'user_id': userId,
    'goal_distance_m': p.goalDistanceMeters,
    'event_date': p.eventDate == null ? null : isoDate(p.eventDate!),
    'start_date': isoDate(plan.startDate),
    'weeks': plan.skeleton.weeks.length,
    'status': 'active',
    'current_weekly_m': p.currentWeeklyMeters,
    'longest_recent_m': p.longestRecentMeters,
    'days_per_week': p.daysPerWeek,
    'strength_days_per_week': p.strengthDaysPerWeek,
    'available_weekdays': p.availableWeekdays.toList()..sort(),
    'time_trial_distance_m': p.timeTrialDistanceMeters,
    'time_trial_seconds': p.timeTrialDuration?.inSeconds,
    'injury_notes': p.injuryNotes,
    // The substance of a PlanShape.rhythm. Sent as jsonb rather than the flat
    // `weekday|meters|timed|label` text Drift uses: SQLite has no array type
    // and the local mirror stays flat on purpose, but a backup that has to be
    // re-parsed by string splitting is a backup nothing can query.
    'commitments': <Map<String, dynamic>>[
      for (final c in p.commitments)
        <String, dynamic>{
          'weekday': c.weekday,
          'distance_meters': c.distanceMeters,
          'timed': c.timed,
          'label': c.label,
        },
    ],
  };
}

/// The `runio.plan_weeks` rows for a plan's whole arc.
List<Map<String, dynamic>> weekRows(StoredPlan plan, String userId) =>
    <Map<String, dynamic>>[
      for (final w in plan.skeleton.weeks)
        <String, dynamic>{
          'id': weekId(plan.id, w.index),
          'plan_id': plan.id,
          'user_id': userId,
          'week_number': w.index,
          'phase': phaseToWire(w.phase),
          'target_volume_m': w.volumeMeters,
          'long_run_m': w.longRunMeters,
          'is_deload': w.isDeload,
        },
    ];

/// The `runio.runner_profiles` row — the documented home of the current
/// profile, kept in step with the plan.
///
/// Additive columns only: the goal and the event date belong to the plan, not
/// to the profile, because a runner has one profile and many plans.
Map<String, dynamic> profileRow(StoredPlan plan, String userId, DateTime now) {
  final p = plan.profile;
  return <String, dynamic>{
    'user_id': userId,
    'current_weekly_m': p.currentWeeklyMeters,
    'longest_run_m': p.longestRecentMeters,
    'days_per_week': p.daysPerWeek,
    'strength_days_per_week': p.strengthDaysPerWeek,
    'available_days': p.availableWeekdays.toList()..sort(),
    'time_trial_distance_m': p.timeTrialDistanceMeters,
    'time_trial_seconds': p.timeTrialDuration?.inSeconds,
    'injury_notes': p.injuryNotes,
    'updated_at': now.toUtc().toIso8601String(),
  };
}

/// The `runio.plan_sessions` rows for one week. Training days only — a rest day
/// is the absence of a row, not a row saying "rest".
List<Map<String, dynamic>> sessionRows(
  StoredPlan plan,
  TrainingWeek week,
  String userId,
) => <Map<String, dynamic>>[
  for (final s in week.runs)
    <String, dynamic>{
      'id': sessionId(plan.id, week.skeletonIndex, s.weekday),
      'plan_id': plan.id,
      'user_id': userId,
      'week_number': week.skeletonIndex,
      'weekday': s.weekday,
      'scheduled_date': isoDate(
        plan.dateFor(weekIndex: week.skeletonIndex, weekday: s.weekday),
      ),
      'kind': sessionKindToWire(s.kind),
      'target_distance_m': s.distanceMeters,
      // What the runner calls it. Dropped on the way up as well as locally, so
      // a restored parkrun came back as "Easy" on a new phone even once the
      // local column existed.
      'label': s.label,
      'provisional': week.provisional,
    },
];

/// Deterministic ids, so a re-push updates the same row instead of duplicating
/// it. The local store's key is `(plan, week, weekday)`; Postgres wants a
/// single-column primary key, so it is composed from the same three parts.
String weekId(String planId, int weekNumber) => '$planId-w$weekNumber';

String sessionId(String planId, int weekNumber, int weekday) =>
    '$planId-w$weekNumber-d$weekday';

String isoDate(DateTime d) => d.toIso8601String().split('T').first;
