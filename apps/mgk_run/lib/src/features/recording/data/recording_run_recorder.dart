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
/// - fixes worse than [maxAccuracyMeters] are dropped before reaching [points].
class RecordingRunRecorder implements RunRecorder {
  RecordingRunRecorder({
    required LocationSource source,
    required AppDatabase db,
    RunBackup? backup,
    String Function()? newId,
    DateTime Function()? now,
    double maxAccuracyMeters = kMaxHorizontalAccuracyMeters,
  }) : _source = source,
       _db = db,
       _runBackup = backup,
       _newId = newId ?? _defaultId,
       _now = now ?? DateTime.now,
       _maxAccuracyM = maxAccuracyMeters;

  final LocationSource _source;
  final AppDatabase _db;

  /// Where a finished run is mirrored. Null keeps it local, which is what the
  /// preview harness and a dev persona want — invented runs must never reach
  /// the shared project.
  final RunBackup? _runBackup;
  final String Function() _newId;
  final DateTime Function() _now;
  final double _maxAccuracyM;

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

  RecorderStatus _status = RecorderStatus.idle;
  String? _runId;
  DateTime? _startedAt;
  int _seq = 0;
  RunPoint? _lastKept;
  double _distanceM = 0;
  StreamSubscription<RunPoint>? _sub;

  @override
  Stream<RunPoint> get points => _points.stream;

  @override
  Stream<RecorderStatus> get statusChanges => _statuses.stream;

  @override
  RecorderStatus get status => _status;

  /// The id of the run currently being recorded, or null.
  String? get currentRunId => _runId;

  /// Distance in meters accumulated so far this run.
  double get distanceMeters => _distanceM;

  void _setStatus(RecorderStatus next) {
    _status = next;
    _statuses.add(next);
  }

  @override
  Future<void> start() async {
    if (_status == RecorderStatus.recording) return;
    final id = _newId();
    final started = _now();
    _runId = id;
    _startedAt = started;
    _seq = 0;
    _lastKept = null;
    _distanceM = 0;
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
    await _source.start();
    _sub = _source.fixes.listen(_onFix);
    _setStatus(RecorderStatus.recording);
  }

  Future<void> _onFix(RunPoint fix) async {
    if (_status != RecorderStatus.recording) return; // ignore while paused
    if (fix.accuracyMeters > _maxAccuracyM) return; // accuracy filter
    final runId = _runId;
    if (runId == null) return;
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
    final prev = _lastKept;
    if (prev != null) {
      _distanceM += haversineMeters(
        prev.latitude,
        prev.longitude,
        fix.latitude,
        fix.longitude,
      );
    }
    _lastKept = fix;
    _points.add(fix);
  }

  @override
  Future<void> pause() async {
    if (_status == RecorderStatus.recording) {
      _setStatus(RecorderStatus.paused);
    }
  }

  @override
  Future<void> resume() async {
    if (_status == RecorderStatus.paused) {
      _setStatus(RecorderStatus.recording);
    }
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
    final distanceM = processedDistanceMeters(rows.map(_rowToPoint));
    final ended = _now();
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
