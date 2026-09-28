import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/recording/domain/best_effort.dart';
import '../../features/recording/domain/run_point.dart';
import 'coach_memory_tables.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// The on-device database — the offline-first source of truth for a run in
/// progress. Supabase is a backup and cross-device store, not the authority
/// for live recording (see docs/architecture/data-model.md).
///
/// **The two imports above are the only place `core/` reaches into
/// `features/`, and they are deliberate.** `run_point.dart` and
/// `best_effort.dart` are dependency-free value types and pure functions;
/// neither knows this file exists, so nothing here is circular. They are needed
/// because schema 9's migration backfills the records table from traces already
/// on the phone, and the alternative was worse in both directions: a migration
/// that creates a table it cannot fill, and a backfill fired from the
/// composition root that would need a new column purely to remember whether it
/// had already run. Exactly-once is what a schema version *is* — borrowing a
/// pure function is cheaper than building a second mechanism to say it again.
@DriftDatabase(
  tables: [
    Runs,
    RunPoints,
    RunSplits,
    RunBestEfforts,
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
  int get schemaVersion => 10;

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
      if (from < 8) {
        // Steps and the route's high point, so a summary can say what Strava
        // says. Nullable and additive, and deliberately not backfilled: a run
        // recorded before this genuinely has no step count, and inventing one
        // from distance and an assumed stride would be the app making up a
        // number it is about to display as measured.
        await m.addColumn(runs, runs.elevationMaxM);
        await m.addColumn(runs, runs.steps);
      }
      if (from < 9) {
        // Personal bests at the standard distances, cut from the trace the way
        // the splits are. Additive: a new table, and nothing already stored
        // changes meaning.
        await m.createTable(runBestEfforts);
        // **And backfilled, which the previous migration deliberately was
        // not.** Schema 8 refused to invent a step count for an old run, and
        // was right to: there was no evidence on the phone that could produce
        // one, so a backfill there would have been the app making up a number
        // it was about to display as measured. That argument does not reach
        // this table. The evidence is already here — `run_points` holds every
        // fix of every run — and [backfillBestEfforts] runs exactly the same
        // window over exactly the same trace the recorder would have run at
        // the finish line. The answer is not an estimate of the record; it is
        // the record. Leaving it out would mean a runner with a year of
        // recorded running opened Records and saw four dashes, over a database
        // that could answer all four.
        //
        // The cost is bounded by construction, which is the only reason it is
        // safe to do here rather than off the critical path. This runs once,
        // on a database that predates schema 9 — that is, one built during the
        // app's pre-release life. Every run recorded from here on gets its
        // efforts written at `stop()`, so no future log ever reaches this line,
        // however long it grows.
        await backfillBestEfforts();
      }
      if (from < 10) {
        // A plan can now reach its own end rather than only being replaced
        // (ADR-0027): when it was closed out, and what the runner ran on the
        // day. Nullable and additive, and **not backfilled**, which puts this
        // migration on schema 8's side of the line rather than schema 9's.
        //
        // The difference is once again the evidence. Schema 9 could recompute a
        // record because `run_points` held every fix of every run, so the
        // backfill produced the record rather than an estimate of it. Nothing
        // on the phone can say whether a runner who has an old block on disk
        // actually ran that race: a run on the day is suggestive and no run at
        // all means nothing, since the phone may simply have stayed in the
        // hotel. Writing `completed` on that basis would be the app filing a
        // result on the runner's behalf for a race it did not see — and unlike
        // a wrong step count, it would appear in their history as a race they
        // ran and in the coach's brief as a block they saw through.
        //
        // So every plan already on disk keeps the status it has. The plans that
        // predate this are pre-release ones belonging to this app's own
        // testing, and [overdueClosureFor] closes any of them whose race is
        // long past the next time the runner opens the app — from the log,
        // which is the same evidence a runner would be shown before confirming.
        await m.addColumn(plans, plans.finishedAt);
        await m.addColumn(plans, plans.raceTimeS);
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
    await (delete(runBestEfforts)..where((e) => e.runId.equals(id))).go();
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
  ///
  /// **The elevation figures go down with the run**, from the same walk over
  /// the same persisted trace the distance comes from. Climb was computed on
  /// every fix for the in-run readout and then dropped on the floor, exactly
  /// the way the splits were: a runner watched a climb figure tick up for an
  /// hour and the summary afterwards had nowhere to read it from.
  ///
  /// Both are nullable and both are *usually* null, which is the designed-for
  /// state rather than a gap — `climbMeters` and `maxElevationMeters` answer
  /// null on a trace with no barometric altitude, and a null here renders as an
  /// absent tile rather than as `0 m`.
  Future<void> finalizeRun({
    required String runId,
    required DateTime endedAt,
    required int durationS,
    required double distanceM,
    double? avgPaceSPerKm,
    double? elevationGainM,
    double? elevationMaxM,
  }) => (update(runs)..where((r) => r.id.equals(runId))).write(
    RunsCompanion(
      endedAt: Value(endedAt),
      durationS: Value(durationS),
      distanceM: Value(distanceM),
      avgPaceSPerKm: Value(avgPaceSPerKm),
      elevationGainM: Value(elevationGainM),
      elevationMaxM: Value(elevationMaxM),
    ),
  );

  /// Writes what Health said about a finished run.
  ///
  /// **Separate from [finalizeRun], because it happens later and might not
  /// happen at all.** The Health read is a platform round trip behind a
  /// permission the runner may have declined; making it part of finalising
  /// would put the run's own numbers behind somebody else's daemon. The run
  /// commits first and this arrives after, or never.
  ///
  /// Only ever called with a value. There is no "clear the steps" here on
  /// purpose: a read that came back with nothing must not overwrite a figure
  /// already stored, because "Health told us nothing this time" and "this run
  /// had no steps" are the same answer and only one of them is worth writing
  /// down (CLAUDE.md rule 6).
  Future<void> recordRunSteps({required String runId, required int steps}) =>
      (update(runs)..where((r) => r.id.equals(runId))).write(
        RunsCompanion(steps: Value(steps)),
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

  // --- Records ---------------------------------------------------------------

  /// Writes a run's best efforts, replacing whatever was there.
  ///
  /// Replace rather than insert, for [replaceRunSplits]'s reason: the efforts
  /// are a function of the trace, and the last walk over it is the answer.
  /// Finishing the same run twice must not leave two sets behind, and an empty
  /// list is a real answer — a run too short to hold a record — so it clears
  /// the rows rather than skipping the write.
  ///
  /// Not reachable from [updateRunDetails], for the same reason splits are not:
  /// a record is what the device observed, and correcting a run's summary does
  /// not rewrite the road (ADR-0016). Correcting a GPS run's distance therefore
  /// leaves its records saying what the trace said, which is intended.
  Future<void> replaceRunBestEfforts(
    String runId,
    List<RunBestEffortsCompanion> rows,
  ) => transaction(() async {
    await (delete(runBestEfforts)..where((e) => e.runId.equals(runId))).go();
    if (rows.isEmpty) return;
    await batch((b) => b.insertAll(runBestEfforts, rows));
  });

  /// One run's records, shortest distance first. Empty is the ordinary answer:
  /// most runs are shorter than 5 km, and a run with no trace has no interior
  /// to have searched.
  Future<List<RunBestEffortRow>> bestEffortsForRun(String runId) =>
      (select(runBestEfforts)
            ..where((e) => e.runId.equals(runId))
            ..orderBy([(e) => OrderingTerm.asc(e.distanceM)]))
          .get();

  /// Every stored record, for folding a lifetime best out of.
  ///
  /// Four rows per run at the very most, and none at all for the majority —
  /// which is what makes it safe to read the lot on the way to a screen. The
  /// traces these came from are thousands of rows each and are never touched
  /// again after the run that produced them (ADR-0026).
  Future<List<RunBestEffortRow>> allBestEfforts() =>
      select(runBestEfforts).get();

  /// Computes and stores the records of every traced run that has none, and
  /// answers how many runs it filled.
  ///
  /// **Called once, from schema 9's migration.** Runs recorded from then on get
  /// their efforts written when they finish, so nothing reaches this afterwards
  /// — but it is written to be safe to call twice: a run that already has rows
  /// is skipped rather than recomputed.
  ///
  /// **The filter is "has a trace", and nothing else.** Skipping runs whose
  /// stored `distanceM` is under 5 km would be faster and is wrong: a run's
  /// distance is editable and its trace is not (ADR-0016), so a GPS run whose
  /// summary was corrected down to 4 km can still hold a 5 km stretch of road,
  /// and it is the road that a record is read off. A run with no points is
  /// skipped because there is genuinely nothing to search.
  ///
  /// Plain inserts, no batch and no transaction. Both of drift's bulk helpers
  /// open a transaction of their own, and this runs inside `onUpgrade`, where
  /// nesting one is at best pointless. The write it replaces is four rows per
  /// run.
  Future<int> backfillBestEfforts() async {
    final traced =
        await (selectOnly(runPoints, distinct: true)
              ..addColumns(<Expression<Object>>[runPoints.runId]))
            .map((row) => row.read(runPoints.runId)!)
            .get();
    if (traced.isEmpty) return 0;

    final done =
        (await (selectOnly(runBestEfforts, distinct: true)
                  ..addColumns(<Expression<Object>>[runBestEfforts.runId]))
                .map((row) => row.read(runBestEfforts.runId)!)
                .get())
            .toSet();

    var filled = 0;
    for (final runId in traced) {
      if (done.contains(runId)) continue;
      // One run's trace at a time, so peak memory is one run rather than the
      // whole log however long the log is.
      final rows = await pointsForRun(runId);
      final efforts = bestEffortsFor(<RunPoint>[
        for (final row in rows)
          RunPoint(
            latitude: row.lat,
            longitude: row.lng,
            accuracyMeters: row.accuracyM,
            altitudeMeters: row.altitudeM,
            timestamp: row.timestamp,
          ),
      ]);
      if (efforts.isEmpty) continue;
      for (final effort in efforts) {
        await into(runBestEfforts).insert(
          RunBestEffortsCompanion.insert(
            runId: runId,
            distanceM: effort.distanceMeters,
            durationS: effort.duration.inSeconds,
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
      filled++;
    }
    return filled;
  }

  // --- Restore ---------------------------------------------------------------
  //
  // Every write here is **insert-or-ignore**, which is the whole contract of
  // the restore (SupabaseRestore): a row the phone already has always wins.
  //
  // The alternative — upsert — would let a pull overwrite a local edit made
  // while offline with the older copy the server still holds. That turns a
  // restore, which can only ever add, into a sync, which can lose. Runio has
  // one device, so there is nothing a merge could resolve that this cannot.

  /// Inserts runs the phone does not have, and returns **how many it added**.
  ///
  /// The count is taken here rather than by the caller because this is the only
  /// place that knows. Writes are insert-or-ignore, so the number of rows handed
  /// in says nothing about the number that landed — and [SupabaseRestore] used
  /// to return the length of what it *fetched*, which meant a runner with 21
  /// runs on the server was told "restored 21 runs" on every launch forever,
  /// having restored nothing at all since the first one. The same question asked
  /// of a plan and of the coach's memory is already answered against the
  /// database, by [hasNoPlan] and [hasNoCoachMemory]; runs merge rather than
  /// gate, so they need a delta instead of a flag.
  ///
  /// In one transaction so the two counts cannot straddle another write.
  Future<int> restoreRuns(List<RunsCompanion> rows) => transaction(() async {
    final before = await _runCount();
    await batch(
      (b) => b.insertAll(runs, rows, mode: InsertMode.insertOrIgnore),
    );
    return await _runCount() - before;
  });

  Future<int> _runCount() async {
    final count = runs.id.count();
    final row = await (selectOnly(
      runs,
    )..addColumns(<Expression<Object>>[count])).getSingle();
    return row.read(count) ?? 0;
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

  /// Closes a plan out: it reached its own end rather than being replaced.
  ///
  /// **Deliberately narrow.** It writes three columns and cannot reach the
  /// skeleton, the sessions or the profile snapshot — a finished plan is still
  /// the record of what the runner committed to, and closing it must not be a
  /// door to editing it. It is the same restraint [updateRunDetails] applies to
  /// a run's trace (ADR-0016), for the same reason.
  ///
  /// Scoped by id rather than by "the active plan", so closing one twice — a
  /// double tap, or the auto-close racing the runner's own confirmation — is
  /// idempotent rather than reaching whatever is active by then.
  ///
  /// Returns the number of rows changed, so a caller cannot mistake a write
  /// against a plan that is no longer there for success.
  Future<int> closePlan({
    required String planId,
    required String status,
    required DateTime finishedAt,
    Duration? raceTime,
  }) => (update(plans)..where((p) => p.id.equals(planId))).write(
    PlansCompanion(
      status: Value(status),
      finishedAt: Value(finishedAt),
      // Written as an explicit null for a runner who did not race, so a plan
      // closed twice cannot keep a time from the first attempt.
      raceTimeS: Value(raceTime?.inSeconds),
    ),
  );

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
///
/// Four, and they divide two ways. A plan is [planStatusSuperseded] when
/// another plan takes its place, which can happen in week two and says nothing
/// about how it went. It is [planStatusCompleted] or [planStatusAbandoned] when
/// it reaches its **own** end — race day arrived, and the runner either ran it
/// or did not (ADR-0027). The last two were documented from the day the table
/// was written and nothing produced either of them for a year.
const String planStatusActive = 'active';
const String planStatusSuperseded = 'superseded';
const String planStatusCompleted = 'completed';
const String planStatusAbandoned = 'abandoned';

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
