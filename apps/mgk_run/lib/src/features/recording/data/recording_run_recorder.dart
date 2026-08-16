import 'dart:async';

import 'package:drift/drift.dart' show Value;

import '../../../core/database/app_database.dart';
import '../../history/data/run_backup.dart';
import '../domain/route_metrics.dart';
import '../domain/run_point.dart';
import '../domain/run_recorder.dart';
import 'location_source.dart';

/// The production [RunRecorder]: wires a [LocationSource] to the local database.
///
/// Contract (see docs/architecture/run-recording.md):
/// - every fix is **persisted before** it is emitted on [points], so a crash
///   mid-run never loses the run (the run row is created on [start], and
///   `endedAt` stays null until [stop] — that null is the recovery marker);
/// - fixes worse than [recordAccuracyMeters] never happened as far as the app
///   is concerned; fixes worse than [distanceAccuracyMeters] are recorded and
///   drawn but do not move the distance.
class RecordingRunRecorder implements RunRecorder {
  RecordingRunRecorder({
    required LocationSource source,
    required AppDatabase db,
    RunBackup? backup,
    String Function()? newId,
    DateTime Function()? now,
    double recordAccuracyMeters = kMaxRecordableAccuracyMeters,
    double distanceAccuracyMeters = kMaxHorizontalAccuracyMeters,
  }) : _source = source,
       _db = db,
       _runBackup = backup,
       _newId = newId ?? _defaultId,
       _now = now ?? DateTime.now,
       _recordAccuracyM = recordAccuracyMeters,
       _distanceAccuracyM = distanceAccuracyMeters;

  final LocationSource _source;
  final AppDatabase _db;

  /// Where a finished run is mirrored. Null keeps it local, which is what the
  /// preview harness and a dev persona want — invented runs must never reach
  /// the shared project.
  final RunBackup? _runBackup;
  final String Function() _newId;
  final DateTime Function() _now;

  /// Worse than this and the fix is discarded outright — see
  /// [kMaxRecordableAccuracyMeters] for why this is not the same number as
  /// [_distanceAccuracyM].
  final double _recordAccuracyM;

  /// Worse than this and the fix is kept and drawn, but does not move the
  /// distance. The number on screen stays trustworthy; the map stays alive.
  final double _distanceAccuracyM;

  /// Runs [push] only when there is a backup, and never lets it fail the
  /// caller: the run has already committed locally.
  Future<void> _backup(Future<void> Function(RunBackup) push) async {
    final backup = _runBackup;
    if (backup == null) return;
    try {
      await push(backup);
    } catch (_) {
      // Deliberate — a lost push is a run on the phone and not yet in the
      // backup, which the next push repairs.
    }
  }

  final StreamController<RunPoint> _points =
      StreamController<RunPoint>.broadcast();
  final StreamController<RecorderStatus> _statuses =
      StreamController<RecorderStatus>.broadcast();
  final StreamController<RecorderProblem?> _problems =
      StreamController<RecorderProblem?>.broadcast();

  RecorderStatus _status = RecorderStatus.idle;
  RecorderProblem? _problem;
  String? _runId;
  DateTime? _startedAt;
  int _seq = 0;

  /// The last fix that moved the distance. Cleared on pause so the first fix
  /// after resuming is an anchor rather than the far end of a long segment.
  RunPoint? _lastMeasured;
  RunPoint? _lastFix;
  double _distanceM = 0;

  /// Time not counted so far, and when the current not-counting began.
  ///
  /// One pair for both kinds of stop. Manual pause and autopause can overlap —
  /// a runner stops at a light, autopause fires, then they hit Pause — and two
  /// independent accumulators would charge that overlap twice.
  Duration _pausedTotal = Duration.zero;
  DateTime? _notCountingSince;

  /// Set once the run is finished, so both clocks stop at the line rather than
  /// running on while the summary is open.
  DateTime? _endedAt;

  StreamSubscription<RunPoint>? _sub;

  @override
  Stream<RunPoint> get points => _points.stream;

  @override
  Stream<RecorderStatus> get statusChanges => _statuses.stream;

  @override
  RecorderStatus get status => _status;

  @override
  RecorderProblem? get problem => _problem;

  @override
  Stream<RecorderProblem?> get problems => _problems.stream;

  @override
  RunPoint? get lastFix => _lastFix;

  /// **Always false: autopause is switched off at the recording layer.**
  ///
  /// It was wired in and it reproduced, by a different route, the exact bug
  /// this class was rewritten to fix. On the first device run it latched on
  /// within seconds and never let go: the clock froze, nothing was persisted,
  /// and the screen said "Auto-paused" — which is worse than the silent 0.00 km
  /// it replaced, because it looks deliberate.
  ///
  /// Four faults compounded, and the constants were the least of them:
  ///
  ///  * [displacementOver] filters at [kMaxHorizontalAccuracyMeters] (20 m)
  ///    while this recorder accepts fixes to [kMaxRecordableAccuracyMeters]
  ///    (50 m) — so the detector went blind in exactly the conditions the wider
  ///    gate exists to serve, and returned null.
  ///  * A null reading while already paused was treated as "still stopped",
  ///    which turns a gap in the data into a latch that cannot release.
  ///  * Resuming demanded 15 m in 5 s (3.0 m/s, about 5:33/km) while pausing
  ///    triggered below 0.67 m/s — you had to run hard to undo something a
  ///    slow walk could cause.
  ///  * Nothing waited for the run to actually start, so standing still after
  ///    tapping Start was enough.
  ///
  /// **The rule that was broken is bigger than the tuning: a heuristic may not
  /// stop the clock, and may not decide against persisting a fix.** Only the
  /// runner stops the clock, by pressing Pause. Guessing wrong about a stop
  /// costs a little inflated distance; guessing wrong about a start costs the
  /// entire run, and one of those is recoverable.
  ///
  /// **The problem it was reaching for is real and is still open.** Standing
  /// still DOES inflate distance: `processedDistanceMeters` only discards
  /// sub-metre hops, and real GPS drift is metres, so forty seconds at a
  /// crossing banks a few hundred of them (measured, see the recorder tests).
  /// An earlier version of this comment claimed the jitter rule already
  /// handled it. It does not.
  ///
  /// The fix belongs in the smoother, rejecting a hop by the speed it implies
  /// over the interval it spans — the "speed-windowed" pass
  /// docs/architecture/run-recording.md has always asked for — and not in a
  /// gate in front of the write. An inflated distance is a wrong number on a
  /// saved run. A gate that guesses wrong is no run at all.
  ///
  /// The detector itself is kept, tested, in `live_metrics.dart`. Re-enabling
  /// it needs: its own accuracy gate matched to the record gate, a null reading
  /// that fails *running* rather than stopped, thresholds tuned against a real
  /// recorded trace rather than reasoned about, and a first-movement guard. It
  /// should also become a display label over persisted data rather than a gate
  /// in front of the write.
  @override
  bool get autoPaused => false;

  /// Wall-clock time since the run began. **It does not stop.**
  ///
  /// A race clock runs from gun to line. Standing at a crossing is part of your
  /// 10k whether you like it or not, and a runner training against a race time
  /// needs the number that is comparable to one. So this counts everything,
  /// including a manual pause.
  ///
  /// It briefly did not: the pause fix made this moving time, which also became
  /// the stored `durationS` and therefore the divisor for average pace — so
  /// every paced run recorded as faster than it was run. See [movingTime] for
  /// the figure that legitimately excludes stops.
  @override
  Duration get elapsed {
    final started = _startedAt;
    if (started == null) return Duration.zero;
    final total = (_endedAt ?? _now()).difference(started);
    return total.isNegative ? Duration.zero : total;
  }

  /// [elapsed] minus everything spent paused — the secondary figure, kept
  /// because it is genuinely useful and not because it is the run's time.
  ///
  /// Not persisted: `run.runs` has one duration column and it holds the wall
  /// clock. Adding a column for this is a schema change, and worth making only
  /// once a surface actually shows it.
  Duration get movingTime {
    final started = _startedAt;
    if (started == null) return Duration.zero;
    final until = _notCountingSince ?? _endedAt ?? _now();
    final total = until.difference(started) - _pausedTotal;
    return total.isNegative ? Duration.zero : total;
  }

  /// Whether time and distance should currently be accruing.
  ///
  /// Deliberately reads nothing but lifecycle state. It used to consult the
  /// autopause heuristic, which is how a wrong guess froze the clock — see
  /// [autoPaused] for why that authority has been taken away.
  bool get _counting => _status == RecorderStatus.recording && _runId != null;

  /// Folds every reason the run might not be counting into one clock.
  ///
  /// Called after anything that could change [_counting]. Idempotent, so it is
  /// safe to call on a transition that turns out not to be one — which matters,
  /// because autopause evaluates on every fix.
  void _syncCounting() {
    if (_counting) {
      final since = _notCountingSince;
      if (since != null) {
        _pausedTotal += _now().difference(since);
        _notCountingSince = null;
      }
    } else {
      _notCountingSince ??= _now();
      // Drop the anchor, so whatever happens next starts a fresh segment
      // instead of measuring back to wherever the runner stopped.
      _lastMeasured = null;
    }
  }

  /// The id of the run currently being recorded, or null.
  String? get currentRunId => _runId;

  /// Distance in meters accumulated so far this run.
  double get distanceMeters => _distanceM;

  void _setStatus(RecorderStatus next) {
    _status = next;
    _statuses.add(next);
  }

  void _setProblem(RecorderProblem? next) {
    if (_problem == next) return;
    _problem = next;
    _problems.add(next);
  }

  RecorderProblem _problemFor(LocationUnavailable e) => switch (e.reason) {
    LocationUnavailableReason.servicesDisabled =>
      RecorderProblem.locationServicesOff,
    LocationUnavailableReason.permissionDenied =>
      RecorderProblem.permissionDenied,
    LocationUnavailableReason.permissionDeniedForever =>
      RecorderProblem.permissionDeniedForever,
    LocationUnavailableReason.failed => RecorderProblem.locationFailed,
  };

  @override
  Future<void> start() async {
    if (_status == RecorderStatus.recording) return;
    final id = _newId();
    final started = _now();
    _runId = id;
    _startedAt = started;
    _seq = 0;
    _lastMeasured = null;
    _lastFix = null;
    _distanceM = 0;
    _pausedTotal = Duration.zero;
    _notCountingSince = null;
    _endedAt = null;
    _setProblem(null);

    await _db.upsertRun(
      RunsCompanion.insert(
        id: id,
        startedAt: started,
        durationS: 0,
        distanceM: 0,
        source: 'gps',
        type: 'outdoor',
      ),
    );

    // Subscribe BEFORE starting the source. `fixes` is a broadcast stream, and
    // a broadcast stream drops whatever it emits with nobody listening — so
    // subscribing afterwards threw away every fix that arrived in the gap.
    // On a warm GPS that is the first second or two of the run.
    _sub = _source.fixes.listen(_onFix, onError: _onSourceError);
    _setStatus(RecorderStatus.recording);

    try {
      await _source.start();
    } on LocationUnavailable catch (e) {
      // Deliberately not rethrown: `start` is called from `initState`, so a
      // throw here has nobody to catch it and becomes an unhandled async error
      // — which is exactly how a refused permission used to turn into a screen
      // that pulsed "Recording" over zeroes forever. The problem is a value the
      // screen can render instead.
      await _abandonUnstartedRun();
      _setProblem(_problemFor(e));
      _setStatus(RecorderStatus.idle);
    }
  }

  /// Removes the run row created for a run that never began.
  ///
  /// Without this a refused permission leaves a row with a null `endedAt`,
  /// which is the recovery marker — so the next launch would offer to resume a
  /// run that has no points and never happened.
  Future<void> _abandonUnstartedRun() async {
    final runId = _runId;
    await _sub?.cancel();
    _sub = null;
    if (runId != null) await _db.deleteRun(runId);
    _runId = null;
    _startedAt = null;
  }

  void _onSourceError(Object error, StackTrace stack) {
    if (error is LocationUnavailable) {
      _setProblem(_problemFor(error));
    } else {
      _setProblem(RecorderProblem.locationFailed);
    }
  }

  Future<void> _onFix(RunPoint fix) async {
    if (_status != RecorderStatus.recording) return; // ignore while paused
    if (fix.accuracyMeters > _recordAccuracyM) return; // unusable at any price
    final runId = _runId;
    if (runId == null) return;

    // A fix arriving is proof location is working, whatever went wrong before.
    _setProblem(null);
    _lastFix = fix;

    // **Autopause is deliberately not wired in.** See [autoPaused].
    //
    // Nothing between here and the write below may decide not to persist. A
    // fix that reached this point is going on disk: that is rule 1, and the
    // whole of this class's reason to exist.

    final seq = _seq++;
    // Persist FIRST — an emitted point must already be on disk.
    await _db.addRunPoint(
      RunPointsCompanion.insert(
        runId: runId,
        seq: seq,
        lat: fix.latitude,
        lng: fix.longitude,
        accuracyM: fix.accuracyMeters,
        timestamp: fix.timestamp,
        altitudeM: Value(fix.altitudeMeters),
      ),
    );

    // Recorded and drawn either way; only good fixes move the number. This is
    // the whole point of the two gates — a 35 m fix still says where you are,
    // it just isn't precise enough to measure with.
    if (fix.accuracyMeters <= _distanceAccuracyM) {
      final prev = _lastMeasured;
      if (prev != null) {
        _distanceM += haversineMeters(
          prev.latitude,
          prev.longitude,
          fix.latitude,
          fix.longitude,
        );
      }
      _lastMeasured = fix;
    }

    _points.add(fix);
  }

  @override
  Future<void> pause() async {
    if (_status != RecorderStatus.recording) return;
    _setStatus(RecorderStatus.paused);
    // Drop the anchor. Without this the first fix after resuming measured all
    // the way back to wherever the runner stood when they paused, so a coffee
    // stop two streets away was silently added to the run.
    _syncCounting();
  }

  @override
  Future<void> resume() async {
    if (_status != RecorderStatus.paused) return;
    _setStatus(RecorderStatus.recording);
    _syncCounting();
  }

  @override
  Future<void> stop() async {
    final runId = _runId;
    if (runId == null) return;
    await _sub?.cancel();
    _sub = null;
    await _source.stop();
    // Recompute the authoritative distance from the persisted trace with the
    // smoother, so the stored total matches what the screen displayed and isn't
    // inflated by jitter (the live [_distanceM] is a raw running estimate).
    final rows = await _db.pointsForRun(runId);
    final distanceM = processedDistanceMeters(
      rows.map(_rowToPoint),
      maxAccuracyM: _distanceAccuracyM,
    );
    final ended = _now();
    _endedAt = ended;
    // Wall clock, gun to line — the same number the screen showed, and the
    // only one comparable to a race result. Average pace divides by it.
    final durationS = ended.difference(_startedAt!).inSeconds;
    final avgPace = distanceM > 0 ? durationS / (distanceM / 1000) : null;
    await _db.finalizeRun(
      runId: runId,
      endedAt: ended,
      durationS: durationS,
      distanceM: distanceM,
      avgPaceSPerKm: avgPace,
    );
    // The run is safe on the phone at this point (rule 1). Mirroring it is
    // what makes it appear in the log at all, because History reads Supabase —
    // before this existed, a recorded run was written here and seen nowhere.
    await _backup((backup) async {
      await backup.pushRun(runId);
      await backup.pushTrace(runId);
    });
    _setStatus(RecorderStatus.stopped);
  }

  @override
  Future<void> discard() async {
    final runId = _runId;
    await _sub?.cancel();
    _sub = null;
    await _source.stop();
    if (runId != null) {
      await _db.deleteRun(runId);
      // A discarded run must not survive in the backup, or the next read of
      // the log would bring it back.
      await _backup((backup) => backup.deleteRun(runId));
    }
    _runId = null;
    _setStatus(RecorderStatus.stopped);
  }

  RunPoint _rowToPoint(RunPointRow row) => RunPoint(
    latitude: row.lat,
    longitude: row.lng,
    accuracyMeters: row.accuracyM,
    altitudeMeters: row.altitudeM,
    timestamp: row.timestamp,
  );
}

String _defaultId() => DateTime.now().microsecondsSinceEpoch.toString();
