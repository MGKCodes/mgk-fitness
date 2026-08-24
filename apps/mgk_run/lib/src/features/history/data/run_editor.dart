import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/ids.dart';
import '../domain/run_draft.dart';
import '../domain/run_writer.dart';
import 'run_backup.dart';

/// Adds and corrects runs — the write half of "the log is the runner's, not the
/// device's".
///
/// One service, two callers, on purpose. The manual-entry form calls it, and so
/// will the coach when it hears "I did 5k in 26 minutes this morning". Giving
/// the conversational path its own write path would mean two sets of rules
/// about what a legal run is, and the one that got skipped would be the one
/// nobody typed into.
///
/// Every method refuses an invalid draft rather than repairing it. A validator
/// that silently fixes things is a validator whose failures are invisible, and
/// the confirmation step the coach shows the runner is only meaningful if what
/// they confirmed is what gets written.
class RunEditor implements RunWriter {
  RunEditor({
    required AppDatabase db,
    RunBackup? backup,
    DateTime Function() now = DateTime.now,
    String Function()? newId,
  }) : _db = db,
       _backup = backup,
       _now = now,
       _newId = newId ?? _defaultId;

  final AppDatabase _db;

  /// Where the run is mirrored after it is stored. Null means local only,
  /// which is what a build with no backend or a dev persona wants.
  final RunBackup? _backup;
  final DateTime Function() _now;
  final String Function() _newId;

  /// Client-generated, matching the convention `run.runs.id` is built on: the
  /// device owns the identity so a run is the same row on the phone and in the
  /// backup, with no round trip to find out what it is called.
  ///
  /// The `manual-` prefix is kept for the runs a person typed, but the identity
  /// is no longer the clock — see [newLocalId] for the collision that cost.
  static String _defaultId() => newLocalId('manual-');

  /// Writes a new hand-entered run, returning its id.
  ///
  /// Throws [RunDraftInvalid] if the draft does not pass [RunDraft.issues], so a
  /// caller cannot write an unchecked run by forgetting to look.
  @override
  Future<String> add(RunDraft draft) async {
    final issues = draft.issues(_now());
    if (issues.isNotEmpty) throw RunDraftInvalid(issues);

    final id = _newId();
    await _db.upsertRun(
      RunsCompanion.insert(
        id: id,
        startedAt: draft.startedAt!,
        durationS: draft.duration!.inSeconds,
        distanceM: draft.distanceMeters!,
        // Provenance, fixed at creation and never edited afterwards.
        source: kSourceManual,
        type: draft.type,
        endedAt: Value(draft.startedAt!.add(draft.duration!)),
        avgPaceSPerKm: Value(draft.avgPaceSecondsPerKm),
        avgHr: Value(draft.avgHr),
        rpe: Value(draft.rpe),
        notes: Value(draft.notes),
      ),
    );
    // After the local commit, never before it, and never fatal: the run is on
    // the phone whatever the network did (rule 1).
    await _push(id);
    return id;
  }

  /// Corrects an existing run, recorded or hand-entered.
  ///
  /// The trace is untouched — see [AppDatabase.updateRunDetails]. Throws
  /// [RunDraftInvalid] on a bad draft and [StateError] if there is no such run,
  /// because silently creating one would turn a typo in an id into a duplicate
  /// entry in the log.
  @override
  Future<void> edit(String runId, RunDraft draft) async {
    final issues = draft.issues(_now());
    if (issues.isNotEmpty) throw RunDraftInvalid(issues);

    final existing = await _db.runById(runId);
    if (existing == null) throw StateError('No run with id $runId');

    await _db.updateRunDetails(
      runId: runId,
      startedAt: draft.startedAt!,
      durationS: draft.duration!.inSeconds,
      distanceM: draft.distanceMeters!,
      avgPaceSPerKm: draft.avgPaceSecondsPerKm,
      type: draft.type,
      avgHr: draft.avgHr,
      rpe: draft.rpe,
      notes: draft.notes,
    );
    await _push(runId);
  }

  /// Mirrors a run, swallowing any failure. A dropped push shows up as a run
  /// that is on the phone and not yet in the backup, which the next push of
  /// that run repairs — the upsert is keyed on the run's id.
  ///
  /// Swallowed for the caller, not for everybody: the backup this is handed is
  /// wrapped in `ReportedRunBackup`, which writes the outcome down before the
  /// exception reaches here. Adding a run must not fail because a server was
  /// unreachable, and a backup that has been failing all month must not look
  /// identical to one that is working.
  Future<void> _push(String runId) async {
    final backup = _backup;
    if (backup == null) return;
    try {
      await backup.pushRun(runId);
    } catch (_) {
      // Deliberate: see the class doc.
    }
  }

  /// Sends every local run the backup does not already hold.
  ///
  /// Exposed here rather than making callers reach for the backup directly,
  /// because [RunEditor] is already the one thing that owns writing runs. A
  /// second route to the mirror is a second place to forget the consent gate.
  ///
  /// Returns 0 with no backup configured, which is the local-only build.
  ///
  /// **Never throws**, and callers may rely on that. A backfill runs at launch
  /// over a connection nobody promised, from a caller that does not wait for
  /// it, so a throw here would surface as an unhandled async error with nothing
  /// to catch it — which is precisely how a failing backfill used to go
  /// unnoticed. The failure is recorded by `ReportedRunBackup` instead, where
  /// something can be done with it.
  @override
  Future<int> backfill() async {
    final backup = _backup;
    if (backup == null) return 0;
    try {
      return await backup.backfill();
    } catch (_) {
      // Best-effort like every other push: the runs are on the phone.
      return 0;
    }
  }

  /// The stored run as a draft, for a form or a confirmation to start from.
  @override
  Future<RunDraft?> draftOf(String runId) async {
    final row = await _db.runById(runId);
    if (row == null) return null;
    return RunDraft(
      startedAt: row.startedAt,
      duration: Duration(seconds: row.durationS),
      distanceMeters: row.distanceM,
      type: row.type,
      avgHr: row.avgHr,
      rpe: row.rpe,
      notes: row.notes,
    );
  }
}
