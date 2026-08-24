import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'coach_memory_tables.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// The on-device database — the offline-first source of truth for a run in
/// progress. Supabase is a backup and cross-device store, not the authority
/// for live recording (see docs/architecture/data-model.md).
@DriftDatabase(
  tables: [
    Runs,
    RunPoints,
    RunSplits,
    Plans,
    PlanWeeks,
    PlanSessions,
    CoachSummaries,
    CoachConversations,
    CoachTurns,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Opens the real on-device database file.
  AppDatabase.open() : this(_openConnection());

  @override
  int get schemaVersion => 7;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(runs, runs.endedAt);
      }
      if (from < 3) {
        // Plan persistence: purely additive, so existing runs are untouched.
        await m.createTable(plans);
        await m.createTable(planWeeks);
        await m.createTable(planSessions);
      }
      if (from < 4) {
        // Coach memory: additive too. Queries live in DriftCoachMemoryStore
        // rather than on this class, to keep the shared database file to the
        // registration above.
        await m.createTable(coachSummaries);
        await m.createTable(coachConversations);
        await m.createTable(coachTurns);
      }
      if (from < 5) {
        // Strength days on the stored profile. Defaulted to 0, so every plan
        // written before this reads back as "runs only" — which is what it was.
        await m.addColumn(plans, plans.strengthDaysPerWeek);
      }
      if (from < 6) {
        // A plan need not aim at a distance on a date (ADR-0011), so both
        // become nullable. SQLite cannot drop a NOT NULL in place, so the table
        // is rebuilt — existing rows keep their values and every one of them is
        // a block, which is what they were.
        await m.alterTable(TableMigration(plans));
        await m.addColumn(plans, plans.commitments);
      }
      if (from < 7) {
        // What the runner calls a session. Nullable and additive: every session
        // written before this had no label to lose, and reads back as the kind
        // it always displayed as.
        await m.addColumn(planSessions, planSessions.label);
      }
    },
  );

  // --- Runs ------------------------------------------------------------------

  /// Inserts or replaces a run.
  Future<void> upsertRun(RunsCompanion run) =>
      into(runs).insertOnConflictUpdate(run);

  /// All runs, most recent first.
  Future<List<RunRow>> allRuns() =>
      (select(runs)..orderBy([(r) => OrderingTerm.desc(r.startedAt)])).get();

  /// Watches all runs, most recent first.
  Stream<List<RunRow>> watchRuns() =>
      (select(runs)..orderBy([(r) => OrderingTerm.desc(r.startedAt)])).watch();

  /// A single run by id, or null.
  Future<RunRow?> runById(String id) =>
      (select(runs)..where((r) => r.id.equals(id))).getSingleOrNull();

  /// The most recent run that never finished recording (`endedAt` is null) —
  /// an interrupted run to recover after a crash, or null if there is none.
  Future<RunRow?> activeRun() =>
      (select(runs)
            ..where((r) => r.endedAt.isNull())
            ..orderBy([(r) => OrderingTerm.desc(r.startedAt)])
            ..limit(1))
          .getSingleOrNull();

  /// Deletes a run and everything belonging to it. Used to discard a cancelled
  /// run so its unfinished row (null `endedAt`) is not later mistaken for a
  /// recoverable run.
  Future<void> deleteRun(String id) => transaction(() async {
    await (delete(runPoints)..where((pt) => pt.runId.equals(id))).go();
    await (delete(runSplits)..where((s) => s.runId.equals(id))).go();
    await (delete(runs)..where((r) => r.id.equals(id))).go();
  });

  /// Rewrites the parts of a run a person is allowed to correct.
  ///
  /// **The trace is not one of them.** `run_points` and `run_splits` are what
  /// the device actually observed, and this deliberately cannot reach them: a
  /// recorded run stays a recorded run however its summary is corrected, which
  /// is the difference between fixing a number and rewriting history. That is
  /// also why `source` is absent — provenance is not editable, so a GPS run can
  /// never be laundered into a hand-typed one or the reverse.
  ///
  /// Consequence worth knowing: correcting the distance of a GPS run leaves its
  /// trace saying something else. That is intended. The trace is evidence and
  /// the summary is the runner's account of it, and when they disagree the
  /// runner wins for training purposes while the evidence stays intact.
  Future<void> updateRunDetails({
    required String runId,
    required DateTime startedAt,
    required int durationS,
    required double distanceM,
    double? avgPaceSPerKm,
    String? type,
    int? avgHr,
    int? rpe,
    String? notes,
  }) => (update(runs)..where((r) => r.id.equals(runId))).write(
    RunsCompanion(
      startedAt: Value(startedAt),
      durationS: Value(durationS),
      distanceM: Value(distanceM),
      avgPaceSPerKm: Value(avgPaceSPerKm),
      // Absent stays absent rather than becoming null: omitting a field in the
      // draft means "leave it", not "clear it".
      type: type == null ? const Value.absent() : Value(type),
      avgHr: Value(avgHr),
      rpe: Value(rpe),
      notes: Value(notes),
    ),
  );

  /// Marks a run finished and writes its computed summary.
  Future<void> finalizeRun({
    required String runId,
    required DateTime endedAt,
    required int durationS,
    required double distanceM,
    double? avgPaceSPerKm,
  }) => (update(runs)..where((r) => r.id.equals(runId))).write(
    RunsCompanion(
      endedAt: Value(endedAt),
      durationS: Value(durationS),
      distanceM: Value(distanceM),
      avgPaceSPerKm: Value(avgPaceSPerKm),
    ),
  );

  // --- Points (persisted as they arrive) -------------------------------------

  /// Appends a single recorded point. Called once per point during recording.
  Future<void> addRunPoint(RunPointsCompanion point) =>
      into(runPoints).insert(point);

  /// Writes a run's splits, replacing whatever was there.
  ///
  /// **Splits used to be computed and thrown away.** The recorder cut them live
  /// for the in-run readout and stored none, so `run_splits` was only ever
  /// filled by a restore pulling somebody else's copy back down — which meant a
  /// run finished on this phone had splits until the screen closed and none
  /// afterwards (ADR-0023 names this as one of the gaps local reads made
  /// visible). They are written on stop now, alongside the finalised summary.
  ///
  /// Replace rather than insert, so finishing the same run twice cannot leave
  /// two overlapping sets behind: the splits are a function of the trace, and
  /// the last walk over it is the answer. One transaction, so a crash part-way
  /// leaves the previous splits rather than half of the new ones.
  ///
  /// Not reachable from [updateRunDetails], and deliberately: splits are what
  /// the device observed, and correcting a run's summary does not rewrite what
  /// happened on the road (ADR-0016).
  Future<void> replaceRunSplits(String runId, List<RunSplitsCompanion> rows) =>
      transaction(() async {
        await (delete(runSplits)..where((s) => s.runId.equals(runId))).go();
        if (rows.isEmpty) return;
        await batch((b) => b.insertAll(runSplits, rows));
      });

  // --- Restore ---------------------------------------------------------------
  //
  // Every write here is **insert-or-ignore**, which is the whole contract of
  // the restore (SupabaseRestore): a row the phone already has always wins.
  //
  // The alternative — upsert — would let a pull overwrite a local edit made
  // while offline with the older copy the server still holds. That turns a
  // restore, which can only ever add, into a sync, which can lose. Runio has
  // one device, so there is nothing a merge could resolve that this cannot.

  /// Inserts runs the phone does not have. Existing rows are left untouched.
  Future<void> restoreRuns(List<RunsCompanion> rows) async {
    await batch(
      (b) => b.insertAll(runs, rows, mode: InsertMode.insertOrIgnore),
    );
  }

  Future<void> restoreRunPoints(List<RunPointsCompanion> rows) async {
    await batch(
      (b) => b.insertAll(runPoints, rows, mode: InsertMode.insertOrIgnore),
    );
  }

  Future<void> restoreRunSplits(List<RunSplitsCompanion> rows) async {
    await batch(
      (b) => b.insertAll(runSplits, rows, mode: InsertMode.insertOrIgnore),
    );
  }

  /// Restores a plan and its skeleton.
  ///
  /// Unlike [savePlan] this does **not** supersede whatever is active locally.
  /// A phone that already has a plan is not waiting to be told what its plan
  /// is, and demoting it from a backup would be the pull overruling the device
  /// that owns the truth (rule 1).
  Future<void> restorePlan({
    required PlansCompanion plan,
    required List<PlanWeeksCompanion> weeks,
    required List<PlanSessionsCompanion> sessions,
  }) => transaction(() async {
    await into(plans).insert(plan, mode: InsertMode.insertOrIgnore);
    await batch(
      (b) => b.insertAll(planWeeks, weeks, mode: InsertMode.insertOrIgnore),
    );
    await batch(
      (b) =>
          b.insertAll(planSessions, sessions, mode: InsertMode.insertOrIgnore),
    );
  });

  /// True when there is no plan at all on this device — the question a restore
  /// asks before pulling one, so it never has to choose between two.
  Future<bool> hasNoPlan() async =>
      (await (select(plans)..limit(1)).get()).isEmpty;

  /// Restores the coach's memory: the conversations, then their turns.
  ///
  /// Insert-or-ignore like the rest, which matters more here than anywhere
  /// else. A transcript is append-only by design — UPDATE is revoked from
  /// `authenticated` on the server table for exactly this reason — so a
  /// restore that overwrote turns would be rewriting a record of what the
  /// runner said about their own body. Ignoring duplicates is the only
  /// behaviour consistent with that.
  ///
  /// Conversations go in first: `coach_turns.conversationId` references them,
  /// so the other order would drop every turn on a foreign key.
  Future<void> restoreCoachMemory({
    required List<CoachConversationsCompanion> conversations,
    required List<CoachTurnsCompanion> turns,
  }) => transaction(() async {
    await batch(
      (b) => b.insertAll(
        coachConversations,
        conversations,
        mode: InsertMode.insertOrIgnore,
      ),
    );
    await batch(
      (b) => b.insertAll(coachTurns, turns, mode: InsertMode.insertOrIgnore),
    );
  });

  /// Restores the rolling summary, but only when there is not one already.
  ///
  /// The summary is a single row that is **replaced, never appended to**, and
  /// the local one is the newer of the two whenever the phone has been used
  /// since the last push. Overwriting it with the server's copy would hand the
  /// runner an older memory than the one their coach was just using.
  Future<void> restoreCoachSummary(CoachSummariesCompanion summary) =>
      into(coachSummaries).insert(summary, mode: InsertMode.insertOrIgnore);

  /// True when the coach remembers nothing on this device.
  Future<bool> hasNoCoachMemory() async =>
      (await (select(coachTurns)..limit(1)).get()).isEmpty;

  /// A run's splits, in order. Empty for a treadmill or hand-entered run, which
  /// is a normal state rather than missing data.
  Future<List<RunSplitRow>> splitsForRun(String runId) =>
      (select(runSplits)
            ..where((s) => s.runId.equals(runId))
            ..orderBy([(s) => OrderingTerm.asc(s.seq)]))
          .get();

  /// The trace for a run, in recorded order.
  Future<List<RunPointRow>> pointsForRun(String runId) =>
      (select(runPoints)
            ..where((pt) => pt.runId.equals(runId))
            ..orderBy([(pt) => OrderingTerm.asc(pt.seq)]))
          .get();

  // --- Plans -----------------------------------------------------------------

  /// The runner's current plan, or null if they have none. Newest first so a
  /// database that somehow holds two active plans still resolves to one.
  Future<PlanRow?> activePlan() =>
      (select(plans)
            ..where((p) => p.status.equals(planStatusActive))
            ..orderBy([(p) => OrderingTerm.desc(p.createdAt)])
            ..limit(1))
          .getSingleOrNull();

  /// Every plan ever stored for this runner, **oldest first**.
  ///
  /// No status filter: superseded plans are the point. `savePlan` has always
  /// kept them — a plan is a record of what someone committed to — and nothing
  /// read them back until there was a history to show.
  ///
  /// Ordered by creation rather than by start date because that is what makes a
  /// plan's *end* knowable: it stopped being active when the next one was
  /// created. A runner who built a plan starting next Monday and changed their
  /// mind the same afternoon would order wrongly by start date.
  Future<List<PlanRow>> allPlans() =>
      (select(plans)..orderBy([(p) => OrderingTerm.asc(p.createdAt)])).get();

  /// Stores a new plan and its skeleton, superseding any plan already active —
  /// **one transaction**, so a crash part-way leaves the old plan intact rather
  /// than a half-written new one.
  ///
  /// The old plan is marked `superseded`, never deleted: a plan is a record of
  /// what the runner committed to.
  Future<void> savePlan({
    required PlansCompanion plan,
    required List<PlanWeeksCompanion> weeks,
  }) => transaction(() async {
    await (update(plans)..where((p) => p.status.equals(planStatusActive)))
        .write(const PlansCompanion(status: Value(planStatusSuperseded)));
    await into(plans).insertOnConflictUpdate(plan);
    for (final week in weeks) {
      await into(planWeeks).insertOnConflictUpdate(week);
    }
  });

  /// The skeleton of a plan, in week order.
  Future<List<PlanWeekRow>> weeksForPlan(String planId) =>
      (select(planWeeks)
            ..where((w) => w.planId.equals(planId))
            ..orderBy([(w) => OrderingTerm.asc(w.weekNumber)]))
          .get();

  /// The generated sessions of one week, in weekday order. Empty when the week
  /// has not been generated yet — sessions come a week ahead of time.
  Future<List<PlanSessionRow>> sessionsForWeek(String planId, int weekNumber) =>
      (select(planSessions)
            ..where(
              (s) => s.planId.equals(planId) & s.weekNumber.equals(weekNumber),
            )
            ..orderBy([(s) => OrderingTerm.asc(s.weekday)]))
          .get();

  /// Replaces a week's sessions in one transaction. Days that dropped out of the
  /// week (an adaptation moving a run) are removed, so the stored week always
  /// matches the generated one — no orphaned sessions on days now at rest.
  ///
  /// Statuses the runner already set are preserved: rewriting the week's shape
  /// must not resurrect a session they had marked done.
  Future<void> replaceWeekSessions({
    required String planId,
    required int weekNumber,
    required List<PlanSessionsCompanion> sessions,
  }) => transaction(() async {
    final existing = await sessionsForWeek(planId, weekNumber);
    final priorStatus = <int, PlanSessionRow>{
      for (final row in existing) row.weekday: row,
    };
    await (delete(planSessions)..where(
          (s) => s.planId.equals(planId) & s.weekNumber.equals(weekNumber),
        ))
        .go();
    for (final session in sessions) {
      final prior = priorStatus[session.weekday.value];
      await into(planSessions).insert(
        prior == null || prior.status == sessionStatusPlanned
            ? session
            : session.copyWith(
                status: Value(prior.status),
                statusAt: Value(prior.statusAt),
                runId: Value(prior.runId),
              ),
      );
    }
  });

  /// The session in week [weekNumber] on [weekday] (1=Mon..7=Sun), or null when
  /// that day is a rest day.
  ///
  /// Addressed by slot rather than by date because a week slot is what a session
  /// row actually belongs to. A plan whose weeks cycle re-uses one slot every
  /// cycle, so its stored `scheduledDate` is only ever the occurrence that
  /// happened to be materialised first — looking a mark up by date found nothing
  /// from the second cycle onward.
  Future<PlanSessionRow?> sessionAt(
    String planId,
    int weekNumber,
    int weekday,
  ) =>
      (select(planSessions)
            ..where(
              (s) =>
                  s.planId.equals(planId) &
                  s.weekNumber.equals(weekNumber) &
                  s.weekday.equals(weekday),
            )
            ..limit(1))
          .getSingleOrNull();

  /// The session scheduled on [date] (date-only), or null for a rest day.
  Future<PlanSessionRow?> sessionOn(String planId, DateTime date) =>
      (select(planSessions)
            ..where(
              (s) =>
                  s.planId.equals(planId) &
                  s.scheduledDate.equals(
                    DateTime(date.year, date.month, date.day),
                  ),
            )
            ..limit(1))
          .getSingleOrNull();

  /// Marks a session done / skipped / planned again. A single row write that the
  /// caller awaits, so the mark is on disk before the UI shows it — not deferred
  /// to a later flush.
  ///
  /// Returns the number of rows changed: 0 means the session was not there,
  /// which the caller must not mistake for success.
  Future<int> setSessionStatus({
    required String planId,
    required int weekNumber,
    required int weekday,
    required String status,
    DateTime? statusAt,
  }) =>
      (update(planSessions)..where(
            (s) =>
                s.planId.equals(planId) &
                s.weekNumber.equals(weekNumber) &
                s.weekday.equals(weekday),
          ))
          .write(
            PlanSessionsCompanion(
              status: Value(status),
              statusAt: Value(status == sessionStatusPlanned ? null : statusAt),
            ),
          );
}

/// Plan lifecycle states, shared with `runio.plans.status`.
const String planStatusActive = 'active';
const String planStatusSuperseded = 'superseded';

/// The planned/completed/skipped wire value, shared with
/// `runio.plan_sessions.status`.
const String sessionStatusPlanned = 'planned';

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'runio.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
