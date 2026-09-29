import '../../../core/database/app_database.dart';
import '../domain/best_effort.dart';
import '../domain/live_metrics.dart';
import '../domain/route_metrics.dart';
import '../domain/run_point.dart';

/// The honest marker recovery leaves on a run's notes.
///
/// A run reaching [recoverInterruptedRun] has never been finished before —
/// `endedAt` was null, which is exactly what made it findable — so there is
/// never anything already in `notes` for this to overwrite.
const String kRecoveredRunNote =
    'Recovered automatically — recording stopped when the app closed, '
    'before you pressed Finish.';

/// Finds a run `start()` began that no `stop()` or `discard()` ever finished,
/// and settles it one way or the other.
///
/// **The gap this closes.** A null `endedAt` is `RecordingRunRecorder`'s own
/// recovery marker (see its class doc), and [AppDatabase.activeRun] has read
/// it since the column existed — but nothing in `lib/` ever called
/// [AppDatabase.activeRun] before this file. So a run survived an iOS memory
/// kill, an Android task swipe, a reboot or a crash exactly as rule 1
/// promises — every fix up to the last one is on disk — and then sat there
/// forever: not in the log (`DriftRunRepository.fetchRuns` filters on
/// `endedAt` for precisely the reason a live 0.00 km row must not sit at the
/// top of it), not in a backup, not on the next launch either, because
/// nothing asked.
///
/// **Call this once, at launch, before anything reads the log.** That is the
/// contract a caller has to keep: a runner who opens Run after a kill should
/// see the run they were on folded into their history, not an empty screen
/// that quietly grows one entry after the fact.
///
/// Two outcomes, both terminal — settling the row clears the marker either
/// way, so a second launch finds nothing left to do:
///
///  - **No points at all.** `start()` wrote the row and the process died
///    before a single fix arrived — a permission prompt still on screen, a
///    kill in the first second. There is nothing to show for this run, so
///    the row is deleted rather than finalised: a 0.00 km entry would be a
///    lie about a run that never happened, and `SupabaseRunBackup.backfill`
///    would be the next thing to find it and mirror that lie onward.
///  - **Some points.** Finalised exactly the way `stop()` would: distance
///    recomputed from the persisted trace with the same smoother, splits and
///    best efforts cut from the same walk over it, `endedAt` set to the
///    **last recorded fix** — the last moment this run is evidence for
///    anything, since a recovered run does not get to claim it kept tracking
///    after the phone died. Duration excludes whatever `pausedTotalS` the row
///    already carried: written by `pause()`/`resume()` as the run went, not
///    computed here from a clock that no longer exists.
///
/// **Never pushes to a backup.** The run is safe on the phone the moment this
/// returns, which is the whole of what rule 1 asks for. Finalising it here
/// gives it a real `endedAt`, so the ordinary backfill path picks it up the
/// next time it runs; recovery does not need a network seam of its own to do
/// that again.
Future<void> recoverInterruptedRun(AppDatabase db) async {
  final active = await db.activeRun();
  if (active == null) return;

  final rows = await db.pointsForRun(active.id);
  if (rows.isEmpty) {
    await db.deleteRun(active.id);
    return;
  }

  final trace = <RunPoint>[
    for (final row in rows)
      RunPoint(
        latitude: row.lat,
        longitude: row.lng,
        accuracyMeters: row.accuracyM,
        altitudeMeters: row.altitudeM,
        timestamp: row.timestamp,
      ),
  ];

  final distanceM = processedDistanceMeters(trace);
  // The last fix is the last moment this run is evidence for anything.
  final endedAt = trace.last.timestamp;

  // A pause still open when the process died (`notCountingSince` non-null)
  // needs nothing added for the time since: `_onFix` refuses fixes while
  // paused, so the last fix can only be at or before that pause began, and
  // `pausedTotalS` already excludes every pause that closed before this one.
  final pausedTotal = Duration(seconds: active.pausedTotalS);
  final wallTime = endedAt.difference(active.startedAt) - pausedTotal;
  final durationS = wallTime.isNegative ? 0 : wallTime.inSeconds;

  final avgPace = distanceM > 0 ? durationS / (distanceM / 1000) : null;

  await db.finalizeRun(
    runId: active.id,
    endedAt: endedAt,
    durationS: durationS,
    distanceM: distanceM,
    avgPaceSPerKm: avgPace,
    elevationGainM: climbMeters(trace),
    elevationMaxM: maxElevationMeters(trace),
    notes: kRecoveredRunNote,
  );
  await db.replaceRunSplits(active.id, <RunSplitsCompanion>[
    for (final split in splitsFor(trace))
      RunSplitsCompanion.insert(
        runId: active.id,
        seq: split.index,
        distanceM: split.distanceMeters,
        durationS: split.duration.inSeconds,
      ),
  ]);
  await db.replaceRunBestEfforts(active.id, <RunBestEffortsCompanion>[
    for (final effort in bestEffortsFor(trace))
      RunBestEffortsCompanion.insert(
        runId: active.id,
        distanceM: effort.distanceMeters,
        durationS: effort.duration.inSeconds,
      ),
  ]);
}
