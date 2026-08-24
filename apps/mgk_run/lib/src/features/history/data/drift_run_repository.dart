import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../recording/domain/run_summary.dart';

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
class DriftRunRepository {
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
}

/// A stored run as the screens see it.
///
/// Split out and public so it can be tested on its own: the query cannot run
/// off-device but the mapping is where a wrong column would hide.
RunSummary runSummaryFromLocal(RunRow row) => RunSummary(
  id: row.id,
  startedAt: row.startedAt,
  duration: Duration(seconds: row.durationS),
  distanceMeters: row.distanceM,
  avgPaceSecondsPerKm: row.avgPaceSPerKm,
  elevationGainMeters: row.elevationGainM,
  avgHr: row.avgHr,
  maxHr: row.maxHr,
  caloriesEst: row.caloriesEst,
  type: row.type,
);
