import 'dart:async';

import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../domain/route_metrics.dart';
import '../domain/run_point.dart';
import '../domain/run_recorder.dart';
import 'route_map.dart';

/// The in-run hero: big live distance, elapsed time and pace, with pause /
/// finish controls. Driven entirely by the [RunRecorder] seam, so it renders
/// against a fake in the preview and tests, and against the real
/// geolocator-backed recorder on device.
///
/// Distances/paces are formatted through the unit layer at the display edge —
/// the stored values stay metric (see docs/design + the store-metric rule).
class RecordingScreen extends StatefulWidget {
  const RecordingScreen({
    super.key,
    required this.recorder,
    this.unit = UnitSystem.metric,
    this.onFinish,
    this.onCancel,
  });

  final RunRecorder recorder;
  final UnitSystem unit;

  /// Called after [RunRecorder.stop] completes (e.g. to show the run summary).
  final VoidCallback? onFinish;

  /// Called after the run is discarded (nothing saved). Null hides the cancel
  /// affordance.
  final VoidCallback? onCancel;

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  final List<RunPoint> _points = <RunPoint>[];
  double _distanceM = 0;
  Duration _elapsed = Duration.zero;
  late RecorderStatus _status = widget.recorder.status;

  StreamSubscription<RunPoint>? _pointSub;
  StreamSubscription<RecorderStatus>? _statusSub;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _pointSub = widget.recorder.points.listen((point) {
      _points.add(point);
      setState(() => _distanceM = processedDistanceMeters(_points));
    });
    _statusSub = widget.recorder.statusChanges.listen(
      (status) => setState(() => _status = status),
    );
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_status == RecorderStatus.recording) {
        setState(() => _elapsed += const Duration(seconds: 1));
      }
    });
    // Reaching this screen means the run is starting.
    widget.recorder.start();
    _status = widget.recorder.status;
  }

  @override
  void dispose() {
    _pointSub?.cancel();
    _statusSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  bool get _recording => _status == RecorderStatus.recording;

  Future<void> _togglePause() =>
      _recording ? widget.recorder.pause() : widget.recorder.resume();

  Future<void> _finish() async {
    await widget.recorder.stop();
    widget.onFinish?.call();
  }

  Future<void> _cancel() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Discard this run?'),
        content: const Text("Your progress won't be saved."),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep running'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard != true) return;
    await widget.recorder.discard();
    if (mounted) widget.onCancel?.call();
  }

  String get _paceLabel {
    if (_distanceM <= 0 || _elapsed == Duration.zero) {
      return '--:-- ${widget.unit.paceSuffix}';
    }
    return Pace.from(Distance.meters(_distanceM), _elapsed).format(widget.unit);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The map fills the screen and the readout floats on it as glass, rather
      // than the two splitting the screen between them. That is what gives the
      // panel something to refract: over an opaque charcoal band the blur would
      // do nothing (docs/design/design-system.md).
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: RouteMap(points: _points, interactive: false),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Center(child: _StatusPill(recording: _recording)),
                    ),
                  ),
                ),
                if (widget.onCancel != null)
                  Positioned(
                    top: 0,
                    left: 0,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4, top: 4),
                        child: IconButton(
                          icon: const Icon(Icons.close),
                          color: AppColors.textPrimary,
                          tooltip: 'Cancel run',
                          onPressed: _cancel,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // The readout, as glass over the live route.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: GlassSurface(
              // Flush to the bottom edge, so only the top corners are rounded —
              // a fully rounded card here would leave slivers of map in the
              // bottom corners.
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.sheet),
              ),
              padding: EdgeInsets.zero,
              // A map is busier than the photography, so the pane leans a little
              // more opaque to keep the numbers readable over any street.
              tintOpacity: 0.14,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      StatBlock(
                        align: CrossAxisAlignment.center,
                        size: StatSize.display,
                        label: 'Distance',
                        value: Distance.meters(_distanceM).format(widget.unit),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: <Widget>[
                          StatBlock(
                            align: CrossAxisAlignment.center,
                            size: StatSize.hero,
                            label: 'TIME',
                            value: _elapsed.hoursMinutesSeconds,
                          ),
                          StatBlock(
                            align: CrossAxisAlignment.center,
                            size: StatSize.hero,
                            label: 'PACE',
                            value: _paceLabel,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _togglePause,
                              child: Text(_recording ? 'Pause' : 'Resume'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: _finish,
                              child: const Text('Finish'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A pulsing dot + label showing whether recording is live or paused. The dot
/// is monochrome (greyscale design language — no colour, ADR-0009); motion, not
/// hue, signals "live".
class _StatusPill extends StatefulWidget {
  const _StatusPill({required this.recording});

  final bool recording;

  @override
  State<_StatusPill> createState() => _StatusPillState();
}

class _StatusPillState extends State<_StatusPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        FadeTransition(
          opacity: widget.recording
              ? Tween<double>(begin: 0.25, end: 1).animate(_pulse)
              : const AlwaysStoppedAnimation<double>(0.4),
          child: Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: AppColors.textPrimary,
              shape: BoxShape.circle,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          widget.recording ? 'Recording' : 'Paused',
          style: theme.textTheme.labelLarge?.copyWith(letterSpacing: 1.5),
        ),
      ],
    );
  }
}
