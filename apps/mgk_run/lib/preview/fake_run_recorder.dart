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

  /// When the newest fix arrived — see [RunRecorder.sinceLastFix].
  DateTime? _lastFixAt;
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

  @override
  Duration? get sinceLastFix {
    final at = _lastFixAt;
    if (at == null) return null;
    final age = _now().difference(at);
    // A fix timestamped fractionally ahead of the clock is a rounding artefact,
    // not time travel; report it as fresh rather than negative.
    return age.isNegative ? Duration.zero : age;
  }

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
      _lastFixAt = _now();
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

/// Metres between two nearby coordinates, flat-earth style.
///
/// Equirectangular rather than haversine on purpose: over a few hundred metres
/// the difference is millimetres, and this is fake data being laid out, not a
/// measurement being taken. The recorder's own distances go through
/// `route_metrics.dart`.
double _metersBetween(double lat1, double lng1, double lat2, double lng2) {
  const double metersPerDegree = 111320;
  final double dy = (lat2 - lat1) * metersPerDegree;
  final double dx =
      (lng2 - lng1) * metersPerDegree * math.cos(lat1 * math.pi / 180);
  return math.sqrt(dx * dx + dy * dy);
}

/// A demo run around a park. Shared by the fake recorder and the map preview.
///
/// It's a loop, but a deliberately *wobbly* one — the radius is perturbed and
/// each fix jittered, so it reads like a real run following streets rather than
/// a perfect circle. This is fake data; real GPS traces come from the recorder.
///
/// [pacePerKm] asks for a run at a chosen pace. The default loop averages
/// ~9:32/km over its whole length, and nearer 8:45 across the opening quarter
/// the plates actually show — either way outside every band the coach
/// prescribes: fine for judging a layout, useless for judging the band, because
/// a screen driven by it says PICK IT UP at every distance and can never render
/// ON TARGET or EASE OFF.
///
/// **A paced trace is resampled, not scaled.** Scaling the radius was the
/// obvious approach and it is wrong: the radius is modulated by two sine terms,
/// so the loop's speed varies around it and there is no single number to scale.
/// A constant measured off the first quarter of the loop ran ~50 s/km fast
/// against the whole of it. Instead the shape is walked at a fine step and a fix
/// is laid down every time the required arc length has been covered, so the run
/// happens at the asked pace *everywhere* rather than on average.
///
/// The per-fix jitter is dropped when a pace is asked for. At ~2 m amplitude
/// against a ~7 m spacing it is a third of the distance between fixes, which is
/// precisely what makes a pace unpredictable — and an unpredictable pace is the
/// one thing a paced trace must not have. The radius wobble stays, so the route
/// still bends like streets.
List<RunPoint> demoRunTrace({Duration? pacePerKm}) {
  const double baseLat = 51.5450;
  const double baseLng = -0.1500;
  const double radius = 0.0026;
  const int count = 440;
  final double lngScale = 1 / math.cos(baseLat * math.pi / 180);
  final DateTime start = DateTime(2026, 1, 1, 8);

  /// The loop's shape at [t] radians around it.
  (double, double) shapeAt(double t) {
    final double r =
        radius * (1 + 0.28 * math.sin(t * 2) + 0.12 * math.sin(t * 5 + 0.7));
    return (baseLat + r * math.sin(t), baseLng + lngScale * r * math.cos(t));
  }

  RunPoint fixAt(double lat, double lng, int i) => RunPoint(
    latitude: lat,
    longitude: lng,
    accuracyMeters: 5,
    altitudeMeters: 40,
    timestamp: start.add(Duration(seconds: i * 3)),
  );

  final List<RunPoint> points = <RunPoint>[];

  if (pacePerKm == null) {
    for (int i = 0; i < count; i++) {
      final double t = i * 0.0143; // ~one full loop over the run
      final (double lat, double lng) = shapeAt(t);
      points.add(
        fixAt(
          lat + 0.00002 * math.sin(i * 1.7),
          lng + 0.00002 * math.cos(i * 2.3),
          i,
        ),
      );
    }
    return points;
  }

  // Fixes are three seconds apart, so the ground each one must cover follows
  // directly from the pace asked for.
  final double metersPerPoint = 3000 / pacePerKm.inSeconds;

  double t = 0;
  (double, double) here = shapeAt(t);
  points.add(fixAt(here.$1, here.$2, 0));

  double carried = 0;
  // Bounded so a pathological pace cannot spin forever; 40 laps is far past
  // anything the harness asks for.
  const double tLimit = 2 * math.pi * 40;
  while (points.length < count && t < tLimit) {
    t += 0.0001;
    final (double, double) next = shapeAt(t);
    carried += _metersBetween(here.$1, here.$2, next.$1, next.$2);
    here = next;
    if (carried >= metersPerPoint) {
      carried -= metersPerPoint;
      points.add(fixAt(here.$1, here.$2, points.length));
    }
  }

  return points;
}
