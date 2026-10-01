import 'dart:async';

import 'package:mgk_units/mgk_units.dart';

import '../domain/live_metrics.dart';
import '../domain/live_readout.dart';
import '../domain/route_metrics.dart';
import '../domain/run_point.dart';
import '../domain/run_recorder.dart';

/// How often the lock screen's distance and pace are refreshed.
///
/// The clock on it counts by itself, so this is only for the two figures
/// that need the app. Often enough to trust at a glance; not every fix, which
/// is once a second for an hour.
const Duration kLiveReadoutEvery = Duration(seconds: 4);

/// Below this the average pace is noise, and the readout shows dashes. The
/// in-run screen's own floor.
const double _paceFloorMeters = 100;

/// A [RunRecorder] that also keeps a [LiveRunReadout] up to date.
///
/// **Around the recorder, not inside the screen.** The in-run screen works out
/// the same figures, and it is the wrong place to send them from: the screen
/// is exactly what is not there when the phone is locked. A locked iPhone
/// stops an app's timers and keeps delivering location to one recording a
/// run, so the readout is refreshed when a fix arrives, which is the one
/// thing that still happens.
///
/// Everything else is passed straight through. The recorder underneath does
/// not know this exists, and a readout that fails changes nothing about the
/// run (see [LiveRunReadout]).
class LiveReadoutRecorder implements RunRecorder {
  LiveReadoutRecorder(
    this._inner,
    this._readout, {
    required UnitSystem unit,
    Duration every = kLiveReadoutEvery,
    DateTime Function() now = DateTime.now,
  }) : _unit = unit,
       _every = every,
       _now = now;

  final RunRecorder _inner;
  final LiveRunReadout _readout;
  final UnitSystem _unit;
  final Duration _every;
  final DateTime Function() _now;

  final List<RunPoint> _points = <RunPoint>[];
  StreamSubscription<RunPoint>? _onPoint;
  StreamSubscription<RecorderStatus>? _onStatus;
  DateTime? _shownAt;
  bool _ended = false;

  /// The figures as the in-run screen would give them.
  LiveRunStatus get _current {
    final double meters = processedDistanceMeters(_points);
    final Duration elapsed = _inner.elapsed;
    final Duration? since = _inner.sinceLastFix;
    final bool lost = since != null && since >= kStaleFixAfter;
    // The pace now, when there is one; the run's average when there is not;
    // dashes before there is enough of a run to have either.
    final Pace? pace =
        (lost ? null : rollingPace(_points)) ??
        (meters >= _paceFloorMeters && elapsed > Duration.zero
            ? Pace.from(Distance.meters(meters), elapsed)
            : null);
    return LiveRunStatus(
      distance: Distance.meters(meters).format(_unit),
      pace: pace?.format(_unit) ?? '--:-- ${_unit.paceSuffix}',
      elapsed: elapsed,
      paused: _inner.status == RecorderStatus.paused,
    );
  }

  void _show({bool force = false}) {
    if (_ended) return;
    final DateTime at = _now();
    final DateTime? last = _shownAt;
    if (!force && last != null && at.difference(last) < _every) return;
    _shownAt = at;
    unawaited(_readout.show(_current));
  }

  Future<void> _end() async {
    if (_ended) return;
    _ended = true;
    await _onPoint?.cancel();
    await _onStatus?.cancel();
    await _readout.end();
  }

  @override
  Future<void> start() async {
    await _inner.start();
    // A recorder that could not start has a problem to show, on the screen.
    // The lock screen does not announce a run that is not being recorded.
    if (_inner.problem != null) return;
    _onPoint = _inner.points.listen((RunPoint point) {
      _points.add(point);
      _show();
    });
    _onStatus = _inner.statusChanges.listen((RecorderStatus status) {
      if (status == RecorderStatus.stopped) {
        unawaited(_end());
      } else {
        // Paused and resumed are said at once: the clock has to stop, or
        // start, when the runner pressed the button and not four seconds on.
        _show(force: true);
      }
    });
    _show(force: true);
  }

  @override
  Future<void> pause() => _inner.pause();

  @override
  Future<void> resume() => _inner.resume();

  @override
  Future<void> stop() async {
    await _inner.stop();
    await _end();
  }

  @override
  Future<void> discard() async {
    await _inner.discard();
    await _end();
  }

  @override
  Stream<RunPoint> get points => _inner.points;

  @override
  Stream<RecorderStatus> get statusChanges => _inner.statusChanges;

  @override
  RecorderStatus get status => _inner.status;

  @override
  RecorderProblem? get problem => _inner.problem;

  @override
  Stream<RecorderProblem?> get problems => _inner.problems;

  @override
  RunPoint? get lastFix => _inner.lastFix;

  @override
  Duration? get sinceLastFix => _inner.sinceLastFix;

  @override
  Duration get elapsed => _inner.elapsed;
}
