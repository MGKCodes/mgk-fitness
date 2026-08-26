import 'package:drift/drift.dart' show Value;

import '../../../core/database/app_database.dart';
import '../domain/plan_history.dart';
import '../domain/plan_shape.dart';
import '../domain/race_day.dart';
import '../domain/runner_profile.dart';
import '../domain/session_status.dart';
import '../domain/stored_plan.dart';
import '../domain/training_plan.dart';
import 'plan_mappers.dart';
import 'plan_store.dart';

/// The production [PlanStore]: the plan lives in the on-device database, which
/// is the source of truth (CLAUDE.md rule 1). Every read here is local — the
/// plan tab works in airplane mode, on a plane, in a tunnel.
///
/// Decoding is **strict**. A row that cannot be mapped back to a domain object
/// (an unknown phase, a week with no skeleton) raises [PlanStoreException]
/// rather than being skipped, so a schema mismatch surfaces instead of quietly
/// truncating someone's training block.
class DriftPlanStore implements PlanStore {
  DriftPlanStore(this._db);

  final AppDatabase _db;

  @override
  Future<StoredPlan?> loadActivePlan() async {
    final row = await _db.activePlan();
    if (row == null) return null;

    final weekRows = await _db.weeksForPlan(row.id);
    if (weekRows.isEmpty) {
      throw PlanStoreException(
        'plan ${row.id} has no skeleton weeks stored — refusing to present a '
        'plan with no arc',
      );
    }

    return StoredPlan(
      id: row.id,
      profile: _profileFrom(row),
      skeleton: PlanSkeleton(
        weeks: <SkeletonWeek>[
          for (final w in weekRows) _skeletonWeekFrom(w, row.id),
        ],
      ),
      startDate: _dateOnly(row.startDate),
    );
  }

  /// Every plan, oldest first, with each one's end derived from the next one's
  /// start.
  ///
  /// The derivation is the reason this reads the whole list at once: a plan
  /// stopped being active at the moment the plan after it was created, so no
  /// single row knows when it ended. Storing a `supersededAt` would have been a
  /// second copy of a fact the ordering already carries, and the two would
  /// eventually disagree.
  ///
  /// Unlike [loadActivePlan] this does not load skeletons and does not throw on
  /// a plan with no weeks. A history entry only needs the week *count*, which is
  /// on the row — and a plan too broken to open is still a plan the runner had,
  /// so refusing to list it would hide their own past from them.
  @override
  Future<List<PlanRecord>> loadHistory() async {
    final rows = await _db.allPlans();
    return <PlanRecord>[
      for (var i = 0; i < rows.length; i++)
        PlanRecord(
          id: rows[i].id,
          startDate: _dateOnly(rows[i].startDate),
          weeks: rows[i].weeks,
          isActive: rows[i].status == planStatusActive,
          goalDistanceMeters: rows[i].goalDistanceM,
          eventDate: rows[i].eventDate,
          // The next plan's creation is this plan's end. Null for the last row,
          // which is either the current plan or the newest a history has.
          endedAt: i + 1 < rows.length ? rows[i + 1].createdAt : null,
          // Read rather than derived, and only where it was written. A plan
          // stored before ADR-0027 has no ending recorded, so `closure` is
          // null and [PlanRecord.outcome] falls back to reading the dates
          // against each other exactly as it always did.
          closure: planClosureFromWire(rows[i].status),
          finishedAt: rows[i].finishedAt,
          raceTime: rows[i].raceTimeS == null
              ? null
              : Duration(seconds: rows[i].raceTimeS!),
        ),
    ];
  }

  @override
  Future<void> closePlan(
    StoredPlan plan, {
    required PlanClosure closure,
    Duration? raceTime,
  }) async {
    final changed = await _db.closePlan(
      planId: plan.id,
      status: planClosureToWire(closure),
      finishedAt: DateTime.now(),
      // A time can only belong to a race that happened. Enforced here as well
      // as at the call site because this is the last place the two can be held
      // apart before they are indistinguishable on disk.
      raceTime: closure == PlanClosure.raced ? raceTime : null,
    );
    if (changed == 0) {
      throw PlanStoreException(
        'plan ${plan.id} is not on this device — refusing to report it closed',
      );
    }
  }

  @override
  Future<void> savePlan(StoredPlan plan) async {
    final p = plan.profile;
    await _db.savePlan(
      plan: PlansCompanion.insert(
        id: plan.id,
        goalDistanceM: Value(p.goalDistanceMeters),
        eventDate: Value(p.eventDate),
        startDate: plan.startDate,
        weeks: plan.skeleton.weeks.length,
        currentWeeklyM: p.currentWeeklyMeters,
        longestRecentM: p.longestRecentMeters,
        daysPerWeek: p.daysPerWeek,
        strengthDaysPerWeek: Value(p.strengthDaysPerWeek),
        commitments: Value(encodeCommitments(p.commitments)),
        availableWeekdays: _weekdaysToCsv(p.availableWeekdays),
        timeTrialDistanceM: Value(p.timeTrialDistanceMeters),
        timeTrialSeconds: Value(p.timeTrialDuration?.inSeconds),
        injuryNotes: Value(p.injuryNotes),
      ),
      weeks: <PlanWeeksCompanion>[
        for (final w in plan.skeleton.weeks)
          PlanWeeksCompanion.insert(
            planId: plan.id,
            weekNumber: w.index,
            phase: phaseToWire(w.phase),
            targetVolumeM: w.volumeMeters,
            longRunM: w.longRunMeters,
            isDeload: Value(w.isDeload),
          ),
      ],
    );
  }

  @override
  Future<TrainingWeek?> loadWeek(StoredPlan plan, int weekNumber) async {
    final rows = await _db.sessionsForWeek(plan.id, weekNumber);
    if (rows.isEmpty) return null;
    return TrainingWeek(
      skeletonIndex: weekNumber,
      sessions: <PlannedSession>[
        for (final row in rows) _sessionFrom(row, plan.id),
      ],
      // Provisional is a property of the whole week; every row of a week carries
      // the same flag, so the first is authoritative.
      provisional: rows.first.provisional,
    );
  }

  @override
  Future<void> saveWeek(StoredPlan plan, TrainingWeek week) =>
      _db.replaceWeekSessions(
        planId: plan.id,
        weekNumber: week.skeletonIndex,
        sessions: <PlanSessionsCompanion>[
          // Only training days become rows — a rest day is the absence of one.
          for (final s in week.runs)
            PlanSessionsCompanion.insert(
              planId: plan.id,
              weekNumber: week.skeletonIndex,
              weekday: s.weekday,
              scheduledDate: plan.dateFor(
                weekIndex: week.skeletonIndex,
                weekday: s.weekday,
              ),
              kind: sessionKindToWire(s.kind),
              targetDistanceM: Value(s.distanceMeters),
              label: Value(s.label),
              provisional: Value(week.provisional),
            ),
        ],
      );

  /// The session row [date] falls on, addressed by the slot the date resolves to
  /// rather than by the stored `scheduledDate`.
  ///
  /// The two agree for a plan that goes somewhere: its weeks happen once, so a
  /// date and a slot name the same session. They part company for a rhythm,
  /// whose single slot recurs every cycle while `scheduledDate` keeps the one
  /// occurrence that was materialised first — so a parkrun runner's "mark done"
  /// looked up July, found a row dated May, and silently did nothing
  /// ([StoredPlan.dateFor]).
  Future<PlanSessionRow?> _rowOn(StoredPlan plan, DateTime date) =>
      _db.sessionAt(plan.id, plan.weekIndexOn(date), date.weekday);

  @override
  Future<SessionStatus?> statusOn(StoredPlan plan, DateTime date) async {
    final row = await _rowOn(plan, date);
    if (row == null) return null;
    final status = sessionStatusFromWire(row.status);
    if (status == null) {
      throw PlanStoreException(
        'session on ${_isoDate(date)} has unknown status "${row.status}"',
      );
    }
    return status;
  }

  @override
  Future<bool> setStatusOn(
    StoredPlan plan,
    DateTime date,
    SessionStatus status,
  ) async {
    final row = await _rowOn(plan, date);
    if (row == null) return false;
    final changed = await _db.setSessionStatus(
      planId: plan.id,
      weekNumber: row.weekNumber,
      weekday: row.weekday,
      status: sessionStatusToWire(status),
      statusAt: DateTime.now(),
    );
    return changed > 0;
  }

  // --- row → domain ----------------------------------------------------------

  RunnerProfile _profileFrom(PlanRow row) => RunnerProfile(
    goalDistanceMeters: row.goalDistanceM,
    eventDate: row.eventDate,
    currentWeeklyMeters: row.currentWeeklyM,
    longestRecentMeters: row.longestRecentM,
    daysPerWeek: row.daysPerWeek,
    strengthDaysPerWeek: row.strengthDaysPerWeek,
    commitments: decodeCommitments(row.commitments),
    availableWeekdays: _weekdaysFromCsv(row.availableWeekdays, row.id),
    timeTrialDistanceMeters: row.timeTrialDistanceM,
    timeTrialDuration: row.timeTrialSeconds == null
        ? null
        : Duration(seconds: row.timeTrialSeconds!),
    injuryNotes: row.injuryNotes,
  );

  SkeletonWeek _skeletonWeekFrom(PlanWeekRow row, String planId) {
    final phase = phaseFromWire(row.phase);
    if (phase == null) {
      throw PlanStoreException(
        'plan $planId week ${row.weekNumber} has unknown phase "${row.phase}"',
      );
    }
    return SkeletonWeek(
      index: row.weekNumber,
      phase: phase,
      volumeMeters: row.targetVolumeM,
      longRunMeters: row.longRunM,
      isDeload: row.isDeload,
    );
  }

  PlannedSession _sessionFrom(PlanSessionRow row, String planId) {
    final kind = sessionKindFromWire(row.kind);
    if (kind == null) {
      throw PlanStoreException(
        'plan $planId week ${row.weekNumber} day ${row.weekday} has unknown '
        'kind "${row.kind}"',
      );
    }
    return PlannedSession(
      weekday: row.weekday,
      kind: kind,
      distanceMeters: row.targetDistanceM,
      // The runner's own word for it, when they gave one. Unwritten until the
      // column existed, so every rhythm session came back as its bare kind.
      label: row.label,
    );
  }

  Set<int> _weekdaysFromCsv(String csv, String planId) {
    final days = <int>{};
    for (final part in csv.split(',')) {
      final trimmed = part.trim();
      if (trimmed.isEmpty) continue;
      final day = int.tryParse(trimmed);
      if (day == null || day < DateTime.monday || day > DateTime.sunday) {
        throw PlanStoreException(
          'plan $planId has an unreadable available-weekdays list',
        );
      }
      days.add(day);
    }
    if (days.isEmpty) {
      throw PlanStoreException('plan $planId has no available weekdays');
    }
    return days;
  }

  static String _weekdaysToCsv(Set<int> days) =>
      (days.toList()..sort()).join(',');

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _isoDate(DateTime d) => d.toIso8601String().split('T').first;
}
