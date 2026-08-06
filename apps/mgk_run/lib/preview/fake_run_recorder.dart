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
  }) : _trace = trace ?? demoRunTrace();

  final List<RunPoint> _trace;
  final Duration interval;

  final StreamController<RunPoint> _points =
      StreamController<RunPoint>.broadcast();
  final StreamController<RecorderStatus> _statuses =
      StreamController<RecorderStatus>.broadcast();

  RecorderStatus _status = RecorderStatus.idle;
  Timer? _timer;
  int _index = 0;

  @override
  Stream<RunPoint> get points => _points.stream;

  @override
  Stream<RecorderStatus> get statusChanges => _statuses.stream;

  @override
  RecorderStatus get status => _status;

  void _setStatus(RecorderStatus next) {
    _status = next;
    _statuses.add(next);
  }

  @override
  Future<void> start() async {
    if (_status == RecorderStatus.recording) return;
    _setStatus(RecorderStatus.recording);
    _timer = Timer.periodic(interval, (_) {
      if (_status != RecorderStatus.recording) return;
      if (_index >= _trace.length) {
        _timer?.cancel();
        return;
      }
      _points.add(_trace[_index++]);
    });
  }

  @override
  Future<void> pause() async {
    if (_status == RecorderStatus.recording) _setStatus(RecorderStatus.paused);
  }

  @override
  Future<void> resume() async {
    if (_status == RecorderStatus.paused) _setStatus(RecorderStatus.recording);
  }

  @override
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _setStatus(RecorderStatus.stopped);
  }

  @override
  Future<void> discard() async {
    _timer?.cancel();
    _timer = null;
    _setStatus(RecorderStatus.stopped);
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
