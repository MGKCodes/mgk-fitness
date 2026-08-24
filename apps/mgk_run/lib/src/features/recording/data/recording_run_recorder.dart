import 'dart:async';

import 'package:drift/drift.dart' show Value;

import '../../../core/database/app_database.dart';
import '../../../core/ids.dart';
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
  ///
  /// The catch is deliberate and always was, but for a while it was the *only*
  /// thing that happened to a failed push, which is how a backup that had been
  /// broken for weeks could look exactly like one that was working. Finishing a
  /// run must not fail because a server was unreachable; it must also not be
  /// the last anybody hears of it. The reporting is done by the wrapper the
  /// backup is built with (`ReportedRunBackup` in `main.dart`) rather than
  /// here, so the recorder keeps knowing nothing about backups beyond this
  /// seam — and so the editor and the backfill get it too.
  Future<void> _backup(Future<void> Function(RunBackup) push) async {
    final backup = _runBackup;
    if (backup == null) return;
    try {
      await push(backup);
    } catch (_) {
      // Deliberate — a lost push is a run on the phone and not yet in the
      // backup, which the next push repairs. Recorded on the way past; see
      // above.
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

  /// When the newest fix arrived — see [RunRecorder.sinceLastFix].
  DateTime? _lastFixAt;
  double _distanceM = 0;

  /// Time not counted so far, and when the current not-counting began.
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

  @override
  Duration? get sinceLastFix {
    final at = _lastFixAt;
    if (at == null) return null;
    final age = _now().difference(at);
    // A fix timestamped fractionally ahead of the clock is a rounding artefact,
    // not time travel; report it as fresh rather than negative.
    return age.isNegative ? Duration.zero : age;
  }

  /// Time on the run's clock: wall time since the start, minus anything the
  /// runner explicitly paused.
  ///
  /// **Only the runner stops this clock, and only by pressing Pause.** That is
  /// the whole rule, and both halves matter:
  ///
  ///  * A pause is a deliberate act. Someone who presses it means "this next
  ///    bit is not my run", and the clock owes them that.
  ///  * Merely stopping running is not a pause. Waiting at a crossing is part
  ///    of your 10k the way it is part of a race — the gun clock does not care
  ///    that you stopped. An autopause heuristic was built and removed for
  ///    exactly this: a guess that stops the clock is a guess quietly editing
  ///    somebody's time, and when it latched it also stopped the writing.
  ///
  /// Derived from the wall clock rather than accumulated from a ticker: iOS
  /// throttles and then suspends timers behind a locked screen, so a run with
  /// the screen locked came back having lost the minutes it was away.
  ///
  /// This is also exactly what [stop] stores, so the summary can never
  /// contradict the number the runner watched.
  @override
  Duration get elapsed {
    final started = _startedAt;
    if (started == null) return Duration.zero;
    // Frozen at the moment the clock stopped — a pause now, or the finish —
    // and otherwise running to now. Past pauses come off either way, so a
    // pause is never charged twice.
    final until = _notCountingSince ?? _endedAt ?? _now();
    final total = until.difference(started) - _pausedTotal;
    return total.isNegative ? Duration.zero : total;
  }

  /// Whether time and distance should currently be accruing.
  ///
  /// Deliberately reads nothing but lifecycle state. It briefly consulted an
  /// autopause heuristic, which is how a wrong guess froze the clock and
  /// stopped the run recording. Nothing but Pause gets that authority.
  bool get _counting => _status == RecorderStatus.recording && _runId != null;

  /// Folds every reason the run might not be counting into one clock.
  ///
  /// Called after anything that could change [_counting]. Idempotent, so it is
  /// safe to call on a transition that turns out not to be one.
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
    _lastFixAt = null;
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
    _lastFixAt = _now();

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
    // The same number the screen showed. Storing anything else means the
    // summary disagrees with the run — which it did, in both directions,
    // within a day: first wall time against a moving-time display, then
    // moving time against a wall-clock one.
    final durationS = elapsed.inSeconds;
    final avgPace = distanceM > 0 ? durationS / (distanceM / 1000) : null;
    await _db.finalizeRun(
      runId: runId,
      endedAt: ended,
      durationS: durationS,
      distanceM: distanceM,
      avgPaceSPerKm: avgPace,
    );
    // The run is safe on the phone at this point, and that is now the whole of
    // what "safe" requires (rule 1): the log is read from Drift, so the run is
    // in it the moment the line above returns. Mirroring is a mirror.
    //
    // It used to be more than that — the log was read from Supabase, so this
    // push was what made a run appear at all, and a runner who had declined
    // backup finished a 10 km run and was shown "No runs yet". ADR-0023 has
    // the argument; the code that changed is one line in `main.dart`.
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

/// A recorded run's identity. Not the clock — see [newLocalId].
///
/// Starting two runs inside one microsecond is not a thing a person does, so
/// this generator was the safer of the two that shared the bug. It is fixed
/// anyway: "the caller happens not to race" is a property of today's callers,
/// and the recorder already writes from a stream.
String _defaultId() => newLocalId();
