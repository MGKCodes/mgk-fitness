import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../recording/domain/run_point.dart';
import '../../recording/domain/run_split.dart';
import '../../recording/domain/run_summary.dart';
import '../domain/run_writer.dart';

/// Reads the training log from the on-device database.
///
/// **This is the log's only read path, and it was not always.** History used to
/// be read from Supabase, which made a run visible only if it had been
/// successfully mirrored — so a run that was complete and correct on the phone
/// was shown nowhere if the runner had declined backup, if the push failed, or
/// if the read itself failed (ADR-0023, docs/decisions). The short version is
/// that a device which owns the truth about a run (CLAUDE.md rule 1) has no
/// business asking a server what its runs were.
///
/// Reading locally also means the log is one of the surfaces that works with no
/// signal at all, which is where runs are finished.
///
/// Queries live here rather than on [AppDatabase] for the same reason
/// `DriftCoachMemoryStore`'s do: the shared database class registers the tables
/// and this feature keeps its own storage.
class DriftRunRepository implements RunDetailSource {
  DriftRunRepository(this._db);

  final AppDatabase _db;

  /// Every finished run, newest first.
  ///
  /// **Finished** is the whole of the filter, and it is load-bearing. A null
  /// `endedAt` is the recorder's marker for a run that is still going or was
  /// interrupted mid-way (see `RecordingRunRecorder`), and such a row carries a
  /// zero distance and a zero duration until [AppDatabase.finalizeRun] writes
  /// the real numbers. Including it would put a 0.00 km run at the top of the
  /// log while the runner was still out on it, and leave one there for good
  /// after a crash. Supabase never showed those because nothing pushed a run
  /// until it stopped; reading locally, the filter has to be explicit.
  ///
  /// Summary fields only. The trace is thousands of rows per run and the log
  /// draws none of it, so it is left for whatever opens a single run.
  Future<List<RunSummary>> fetchRuns() async {
    final rows =
        await (_db.select(_db.runs)
              ..where((r) => r.endedAt.isNotNull())
              ..orderBy([(r) => OrderingTerm.desc(r.startedAt)]))
            .get();
    return <RunSummary>[for (final row in rows) runSummaryFromLocal(row)];
  }

  /// One run in full — its summary, its trace and its splits.
  ///
  /// **A run opened from the log has never drawn a route.** The old Supabase
  /// read returned summaries, and the `fetchRunDetail` beside it was called by
  /// nothing at all — so `RunSummaryScreen` had a map it only ever showed for a
  /// run it was handed in memory, which was no run at all until Phase 1 wired
  /// finishing to it. ADR-0023 left this as the one consequence still open;
  /// reading locally it is two selects rather than a network round trip.
  ///
  /// Null when there is no such run. Deliberately not filtered on `endedAt`:
  /// the caller asked for a specific run by id, and answering "not found" for a
  /// run that is on the phone would be the log's filter leaking into a lookup.
  @override
  Future<RunSummary?> runDetail(String runId) async {
    final row = await _db.runById(runId);
    return row == null ? null : _withTrace(row);
  }

  /// The run that finished after [since], or null if none did.
  ///
  /// This is how the shell finds the run a runner just completed, and it is
  /// asked by `endedAt` rather than by "the newest row" for a reason worth
  /// keeping: `startedAt` orders the log, and a hand-entered run typed this
  /// morning about yesterday evening sits above a run finished ten seconds ago.
  /// `endedAt` is written by [AppDatabase.finalizeRun] at the moment the runner
  /// pressed the button, so "ended after I opened the recorder" is exactly one
  /// run — and is *no* run when they backed out without recording, which is
  /// the case that must not show them somebody else's summary.
  ///
  /// At or after, not strictly after, because Drift stores a `DateTime` as
  /// whole unix seconds: a strict comparison silently means "ended in a later
  /// second than the one I opened in", which is false for anything that opens
  /// and finishes inside the same second. That never happens to a runner and
  /// happens constantly to a test, which is a bad reason to have a query that
  /// only works when it is slow. The inclusive form can only be wrong if a
  /// *previous* run ended in the same second the recorder was opened, which
  /// would mean finishing one run and starting another inside one second.
  @override
  Future<RunSummary?> runFinishedSince(DateTime since) async {
    final row =
        await (_db.select(_db.runs)
              ..where((r) => r.endedAt.isBiggerOrEqualValue(since))
              ..orderBy([(r) => OrderingTerm.desc(r.endedAt)])
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _withTrace(row);
  }

  Future<RunSummary> _withTrace(RunRow row) async {
    final points = await _db.pointsForRun(row.id);
    final splits = await _db.splitsForRun(row.id);
    return runSummaryFromLocal(
      row,
      points: <RunPoint>[for (final p in points) runPointFromLocal(p)],
      splits: <RunSplit>[for (final s in splits) runSplitFromLocal(s)],
    );
  }
}

/// A stored run as the screens see it.
///
/// Split out and public so it can be tested on its own: the query cannot run
/// off-device but the mapping is where a wrong column would hide.
RunSummary runSummaryFromLocal(
  RunRow row, {
  List<RunPoint> points = const <RunPoint>[],
  List<RunSplit> splits = const <RunSplit>[],
}) => RunSummary(
  id: row.id,
  startedAt: row.startedAt,
  duration: Duration(seconds: row.durationS),
  distanceMeters: row.distanceM,
  avgPaceSecondsPerKm: row.avgPaceSPerKm,
  elevationGainMeters: row.elevationGainM,
  elevationMaxMeters: row.elevationMaxM,
  avgHr: row.avgHr,
  maxHr: row.maxHr,
  caloriesEst: row.caloriesEst,
  // Null for every run recorded before the Health read existed, and for every
  // runner who declined it. The screen draws no tile rather than a zero, so a
  // column that is mostly empty is the designed state and not a gap.
  steps: row.steps,
  type: row.type,
  points: points,
  splits: splits,
);

/// A stored fix as the map sees it. Public for the same reason as
/// [runSummaryFromLocal] — a swapped latitude and longitude is a mapping bug
/// that draws a plausible route in the sea.
RunPoint runPointFromLocal(RunPointRow row) => RunPoint(
  latitude: row.lat,
  longitude: row.lng,
  accuracyMeters: row.accuracyM,
  altitudeMeters: row.altitudeM,
  timestamp: row.timestamp,
);

/// A stored split as the splits list sees it.
RunSplit runSplitFromLocal(RunSplitRow row) => RunSplit(
  index: row.seq,
  distanceMeters: row.distanceM,
  duration: Duration(seconds: row.durationS),
  avgHr: row.avgHr,
);
