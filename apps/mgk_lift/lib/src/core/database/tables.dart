import 'package:drift/drift.dart';

/// Local mirror of `lift.workouts`.
///
/// **The local schema is clean; the remote one is not.** `lift.*` still carries
/// the shape Liftio's SQLite origins gave it — epoch-millisecond integers for
/// dates, `integer` for booleans, `text` for timestamps. That schema holds 84
/// real workouts and 1,249 sets, so it was left alone during the 2026-08-06
/// restructure rather than migrated for tidiness.
///
/// So this table is written the way Dart wants it and the **sync layer converts
/// at the boundary**. One awkward conversion in one place beats every call site
/// remembering that `is_template` is an int.
///
/// The row class is named `WorkoutRow` to keep persistence rows distinct from
/// domain models.
@DataClassName('WorkoutRow')
class Workouts extends Table {
  /// UUID, shared with the Supabase row so local and remote reconcile.
  TextColumn get id => text()();

  TextColumn get name => text()();

  DateTimeColumn get startedAt => dateTime()();

  /// When the session finished. **Null while one is in progress** — the marker
  /// that makes an interrupted session recoverable after a crash, exactly as
  /// `mgk_run` uses it for a run. Without it, force-quitting mid-session loses
  /// the sets already logged, which is the one thing offline-first exists to
  /// prevent.
  DateTimeColumn get endedAt => dateTime().nullable()();

  IntColumn get durationS => integer().withDefault(const Constant(0))();

  TextColumn get notes => text().nullable()();

  /// A saved routine rather than a session that happened. Templates carry no
  /// date remotely (`date = 0`), which is why they must never reach the
  /// activity feed.
  ///
  /// **A template is outside the started/ended axis entirely.** It keeps a
  /// `startedAt` only because the column is not nullable — the value is when it
  /// was saved and means nothing else — and its `endedAt` stays null forever,
  /// which is the same shape as a session in progress. Anything asking "is
  /// there a session open" therefore has to exclude templates as well as
  /// finished rows; `DriftSessionRecorder.current()` does, and it is the one
  /// query where getting this wrong would hand a lifter their own template as
  /// a workout to resume.
  BoolColumn get isTemplate => boolean().withDefault(const Constant(false))();

  /// The saved workout this session was started from, if any. Set on a
  /// **session** row; null on a template.
  TextColumn get templateId => text().nullable()();

  /// The app-provided premade this template was added from, if any. Set on a
  /// **template** row; null on a session.
  ///
  /// **A second column rather than one field doing both jobs.** The two answer
  /// different questions about different rows — "which of my saved workouts did
  /// this session come from" and "which of the fifteen did this saved workout
  /// come from" — and `isTemplate` would have been the only thing separating
  /// them, so every reader would have had to check a flag before it could know
  /// what the string it was holding meant.
  ///
  /// It costs nothing to have both: `lift.workouts.premade_id` has existed
  /// remotely since the Liftio baseline, so this needs no Supabase migration
  /// and never will. The local migration is one `addColumn` now; after the
  /// write path ships it would be the same migration plus a backfill that has
  /// to guess which of the two meanings each existing value carried.
  TextColumn get premadeId => text().nullable()();

  /// The saved workout a session started from, **as it stood at the start** —
  /// encoded `TemplateMovement`s. Set on a session row, never on a template.
  ///
  /// It is what Finish compares the session against so the workout can learn
  /// from it (`MovementChange`), and it has to be the workout *as it was*:
  /// compared against the current one instead, an edit made on another device
  /// mid-session would read as something this session did.
  ///
  /// **Local only.** The sync layer names the columns it uploads and this is
  /// not one of them; it means nothing once the session has ended.
  TextColumn get templateSnapshot => text().nullable()();

  /// Soft delete. Kept rather than hard-deleted so a delete syncs to other
  /// devices instead of the row simply reappearing from the backup.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// When this row last reached the server.
  ///
  /// **Null means never uploaded, and `updatedAt > syncedAt` means changed
  /// since.** That comparison is the whole dirty-tracking mechanism: no
  /// separate outbox table to keep in step with the rows it describes, and no
  /// way for a write to land without also marking the row for upload, because
  /// the same `updatedAt` bump does both.
  DateTimeColumn get syncedAt => dateTime().nullable()();

  /// Why the server refused this row the last time it was sent — the raw
  /// `code: message`, for the log; the screen maps the code to a sentence. Null
  /// when the last attempt succeeded or none has been made.
  ///
  /// **A refused row waits for an edit, not for a retry.** Sending the same
  /// row again gets the same answer, and in a loop it would sit at the front of
  /// the queue forever; a row the lifter changes since
  /// ([lastSyncAttemptAt] older than [updatedAt]) is tried again. Local only.
  TextColumn get syncError => text().nullable()();

  /// Uploads attempted since the last success. Local only.
  IntColumn get syncAttempts => integer().withDefault(const Constant(0))();

  /// When an upload of this row was last attempted, succeeded or not. Local
  /// only.
  DateTimeColumn get lastSyncAttemptAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Where the last successful pull got to.
///
/// One row, keyed by name. A pull asks the server for everything changed since
/// this timestamp, so losing it means a full re-pull rather than lost data —
/// which is why it can live in the local database rather than anywhere safer.
@DataClassName('SyncMetaRow')
class SyncMeta extends Table {
  TextColumn get key => text()();
  DateTimeColumn get value => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Local mirror of `lift.exercises` — one movement within a session.
@DataClassName('ExerciseRow')
class Exercises extends Table {
  TextColumn get id => text()();

  TextColumn get workoutId =>
      text().references(Workouts, #id, onDelete: KeyAction.cascade)();

  /// The movement's name as the lifter typed or picked it. Deliberately free
  /// text rather than a foreign key into a catalogue: an exercise library that
  /// cannot express "smith machine incline press, feet up" is a library people
  /// work around.
  TextColumn get name => text()();

  IntColumn get orderIndex => integer().withDefault(const Constant(0))();

  TextColumn get notes => text().nullable()();

  /// Set when the movement is measured in time/distance rather than reps and
  /// load — a treadmill finisher, a sled push.
  TextColumn get cardioMode => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Local mirror of `core.progress_photos`.
///
/// **The row points at a file; it does not hold one.** Photos live as JPEGs in
/// the app's documents directory and this table stores the path. Putting image
/// bytes in SQLite would bloat the database that every set write goes through,
/// for data that is only ever read whole.
///
/// In `core` rather than `lift` remotely, because a body is not a lift-specific
/// concept — Run will want the same photos rather than a second set of them.
@DataClassName('PhotoRow')
class ProgressPhotos extends Table {
  TextColumn get id => text()();

  /// Monday midnight of the week this belongs to. One slot per (week, pose) —
  /// see the unique index below.
  DateTimeColumn get weekStart => dateTime()();

  /// `front` | `right_side` | `back` | `left_side`.
  TextColumn get poseType => text()();

  /// Absolute path on this device. **Not portable between installs** — the
  /// documents directory moves, so a restore has to rewrite these rather than
  /// trust them.
  TextColumn get path => text()();

  DateTimeColumn get takenAt => dateTime()();

  TextColumn get note => text().nullable()();

  /// Kept on disk, skipped during playback.
  BoolColumn get isExcluded => boolean().withDefault(const Constant(false))();

  DateTimeColumn get deletedAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// When this row last reached the bucket. Null means never.
  ///
  /// Same rule as `workouts.syncedAt`: dirty is `syncedAt is null or updatedAt
  /// is later`, so there is no outbox to fall out of step with the rows it
  /// describes. A tombstone is dirty too — that is what makes a delete
  /// propagate rather than the photo coming back down on the next pull.
  DateTimeColumn get syncedAt => dateTime().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  /// One live photo per week per pose. The slot *is* the model: retaking
  /// replaces rather than appends, so a week cannot end up with four front
  /// shots and no way to choose between them.
  @override
  List<String> get customConstraints => const <String>[];
}

/// Local mirror of `lift.sets` — one working set.
///
/// Named `ExerciseSets` rather than `Sets` because `sets` collides with the
/// generated accessor on the database class.
@DataClassName('SetRow')
class ExerciseSets extends Table {
  TextColumn get id => text()();

  TextColumn get exerciseId =>
      text().references(Exercises, #id, onDelete: KeyAction.cascade)();

  IntColumn get setNumber => integer().withDefault(const Constant(1))();

  IntColumn get reps => integer().withDefault(const Constant(0))();

  /// **Kilograms, always.** Store metric, convert at display — the suite-wide
  /// rule, and the reason a lifter can switch to pounds without their history
  /// changing meaning.
  ///
  /// Note this differs from the remote column, which holds whatever unit the
  /// account was set to when the row was written. Resolving that is the sync
  /// layer's job and it is not yet written; see the class comment on [Workouts].
  RealColumn get weightKg => real().withDefault(const Constant(0))();

  /// Whether the set was actually performed, as opposed to planned. A set is
  /// created the moment the row appears so the lifter can see it, and completed
  /// when they tick it off.
  BoolColumn get isCompleted => boolean().withDefault(const Constant(false))();

  /// `working` | `warmup` | `dropset` | `failure`.
  ///
  /// Warm-ups are excluded from volume and from every personal best. Counting
  /// them inflates the one number people actually care about — three empty-bar
  /// sets before a heavy single would read as a bigger session than the single.
  /// Defaults to `working`, so a set is only ever discounted deliberately.
  ///
  /// **Drop sets and failure sets count**, which is what the shipped app did.
  /// They are training that happened at a real load; the type records how it
  /// was performed, not whether it was worth anything. Only the warm-up is
  /// discounted, because only the warm-up was not the work.
  ///
  /// A plain text column rather than an enum, so a value written by a client
  /// this one has never heard of round-trips instead of failing. [SetType]
  /// reads anything unrecognised as `working`.
  TextColumn get setType => text().withDefault(const Constant('working'))();

  /// For cardio movements only.
  IntColumn get durationS => integer().nullable()();
  RealColumn get distanceM => real().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
