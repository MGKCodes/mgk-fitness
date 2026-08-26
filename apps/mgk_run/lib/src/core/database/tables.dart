import 'package:drift/drift.dart';

/// Local mirror of the `runs` table (see docs/architecture/data-model.md).
///
/// All distances/paces are stored in **metric**. The row class is named
/// `RunRow` to keep persistence rows distinct from domain models.
@DataClassName('RunRow')
class Runs extends Table {
  /// UUID, shared with the Supabase row so local and remote reconcile.
  TextColumn get id => text()();

  DateTimeColumn get startedAt => dateTime()();

  /// When recording finished. **Null while a run is in progress** — the marker
  /// used to recover an interrupted run after a crash (see run-recording.md).
  DateTimeColumn get endedAt => dateTime().nullable()();

  IntColumn get durationS => integer()();
  RealColumn get distanceM => real()();
  RealColumn get avgPaceSPerKm => real().nullable()();
  RealColumn get elevationGainM => real().nullable()();

  /// The highest point on the route, in metres above sea level.
  ///
  /// Distinct from [elevationGainM], which is the sum of every climb: a runner
  /// doing hill repeats has enormous gain and an unremarkable maximum, and a
  /// runner going up one mountain has the opposite. Strava shows both for the
  /// same reason.
  RealColumn get elevationMaxM => real().nullable()();
  IntColumn get avgHr => integer().nullable()();
  IntColumn get maxHr => integer().nullable()();
  IntColumn get cadence => integer().nullable()();

  /// Steps taken, read from Health rather than counted here.
  ///
  /// Nullable and expected to be null often: a runner who declined the Health
  /// read is indistinguishable from one whose phone recorded nothing, and both
  /// are shown as absent rather than as zero.
  IntColumn get steps => integer().nullable()();
  RealColumn get caloriesEst => real().nullable()();

  /// `gps` | `healthkit` | `manual`.
  TextColumn get source => text()();

  /// `outdoor` | `treadmill`.
  TextColumn get type => text()();

  /// Source-specific id (e.g. HKWorkout UUID) used for deduplication.
  TextColumn get externalId => text().nullable()();

  IntColumn get rpe => integer().nullable()();
  TextColumn get notes => text().nullable()();

  /// The planned session this run fulfilled, if any.
  TextColumn get sessionId => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The raw GPS trace for a run. A point is persisted here **as it arrives**;
/// a run is never held only in memory (see run-recording.md).
@DataClassName('RunPointRow')
class RunPoints extends Table {
  TextColumn get runId => text().references(Runs, #id)();
  IntColumn get seq => integer()();
  RealColumn get lat => real()();
  RealColumn get lng => real()();

  /// Barometric altitude in meters, if available.
  RealColumn get altitudeM => real().nullable()();

  /// Horizontal accuracy in meters; larger is worse.
  RealColumn get accuracyM => real()();

  DateTimeColumn get timestamp => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {runId, seq};
}

/// Per-unit splits for a run. Absent for treadmill/manual runs.
@DataClassName('RunSplitRow')
class RunSplits extends Table {
  TextColumn get runId => text().references(Runs, #id)();
  IntColumn get seq => integer()();
  RealColumn get distanceM => real()();
  IntColumn get durationS => integer()();
  IntColumn get avgHr => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {runId, seq};
}

/// A training block — the local mirror of `runio.plans`, and the **source of
/// truth** for the plan (Supabase is a backup; see data-model.md).
///
/// The row carries a **snapshot of the runner profile the plan was built for**.
/// The validator checks a skeleton against a profile
/// (docs/architecture/plan-generation.md); reading the profile live would mean a
/// later profile edit retroactively invalidates a stored plan. Snapshotting
/// keeps a reloaded plan exactly as valid as the day it was generated.
///
/// Metric throughout — imperial exists only at the display layer.
@DataClassName('PlanRow')
class Plans extends Table {
  /// Client-generated id, shared with the Supabase row. Same convention as
  /// [Runs.id].
  TextColumn get id => text()();

  /// The goal distance, when there is one. Nullable because a plan need not be
  /// aimed at a distance — see ADR-0011.
  RealColumn get goalDistanceM => real().nullable()();
  IntColumn get goalTimeS => integer().nullable()();

  /// Race day, when there is a race. Null with a goal set is a horizon plan:
  /// a distance to reach with nothing entered yet.
  DateTimeColumn get eventDate => dateTime().nullable()();

  /// The Monday of week 1 — what maps a week index onto real calendar dates, so
  /// today's session stays correct as weeks pass.
  DateTimeColumn get startDate => dateTime()();

  IntColumn get weeks => integer()();

  /// `active` | `superseded` | `completed` | `abandoned`. Running the coach
  /// again supersedes the previous plan rather than deleting it.
  ///
  /// `completed` and `abandoned` are the two ways a plan reaches its **own**
  /// end rather than being replaced: the runner got to race day and ran it, or
  /// race day came and went without them (ADR-0027). Both were documented here
  /// from the day the table was written and neither was ever produced, which is
  /// how a sixteen-week block came to end by being quietly superseded.
  TextColumn get status => text().withDefault(const Constant('active'))();

  /// When the plan was closed out. Null while it is still running.
  ///
  /// **Its presence is what makes an ending knowable.** A plan's end was
  /// otherwise derived from the creation date of whatever replaced it
  /// (`plan_history.dart`), which is exactly right for a plan that *was*
  /// replaced and says nothing at all about one that simply finished — a runner
  /// who ran their marathon and has not started anything since had a plan with
  /// no end date and no way to tell it from the plan they are on.
  DateTimeColumn get finishedAt => dateTime().nullable()();

  /// The finish time the runner confirmed on race day, in seconds.
  ///
  /// **Stored rather than re-derived, and that is deliberate against the usual
  /// rule here.** Most of what this app shows about a run is read back off the
  /// log every time, because a second copy of a fact eventually disagrees with
  /// the first. A race result is the exception: it is what the runner *agreed*
  /// their race was, and the evidence underneath it is allowed to move without
  /// taking it with them. A GPS run edited down to 41.8 km (ADR-0016 permits
  /// exactly that), or deleted a year later, must not silently rewrite the
  /// marathon time they tell people.
  ///
  /// Null with a `completed` status means they raced and the app does not know
  /// the time — which happens, and is a better thing to store than a guess.
  IntColumn get raceTimeS => integer().nullable()();

  // --- runner profile snapshot ---
  RealColumn get currentWeeklyM => real()();
  RealColumn get longestRecentM => real()();
  IntColumn get daysPerWeek => integer()();

  /// Available weekdays as a sorted comma-separated list of `1`(Mon)..`7`(Sun) —
  /// SQLite has no array type, and Drift's mirror stays flat on purpose.
  TextColumn get availableWeekdays => text()();

  /// Repeating commitments, as `weekday|meters|timed|label` rows separated by
  /// `;`. Flat for the same reason as [availableWeekdays]. Empty for every
  /// shape but a rhythm.
  TextColumn get commitments => text().withDefault(const Constant(''))();

  /// Strength sessions a week, on top of the runs. Defaulted rather than
  /// nullable so plans written before strength existed read back as zero, which
  /// is what they meant.
  IntColumn get strengthDaysPerWeek =>
      integer().withDefault(const Constant(0))();

  RealColumn get timeTrialDistanceM => real().nullable()();
  IntColumn get timeTrialSeconds => integer().nullable()();
  TextColumn get injuryNotes => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// One week of the skeleton — the arc, generated once at plan creation
/// (plan-generation.md, stage 1). Mirrors `runio.plan_weeks`.
@DataClassName('PlanWeekRow')
class PlanWeeks extends Table {
  TextColumn get planId => text().references(Plans, #id)();

  /// 1-based position in the plan.
  IntColumn get weekNumber => integer()();

  /// `base` | `build` | `peak` | `taper`.
  TextColumn get phase => text()();

  RealColumn get targetVolumeM => real()();
  RealColumn get longRunM => real()();
  BoolColumn get isDeload => boolean().withDefault(const Constant(false))();

  DateTimeColumn get generatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {planId, weekNumber};
}

/// A generated session (plan-generation.md, stage 2 — one week ahead, so a week
/// legitimately has no sessions yet). Mirrors `runio.plan_sessions`.
///
/// One row per **training** day: a rest day is the *absence* of a row. The
/// primary key `(planId, weekNumber, weekday)` means regenerating or adapting a
/// week updates it in place instead of duplicating sessions.
@DataClassName('PlanSessionRow')
class PlanSessions extends Table {
  TextColumn get planId => text().references(Plans, #id)();
  IntColumn get weekNumber => integer()();

  /// `DateTime.monday`(1)..`DateTime.sunday`(7).
  IntColumn get weekday => integer()();

  /// Derived from the plan's [Plans.startDate] and stored, so today's session is
  /// a plain indexed lookup rather than arithmetic against whenever the app was
  /// last opened. Date-only (midnight local).
  DateTimeColumn get scheduledDate => dateTime()();

  /// `rest` | `recovery` | `easy` | `long` | `marathon_pace` | `threshold` |
  /// `interval`.
  TextColumn get kind => text()();

  RealColumn get targetDistanceM => real().withDefault(const Constant(0))();

  /// **What the runner calls this session**, when they call it something.
  ///
  /// The plan builder sets it from a [PlanCommitment] — "parkrun" rather than
  /// "Easy 5 km" — and it had nowhere to be written, so every rhythm runner's
  /// own word for their own session was dropped on the way to disk and read
  /// back as the generic kind. The headline kept it (it reads the profile) and
  /// the week lost it, so one screen said "Your parkrun week" over a Saturday
  /// labelled "Easy".
  TextColumn get label => text().nullable()();

  /// Nullable and unwritten by the app: paces are derived deterministically in
  /// Dart from the time trial at display time (pace_model.dart). Present for a
  /// coach-authored override, not as a cache of a derived value.
  RealColumn get targetPaceSPerKm => real().nullable()();

  /// Validated workout structure (e.g. intervals) — never raw model text.
  TextColumn get structureJson => text().nullable()();
  TextColumn get rationale => text().nullable()();

  /// `planned` | `completed` | `skipped`.
  TextColumn get status => text().withDefault(const Constant('planned'))();

  /// When the runner marked it. Null while planned.
  DateTimeColumn get statusAt => dateTime().nullable()();

  /// True when the week was filled deterministically from the skeleton rather
  /// than generated — plan-generation.md's provisional fallback.
  BoolColumn get provisional => boolean().withDefault(const Constant(false))();

  /// The run that fulfilled this session, if any.
  TextColumn get runId => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {planId, weekNumber, weekday};
}

/// A run's fastest continuous stretch at each of the standard distances —
/// **searched for inside the run, not read off its summary**.
///
/// Rows here are derived from `run_points` at the moment the run finishes, from
/// the same walk over the same trace the distance, the splits and the elevation
/// figures come from. See `best_effort.dart` for the window itself, and
/// ADR-0026 for why the whole run's time is not an acceptable substitute.
///
/// **Absence is the normal state and it carries meaning.** A run with no row
/// for a distance did not contain that distance: it was too short, or it has no
/// trace to search at all because it was typed in by hand or came from Health.
/// Neither is a gap to be filled in later with the run's own time — that would
/// put two different measurements in one column, and nothing reading it back
/// could tell them apart.
///
/// Metric, like everything stored: 21,097.5 m is a half marathon, and the word
/// for it belongs at the display layer (CLAUDE.md rule 4).
@DataClassName('RunBestEffortRow')
class RunBestEfforts extends Table {
  TextColumn get runId => text().references(Runs, #id)();

  /// The record distance, exactly — one of `kRecordDistancesMeters`.
  RealColumn get distanceM => real()();

  IntColumn get durationS => integer()();

  @override
  Set<Column<Object>> get primaryKey => {runId, distanceM};
}
