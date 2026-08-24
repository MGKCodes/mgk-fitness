import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/database/app_database.dart';
import '../../../core/supabase/paged_select.dart';
import '../../settings/domain/backup_consent.dart';
import '../domain/run_writer.dart';

/// Pulls the runner's data back down after a reinstall or onto a new phone.
///
/// The other half of the backup, and the half that makes "everything survives a
/// lost phone" true rather than aspirational. Pushing was never the hard part.
///
/// ## It only ever adds
///
/// Every write is insert-or-ignore (see the restore block on [AppDatabase]), so
/// a row the phone already has always wins. That is a deliberate choice of the
/// weaker guarantee: a one-way pull cannot resolve a conflict, and it cannot
/// create one either. Two-way sync with last-write-wins would be the stronger
/// design and the one that can lose data when it gets a timestamp wrong, and
/// Runio has one device per runner, so there is nothing for it to resolve.
///
/// `updated_at` now exists on the server rows for the day that stops being
/// true. Nothing here reads it.
///
/// ## It is gated on consent
///
/// Reading your own data back is not the privacy risk that uploading it is, but
/// the gate is here anyway for a plainer reason: a runner who declined has
/// nothing stored to restore, and one who has not been asked yet should be
/// asked before the app starts moving their health data around. On new
/// hardware consent arrives unset, so the order is always ask, then restore.
class SupabaseRestore implements DataRestore {
  SupabaseRestore({
    required AppDatabase db,
    required BackupConsentStore consent,
    SupabaseClient? client,
  }) : _db = db,
       _consent = consent,
       _client = client ?? Supabase.instance.client;

  final AppDatabase _db;
  final BackupConsentStore _consent;
  final SupabaseClient _client;

  SupabaseQuerySchema get _run => _client.schema('run');
  SupabaseQuerySchema get _coach => _client.schema('coach');

  /// How many runs to pull traces for.
  ///
  /// A trace is thousands of rows and only the recent ones are ever drawn, so
  /// pulling every trace a runner has ever recorded would spend minutes and
  /// most of a mobile data allowance to restore maps nobody opens. Summaries
  /// come back in full — they are small, and they are what the log, the
  /// standing and the coach's brief are built from.
  static const int _tracesForRecentRuns = 30;

  /// Restores everything, in dependency order. Returns what was pulled.
  ///
  /// Never throws: a restore that fails halfway has still restored the first
  /// half, and every write is repeatable, so the next attempt continues rather
  /// than starting again.
  @override
  Future<RestoreResult> restoreAll() async {
    if (!(await _consent.read()).allowsBackup) return RestoreResult.skipped();
    final result = RestoreResult();
    await _guard(() async => result.runs = await _restoreRuns());
    await _guard(() async => result.plans = await _restorePlan());
    await _guard(() async => result.turns = await _restoreMemory());
    return result;
  }

  Future<int> _restoreRuns() async {
    final rows = await fetchAllPages(
      (f, t) => _run
          .from('runs')
          .select()
          .order('started_at', ascending: false)
          .range(f, t),
    );
    if (rows.isEmpty) return 0;

    await _db.restoreRuns(<RunsCompanion>[
      for (final r in rows) _runCompanion(r),
    ]);

    // Traces for the recent ones only — see [_tracesForRecentRuns].
    final recent = rows
        .take(_tracesForRecentRuns)
        .map((r) => r['id'] as String)
        .toList();
    for (final id in recent) {
      await _guard(() => _restoreTrace(id));
    }
    return rows.length;
  }

  Future<void> _restoreTrace(String runId) async {
    final points = await fetchAllPages(
      (f, t) => _run
          .from('run_points')
          .select()
          .eq('run_id', runId)
          .order('seq')
          .range(f, t),
    );
    if (points.isNotEmpty) {
      await _db.restoreRunPoints(<RunPointsCompanion>[
        for (final p in points)
          RunPointsCompanion.insert(
            runId: runId,
            seq: (p['seq'] as num).toInt(),
            lat: (p['lat'] as num).toDouble(),
            lng: (p['lng'] as num).toDouble(),
            altitudeM: Value((p['altitude_m'] as num?)?.toDouble()),
            accuracyM: (p['accuracy_m'] as num).toDouble(),
            timestamp: DateTime.parse(p['recorded_at'] as String),
          ),
      ]);
    }

    final splits = await fetchAllPages(
      (f, t) => _run
          .from('run_splits')
          .select()
          .eq('run_id', runId)
          .order('seq')
          .range(f, t),
    );
    if (splits.isEmpty) return;
    await _db.restoreRunSplits(<RunSplitsCompanion>[
      for (final s in splits)
        RunSplitsCompanion.insert(
          runId: runId,
          seq: (s['seq'] as num).toInt(),
          distanceM: (s['distance_m'] as num).toDouble(),
          durationS: (s['duration_s'] as num).toInt(),
          avgHr: Value((s['avg_hr'] as num?)?.toInt()),
        ),
    ]);
  }

  /// Restores the active plan, but only onto a phone with no plan at all.
  ///
  /// A device that already has one is not waiting to be told what its plan is,
  /// and pulling a second would leave two rows fighting over which is active —
  /// a partial unique index the local database would then refuse.
  Future<int> _restorePlan() async {
    if (!await _db.hasNoPlan()) return 0;

    final rows = await _run
        .from('plans')
        .select()
        .eq('status', 'active')
        .limit(1);
    if (rows.isEmpty) return 0;
    final plan = Map<String, dynamic>.from(rows.first);
    final planId = plan['id'] as String;

    final weekRows = await _run
        .from('plan_weeks')
        .select()
        .eq('plan_id', planId)
        .order('week_number');
    final sessionRows = await fetchAllPages(
      (f, t) =>
          _run.from('plan_sessions').select().eq('plan_id', planId).range(f, t),
    );

    await _db.restorePlan(
      plan: _planCompanion(plan),
      weeks: <PlanWeeksCompanion>[
        for (final w in weekRows) _weekCompanion(Map<String, dynamic>.from(w)),
      ],
      sessions: <PlanSessionsCompanion>[
        for (final s in sessionRows) _sessionCompanion(s),
      ],
    );
    return 1;
  }

  /// Restores what the coach remembers.
  ///
  /// The thing a runner can least afford to lose and the last store to get a
  /// return path. Runs can be re-entered and a plan can be regenerated in one
  /// call; "runs before work, will not run in the dark, left calf tightens on
  /// faster sessions" took months of conversation and cannot be reconstructed
  /// from anything else.
  ///
  /// Only onto a device that remembers nothing. A phone mid-conversation is
  /// not missing its memory, and merging a server copy into a live transcript
  /// risks interleaving turns by `seq` into an order neither side ever said.
  Future<int> _restoreMemory() async {
    if (!await _db.hasNoCoachMemory()) return 0;

    final summaryRows = await _coach.from('summaries').select().limit(1);
    if (summaryRows.isNotEmpty) {
      final row = Map<String, dynamic>.from(summaryRows.first);
      await _db.restoreCoachSummary(
        CoachSummariesCompanion.insert(
          summary: row['summary'] as String,
          model: Value(row['model'] as String?),
          turnsCovered: Value((row['turns_covered'] as num?)?.toInt() ?? 0),
          updatedAt: Value(DateTime.parse(row['updated_at'] as String)),
        ),
      );
    }

    final convoRows = await fetchAllPages(
      (f, t) => _coach
          .from('conversations')
          .select()
          .order('last_turn_at', ascending: false)
          .range(f, t),
    );
    if (convoRows.isEmpty) return 0;

    final turnRows = await fetchAllPages(
      (f, t) => _coach.from('turns').select().order('created_at').range(f, t),
    );

    await _db.restoreCoachMemory(
      conversations: <CoachConversationsCompanion>[
        for (final row in convoRows)
          () {
            return CoachConversationsCompanion.insert(
              id: row['id'] as String,
              kind: Value(row['kind'] as String? ?? 'coach'),
              startedAt: Value(DateTime.parse(row['started_at'] as String)),
              lastTurnAt: Value(DateTime.parse(row['last_turn_at'] as String)),
            );
          }(),
      ],
      turns: <CoachTurnsCompanion>[
        for (final row in turnRows)
          () {
            return CoachTurnsCompanion.insert(
              // The local key is (conversationId, seq); the server's surrogate
              // `id` is composed from the same pair and has no column here.
              conversationId: row['conversation_id'] as String,
              seq: (row['seq'] as num).toInt(),
              role: row['role'] as String,
              body: row['body'] as String,
              createdAt: Value(DateTime.parse(row['created_at'] as String)),
            );
          }(),
      ],
    );
    return turnRows.length;
  }

  // ---- row -> companion ------------------------------------------------------

  RunsCompanion _runCompanion(Map<String, dynamic> r) => RunsCompanion.insert(
    id: r['id'] as String,
    startedAt: DateTime.parse(r['started_at'] as String),
    durationS: (r['duration_s'] as num).toInt(),
    distanceM: (r['distance_m'] as num).toDouble(),
    source: r['source'] as String,
    type: r['type'] as String,
    // Restored runs are finished by definition; a null endedAt would make the
    // recorder treat one as an interrupted run to resume.
    endedAt: Value(
      DateTime.parse(
        r['started_at'] as String,
      ).add(Duration(seconds: (r['duration_s'] as num).toInt())),
    ),
    avgPaceSPerKm: Value((r['avg_pace_s_per_km'] as num?)?.toDouble()),
    elevationGainM: Value((r['elevation_gain_m'] as num?)?.toDouble()),
    // No `elevation_max_m` and no `steps`, because `run.runs` has neither: both
    // are local columns from schema version 8 and the Postgres side is a `db/`
    // change this app cannot make (`apps/mgk_run/CLAUDE.md` — the schema is not
    // here). So a run restored onto a new phone comes back without its high
    // point and its step count, which read as absent rather than wrong. See
    // `SupabaseRunBackup.pushRun` for the other half of the same seam.
    avgHr: Value((r['avg_hr'] as num?)?.toInt()),
    maxHr: Value((r['max_hr'] as num?)?.toInt()),
    cadence: Value((r['cadence'] as num?)?.toInt()),
    caloriesEst: Value((r['calories_est'] as num?)?.toDouble()),
    externalId: Value(r['external_id'] as String?),
    rpe: Value((r['rpe'] as num?)?.toInt()),
    notes: Value(r['notes'] as String?),
    sessionId: Value(r['session_id'] as String?),
  );

  PlansCompanion _planCompanion(
    Map<String, dynamic> p,
  ) => PlansCompanion.insert(
    id: p['id'] as String,
    startDate: DateTime.parse(p['start_date'] as String),
    weeks: (p['weeks'] as num).toInt(),
    currentWeeklyM: (p['current_weekly_m'] as num).toDouble(),
    longestRecentM: (p['longest_recent_m'] as num).toDouble(),
    daysPerWeek: (p['days_per_week'] as num).toInt(),
    // Drift keeps these flat; the server keeps them structured. Converting on
    // the way in rather than storing the server's shape locally keeps the two
    // mirrors independent — see the tables' own notes on why Drift stays flat.
    availableWeekdays: (p['available_weekdays'] as List<dynamic>)
        .map((d) => (d as num).toInt())
        .join(','),
    goalDistanceM: Value((p['goal_distance_m'] as num?)?.toDouble()),
    goalTimeS: Value((p['goal_time_s'] as num?)?.toInt()),
    eventDate: Value(
      p['event_date'] == null
          ? null
          : DateTime.parse(p['event_date'] as String),
    ),
    status: Value(p['status'] as String),
    // Defaulted columns: absent keeps the default rather than writing null,
    // which the non-nullable column would refuse.
    strengthDaysPerWeek: p['strength_days_per_week'] == null
        ? const Value.absent()
        : Value((p['strength_days_per_week'] as num).toInt()),
    commitments: Value(_commitmentsToFlat(p['commitments'])),
    timeTrialDistanceM: Value((p['time_trial_distance_m'] as num?)?.toDouble()),
    timeTrialSeconds: Value((p['time_trial_seconds'] as num?)?.toInt()),
    injuryNotes: Value(p['injury_notes'] as String?),
  );

  /// jsonb back to Drift's `weekday|meters|timed|label` rows, `;` separated.
  static String _commitmentsToFlat(Object? value) {
    if (value is! List || value.isEmpty) return '';
    return value
        .whereType<Map<dynamic, dynamic>>()
        .map((c) {
          final meters = c['distance_meters'];
          return <String>[
            '${c['weekday']}',
            meters == null ? '' : '${(meters as num).toDouble()}',
            c['timed'] == true ? '1' : '0',
            (c['label'] as String?) ?? '',
          ].join('|');
        })
        .join(';');
  }

  PlanWeeksCompanion _weekCompanion(Map<String, dynamic> w) =>
      PlanWeeksCompanion.insert(
        // Composite primary key (planId, weekNumber) locally — the server's
        // surrogate `id` has no counterpart here and is not carried over.
        planId: w['plan_id'] as String,
        weekNumber: (w['week_number'] as num).toInt(),
        phase: w['phase'] as String,
        targetVolumeM: (w['target_volume_m'] as num).toDouble(),
        longRunM: (w['long_run_m'] as num).toDouble(),
        isDeload: Value(w['is_deload'] as bool? ?? false),
      );

  PlanSessionsCompanion _sessionCompanion(Map<String, dynamic> s) =>
      PlanSessionsCompanion.insert(
        planId: s['plan_id'] as String,
        weekNumber: (s['week_number'] as num).toInt(),
        weekday: (s['weekday'] as num).toInt(),
        scheduledDate: DateTime.parse(s['scheduled_date'] as String),
        kind: s['kind'] as String,
        targetDistanceM: s['target_distance_m'] == null
            ? const Value.absent()
            : Value((s['target_distance_m'] as num).toDouble()),
        targetPaceSPerKm: Value(
          (s['target_pace_s_per_km'] as num?)?.toDouble(),
        ),
        rationale: Value(s['rationale'] as String?),
        // What the runner calls it. Absent on rows written before the column
        // existed, which read back as the bare kind exactly as they always did.
        label: Value(s['label'] as String?),
        status: Value(s['status'] as String? ?? 'planned'),
        provisional: Value(s['provisional'] as bool? ?? false),
        runId: Value(s['run_id'] as String?),
      );

  /// Runs [body], swallowing anything it throws.
  ///
  /// A restore is best-effort by nature: it runs at launch, over a connection
  /// nobody promised, and failing loudly would block the app on a network it
  /// does not need. Every write is repeatable, so a partial restore is simply
  /// continued next time.
  Future<void> _guard(Future<void> Function() body) async {
    try {
      await body();
    } on Object {
      // Deliberate — see above.
    }
  }
}

/// What a restore pulled, for a caller that wants to say so.
class RestoreResult {
  RestoreResult();

  factory RestoreResult.skipped() => RestoreResult()..skipped = true;

  /// True when consent had not been given, so nothing was attempted.
  bool skipped = false;
  int runs = 0;
  int plans = 0;
  int turns = 0;

  bool get restoredAnything => runs > 0 || plans > 0 || turns > 0;
}
