import 'dart:async';
import 'dart:math' as math;

import 'package:mgk_run/src/features/recording/domain/run_point.dart';
import 'package:mgk_run/src/features/recording/domain/run_recorder.dart';

/// In-memory [RunRecorder] for the preview harness and widget tests: replays a
/// canned trace on a timer so the recording screen animates, with no location
/// plugin and no database. Pause/resume/stop behave like the real recorder.
class FakeRunRecorder implements RunRecorder {
  FakeRunRecorder({
    List<RunPoint>? trace,
    this.interval = const Duration(milliseconds: 500),
    this.failsWith,
    this.acquireAfter = Duration.zero,
    DateTime Function()? now,
  }) : _trace = trace ?? demoRunTrace(),
       _now = now ?? DateTime.now;

  final List<RunPoint> _trace;
  final Duration interval;

  /// Injectable for the same reason the real recorder's is: elapsed time now
  /// comes from the wall clock, and `tester.pump` advances Flutter's timers
  /// without touching `DateTime.now`. A widget test cannot watch the clock move
  /// unless it owns the clock.
  final DateTime Function() _now;

  /// Starts in a failed state, so the harness can render what a refused
  /// permission or a switched-off location service actually looks like. Those
  /// states shipped unlooked-at once already.
  final RecorderProblem? failsWith;

  /// How long to sit fixless before the trace begins — the "acquiring GPS"
  /// state every real run opens with and no screenshot had ever shown.
  final Duration acquireAfter;

  final StreamController<RunPoint> _points =
      StreamController<RunPoint>.broadcast();
  final StreamController<RecorderStatus> _statuses =
      StreamController<RecorderStatus>.broadcast();
  final StreamController<RecorderProblem?> _problems =
      StreamController<RecorderProblem?>.broadcast();

  RecorderStatus _status = RecorderStatus.idle;
  RecorderProblem? _problem;
  RunPoint? _lastFix;
  Timer? _timer;
  Timer? _acquireTimer;
  int _index = 0;

  /// The fake keeps the same clock the real recorder does: wall time, less
  /// anything explicitly paused, so the harness and the widget tests model the
  /// app the device runs rather than a slightly different one.
  DateTime? _startedAt;
  Duration _pausedTotal = Duration.zero;
  DateTime? _pausedAt;

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

  /// The canned trace never stops moving, so the preview never auto-pauses.
  /// A harness screen for that state would need a trace with a stop in it.
  @override
  bool get autoPaused => false;

  @override
  Duration get elapsed {
    final started = _startedAt;
    if (started == null) return Duration.zero;
    final until = _pausedAt ?? _now();
    final total = until.difference(started) - _pausedTotal;
    return total.isNegative ? Duration.zero : total;
  }

  void _setStatus(RecorderStatus next) {
    _status = next;
    _statuses.add(next);
  }

  @override
  Future<void> start() async {
    if (_status == RecorderStatus.recording) return;
    _startedAt = _now();
    _pausedTotal = Duration.zero;
    _pausedAt = null;

    if (failsWith != null) {
      _problem = failsWith;
      _problems.add(failsWith);
      _setStatus(RecorderStatus.idle);
      return;
    }

    _setStatus(RecorderStatus.recording);
    _acquireTimer = Timer(acquireAfter, _beginReplay);
  }

  void _beginReplay() {
    _timer = Timer.periodic(interval, (_) {
      if (_status != RecorderStatus.recording) return;
      if (_index >= _trace.length) {
        _timer?.cancel();
        return;
      }
      final fix = _trace[_index++];
      _lastFix = fix;
      _points.add(fix);
    });
  }

  @override
  Future<void> pause() async {
    if (_status != RecorderStatus.recording) return;
    _pausedAt = _now();
    _setStatus(RecorderStatus.paused);
  }

  @override
  Future<void> resume() async {
    if (_status != RecorderStatus.paused) return;
    final pausedAt = _pausedAt;
    if (pausedAt != null) {
      _pausedTotal += _now().difference(pausedAt);
      _pausedAt = null;
    }
    _setStatus(RecorderStatus.recording);
  }

  @override
  Future<void> stop() async {
    _cancelTimers();
    _setStatus(RecorderStatus.stopped);
  }

  @override
  Future<void> discard() async {
    _cancelTimers();
    _setStatus(RecorderStatus.stopped);
  }

  void _cancelTimers() {
    _timer?.cancel();
    _timer = null;
    // The acquire timer outlives a stop that happens during the fixless
    // opening, and a pending timer is what `testWidgets` fails a teardown on.
    _acquireTimer?.cancel();
    _acquireTimer = null;
  }
}

/// A demo run around a park. Shared by the fake recorder and the map preview.
///
/// It's a loop, but a deliberately *wobbly* one — the radius is perturbed and
/// each fix jittered, so it reads like a real run following streets rather than
/// a perfect circle. This is fake data; real GPS traces come from the recorder.
List<RunPoint> demoRunTrace() {
  const baseLat = 51.5450;
  const baseLng = -0.1500;
  const radius = 0.0026;
  final lngScale = 1 / math.cos(baseLat * math.pi / 180);
  final start = DateTime(2026, 1, 1, 8);
  final points = <RunPoint>[];
  for (var i = 0; i < 440; i++) {
    final t = i * 0.0143; // ~one full loop over the run
    final r =
        radius * (1 + 0.28 * math.sin(t * 2) + 0.12 * math.sin(t * 5 + 0.7));
    points.add(
      RunPoint(
        latitude: baseLat + r * math.sin(t) + 0.00002 * math.sin(i * 1.7),
        longitude:
            baseLng + lngScale * r * math.cos(t) + 0.00002 * math.cos(i * 2.3),
        accuracyMeters: 5,
        altitudeMeters: 40,
        timestamp: start.add(Duration(seconds: i * 3)),
      ),
    );
  }
  return points;
}
