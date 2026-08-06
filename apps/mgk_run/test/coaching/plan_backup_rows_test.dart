import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/data/plan_backup_rows.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_shape.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';

/// The columns each table actually has, as of
/// `20260729150000_plan_backup_nullable_goal.sql`.
///
/// **This is the test.** `PlanRepository` swallows a failed push on purpose —
/// the plan belongs to the device and the network must never fail a write — so
/// a payload naming a column that does not exist produces no error anywhere,
/// just a backup that quietly never happens. It did, for a year: `pushPlan`
/// sent `strength_days_per_week` to `runner_profiles`, which had no such
/// column, and PostgREST rejected the statement along with the plans and
/// plan_weeks upserts sharing the method.
///
/// Holding the schema here turns that from an invisible outage into a failing
/// test. If one of these lists is wrong, the fix is a migration, not an edit to
/// the list.
const Set<String> planColumns = <String>{
  'id',
  'user_id',
  'goal_distance_m',
  'goal_time_s',
  'event_date',
  'start_date',
  'weeks',
  'status',
  'current_weekly_m',
  'longest_recent_m',
  'days_per_week',
  'available_weekdays',
  'time_trial_distance_m',
  'time_trial_seconds',
  'injury_notes',
  'created_at',
  'strength_days_per_week',
  'commitments',
  'updated_at',
};

const Set<String> planWeekColumns = <String>{
  'id',
  'plan_id',
  'user_id',
  'week_number',
  'phase',
  'target_volume_m',
  'long_run_m',
  'is_deload',
  'generated_at',
  'updated_at',
};

const Set<String> planSessionColumns = <String>{
  'id',
  'plan_id',
  'user_id',
  'week_number',
  'weekday',
  'scheduled_date',
  'kind',
  'target_distance_m',
  'target_pace_s_per_km',
  'structure_json',
  'rationale',
  'status',
  'status_at',
  'provisional',
  'run_id',
  // What the runner calls the session. Added by
  // `20260801090000_plan_session_label.sql`, which is applied.
  'label',
  'updated_at',
};

const Set<String> runnerProfileColumns = <String>{
  'user_id',
  'current_weekly_m',
  'longest_run_m',
  'available_days',
  'time_trial_distance_m',
  'time_trial_seconds',
  'injury_notes',
  'updated_at',
  'days_per_week',
  'strength_days_per_week',
};

/// Columns the schema requires. A null sent into one of these is rejected, and
/// rejected silently, so the shapes that legitimately have no goal must not be
/// listed here (ADR-0011).
const Set<String> planNotNull = <String>{
  'id',
  'user_id',
  'start_date',
  'weeks',
  'status',
  'current_weekly_m',
  'longest_recent_m',
  'days_per_week',
  'available_weekdays',
  'strength_days_per_week',
  'commitments',
};

void main() {
  final now = DateTime(2026, 7, 29, 9, 30);

  StoredPlan planFor(RunnerProfile profile) => StoredPlan(
    id: 'plan-1',
    profile: profile,
    skeleton: buildSkeleton(profile, now: now),
    startDate: mondayOf(now),
  );

  /// The marathon runner: a goal, a date, a block.
  RunnerProfile blockProfile() => RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: DateTime(2026, 11, 15),
    currentWeeklyMeters: 40000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 4, 6, 7},
    strengthDaysPerWeek: 1,
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );

  /// The parkrun regular ADR-0011 exists for: no goal distance, no race.
  RunnerProfile rhythmProfile() => const RunnerProfile(
    currentWeeklyMeters: 20000,
    longestRecentMeters: 9000,
    daysPerWeek: 3,
    availableWeekdays: <int>{2, 4, 6},
    commitments: <PlanCommitment>[
      PlanCommitment(
        weekday: DateTime.saturday,
        distanceMeters: 5000,
        label: 'parkrun',
        timed: true,
      ),
    ],
  );

  group('every key names a column that exists', () {
    test('the plan row', () {
      expect(
        planRow(planFor(blockProfile()), 'u1').keys,
        everyElement(isIn(planColumns)),
      );
    });

    test('the week rows', () {
      for (final row in weekRows(planFor(blockProfile()), 'u1')) {
        expect(row.keys, everyElement(isIn(planWeekColumns)));
      }
    });

    test('the session rows', () {
      final plan = planFor(blockProfile());
      final week = buildFallbackWeek(plan.skeleton.weeks.first, plan.profile);
      final rows = sessionRows(plan, week, 'u1');
      expect(rows, isNotEmpty);
      for (final row in rows) {
        expect(row.keys, everyElement(isIn(planSessionColumns)));
      }
    });

    test('the profile row', () {
      // The one that was wrong. `strength_days_per_week` was sent to a table
      // that did not have it, and it took the other two upserts with it.
      final row = profileRow(planFor(blockProfile()), 'u1', now);
      expect(row.keys, everyElement(isIn(runnerProfileColumns)));
      expect(row['strength_days_per_week'], 1);
    });
  });

  group('a runner with no race can still be backed up', () {
    // The second bug: goal_distance_m and event_date were NOT NULL, which is
    // only true of a block. A rhythm runner's plan could never be written.
    test('a rhythm plan carries nulls, and they are allowed ones', () {
      final row = planRow(planFor(rhythmProfile()), 'u1');

      expect(row['goal_distance_m'], isNull);
      expect(row['event_date'], isNull);

      for (final key in planNotNull) {
        expect(
          row[key],
          isNotNull,
          reason:
              '$key is NOT NULL in the schema; a null here is rejected '
              'and the rejection is swallowed',
        );
      }
    });

    test('the nulls are written, not omitted', () {
      // On a PostgREST upsert an omitted key leaves the stored value alone. A
      // runner who was training for a marathon and is now keeping a rhythm
      // needs the old goal cleared, not preserved.
      final row = planRow(planFor(rhythmProfile()), 'u1');
      expect(row.containsKey('goal_distance_m'), isTrue);
      expect(row.containsKey('event_date'), isTrue);
    });

    test('their commitments survive the trip as queryable json', () {
      final row = planRow(planFor(rhythmProfile()), 'u1');
      final commitments = row['commitments'] as List<Map<String, dynamic>>;
      expect(commitments, hasLength(1));
      expect(commitments.single['label'], 'parkrun');
      expect(commitments.single['distance_meters'], 5000);
      expect(commitments.single['timed'], isTrue);
    });
  });

  group(
    'ids are deterministic, so a re-push updates rather than duplicates',
    () {
      test('a week id is stable for the same plan and week', () {
        expect(weekId('plan-1', 3), weekId('plan-1', 3));
        expect(weekId('plan-1', 3), isNot(weekId('plan-1', 4)));
        expect(weekId('plan-1', 3), isNot(weekId('plan-2', 3)));
      });

      test('a session id is stable for the same plan, week and day', () {
        expect(sessionId('plan-1', 3, 2), sessionId('plan-1', 3, 2));
        expect(sessionId('plan-1', 3, 2), isNot(sessionId('plan-1', 3, 4)));
      });

      test('a date crosses the wire as a date, not a timestamp', () {
        expect(isoDate(DateTime(2026, 7, 29, 23, 59)), '2026-07-29');
      });
    },
  );
}
