import 'dart:async';

import 'package:drift/drift.dart' show Value;

import '../../../core/database/app_database.dart';
import '../../history/data/run_backup.dart';
import '../domain/live_metrics.dart';
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

  /// Recent fixes, in memory only, kept so autopause has something to measure
  /// movement over. This is fed by **every** accepted fix including the ones
  /// that are not persisted while auto-paused — otherwise the detector would
  /// go blind the moment it fired and could never decide to start again.
  final List<RunPoint> _recent = <RunPoint>[];

  bool _autoPaused = false;

  /// Time not counted so far, and when the current not-counting began.
  ///
  /// One pair for both kinds of stop. Manual pause and autopause can overlap —
  /// a runner stops at a light, autopause fires, then they hit Pause — and two
  /// independent accumulators would charge that overlap twice.
  Duration _pausedTotal = Duration.zero;
  DateTime? _notCountingSince;

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

  @override
  bool get autoPaused => _autoPaused;

  @override
  Duration get elapsed {
    final started = _startedAt;
    if (started == null) return Duration.zero;
    // While stopped the clock is frozen at the moment it stopped; otherwise it
    // runs to now. Either way the total of past stops comes off, so this is
    // moving time and never counts a stop twice.
    final until = _notCountingSince ?? _now();
    final total = until.difference(started) - _pausedTotal;
    return total.isNegative ? Duration.zero : total;
  }

  /// Whether time and distance should currently be accruing.
  bool get _counting =>
      _status == RecorderStatus.recording && !_autoPaused && _runId != null;

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
    _autoPaused = false;
    _recent.clear();
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

    // The autopause window is fed before the decision to persist, not after:
    // once auto-paused, nothing is written, so a detector reading the stored
    // trace would never see the movement that should start the run again.
    _recent.add(fix);
    _trimRecent();

    final wasAutoPaused = _autoPaused;
    _autoPaused = detectAutoPause(_recent, wasPaused: wasAutoPaused);
    if (_autoPaused != wasAutoPaused) _syncCounting();

    // A standing runner still produces metres of drift per fix — more than the
    // sub-metre rule discards — so persisting through a stop would quietly add
    // a few hundred metres to a long wait. Not writing them leaves a gap in
    // the trace instead, which is exactly what the gap rule already handles:
    // no distance across it, and no line drawn through it.
    if (_autoPaused) return;

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

  /// Keeps only what the detector can still use — the longest window it asks
  /// about, plus a little slack. An unbounded list would grow for the length of
  /// the run to answer a question about the last twelve seconds.
  void _trimRecent() {
    final cutoff = _recent.last.timestamp.subtract(
      kAutoPauseWindow + const Duration(seconds: 5),
    );
    _recent.removeWhere((point) => point.timestamp.isBefore(cutoff));
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
    // A manual resume overrides autopause: the runner has said they are going,
    // and leaving the auto flag set would keep the clock stopped until the
    // detector caught up several fixes later.
    _autoPaused = false;
    _recent.clear();
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
    // Moving time, not wall time: [elapsed] already subtracts every pause, and
    // the stored duration has to agree with the number the screen showed.
    final durationS = elapsed.inSeconds;
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
