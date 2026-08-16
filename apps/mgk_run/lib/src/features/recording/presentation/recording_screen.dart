import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' show Geolocator;
import 'package:latlong2/latlong.dart' show LatLng;

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import '../../coaching/domain/training_plan.dart';
import '../domain/live_metrics.dart';
import '../domain/route_metrics.dart';
import '../domain/run_point.dart';
import '../domain/run_recorder.dart';
import '../domain/run_split.dart';
import 'recording_readout.dart';
import 'route_map.dart';

/// The in-run screen: the distance as a hero numeral, the pace pair under it,
/// the route as a strip that opens, and the splits as they land.
///
/// **Numbers first, map second.** The map used to fill the screen with the
/// readout floating on it as glass, which looked good in a screenshot and read
/// badly at arm's length mid-stride: the one number a runner glances down for
/// was rendered at 44pt — the size this design language uses for a summary tile
/// — while the thing they look at maybe twice a run had the whole screen. This
/// inverts that. The map is a strip that expands on tap, so it is there when
/// somebody wants it and quiet when they don't.
///
/// Driven entirely by the [RunRecorder] seam, so it renders against a fake in
/// the preview and tests, and against the real geolocator-backed recorder on
/// device.
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
    this.plannedSession,
  });

  final RunRecorder recorder;
  final UnitSystem unit;

  /// Called after [RunRecorder.stop] completes (e.g. to show the run summary).
  final VoidCallback? onFinish;

  /// Called after the run is discarded (nothing saved). Null hides the cancel
  /// affordance.
  final VoidCallback? onCancel;

  /// What the plan prescribed for today, when it prescribed anything.
  ///
  /// The one thing a generic tracker cannot show: a runner mid-effort seeing
  /// how far through their coach's session they are. Null on an unplanned day,
  /// and then the block is simply absent (principle 6: absent beats zero).
  final PlannedSession? plannedSession;

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  final List<RunPoint> _points = <RunPoint>[];
  double _distanceM = 0;
  List<RunSplit> _splits = const <RunSplit>[];
  late RecorderStatus _status = widget.recorder.status;
  RecorderProblem? _problem;
  bool _mapExpanded = false;

  StreamSubscription<RunPoint>? _pointSub;
  StreamSubscription<RecorderStatus>? _statusSub;
  StreamSubscription<RecorderProblem?>? _problemSub;
  Timer? _ticker;

  /// The device's last known position, used only to point the map somewhere
  /// plausible until the first real fix arrives.
  LatLng? _focus;

  @override
  void initState() {
    super.initState();
    _loadFocus();
    _pointSub = widget.recorder.points.listen((point) {
      _points.add(point);
      setState(() {
        _distanceM = processedDistanceMeters(_points);
        _splits = splitsFor(_points);
      });
    });
    _statusSub = widget.recorder.statusChanges.listen((status) {
      setState(() => _status = status);
      _syncTicker();
    });
    _problemSub = widget.recorder.problems.listen(
      (problem) => setState(() => _problem = problem),
    );
    // Reaching this screen means the run is starting.
    widget.recorder.start();
    _status = widget.recorder.status;
    _problem = widget.recorder.problem;
    _syncTicker();
  }

  /// Runs a repaint tick only while the clock is actually moving.
  ///
  /// This is a *repaint*, NOT the source of truth — elapsed time is read from
  /// the recorder's wall clock, because iOS throttles and then suspends timers
  /// behind a locked screen, and a ticker that accumulated its own total came
  /// back from a backgrounded run minutes short with a pace to match.
  ///
  /// Paused, idle and stopped all freeze [RunRecorder.elapsed], so a timer in
  /// those states would repaint an unchanging number once a second forever.
  void _syncTicker() {
    final shouldTick = _status == RecorderStatus.recording;
    if (shouldTick) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  @override
  void dispose() {
    _pointSub?.cancel();
    _statusSub?.cancel();
    _problemSub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  /// The cached fix iOS already holds — free, instant, and no extra prompt.
  ///
  /// Best-effort by design: it is only ever used to aim the camera, so a
  /// failure or a null simply leaves the map in its acquiring state rather
  /// than being worth a message.
  Future<void> _loadFocus() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null || !mounted) return;
      setState(() => _focus = LatLng(last.latitude, last.longitude));
    } catch (_) {
      // No cached position, or no permission to read one. Nothing to say.
    }
  }

  Duration get _elapsed => widget.recorder.elapsed;

  bool get _recording => _status == RecorderStatus.recording;

  bool get _autoPaused => widget.recorder.autoPaused;

  /// Recording, but no fix has landed yet — the honest opening state of every
  /// run. CoreLocation takes ten to thirty seconds to settle, and rendering
  /// that as a confident 0.00 km is what made a working app look broken.
  bool get _acquiring => _recording && _points.isEmpty && _problem == null;

  String get _statusLabel {
    if (_problem != null) return 'Not recording';
    if (_acquiring) return 'Acquiring GPS';
    if (!_recording) return 'Paused';
    return _autoPaused ? 'Auto-paused' : 'Recording';
  }

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

  /// How far before an average pace means anything.
  ///
  /// **A stationary phone still moves.** GPS drifts by metres while sitting on
  /// a table, so any floor of zero lets elapsed time divide by noise: standing
  /// at the start line for ten minutes with four metres of jitter reads as
  /// 2500 min/km, climbing. That is what the first device test showed.
  ///
  /// A hundred metres is roughly half a minute of running — soon enough that a
  /// runner is not left staring at dashes, far enough that drift cannot
  /// dominate the quotient. The same instinct as `RunnerStats`, which refuses
  /// to call anything under a kilometre a fastest pace.
  static const double _paceFloorMeters = 100;

  String get _dashes => '--:-- ${widget.unit.paceSuffix}';

  /// The pace over the whole run so far. Labelled as an average, because that
  /// is what it is — the screen used to call this "PACE", which is the question
  /// a runner asks mid-stride and the one number that cannot answer it.
  String get _averagePace {
    if (_distanceM < _paceFloorMeters || _elapsed == Duration.zero) {
      // Dashes rather than a number, because "no pace yet" is the true answer
      // and a plausible wrong one is worse than an obvious absence.
      return _dashes;
    }
    return Pace.from(Distance.meters(_distanceM), _elapsed).format(widget.unit);
  }

  /// What the runner is doing *now*, over a trailing window. Null while
  /// stopped or before there is enough movement — dashes, not a guess.
  String get _currentPace =>
      rollingPace(_points)?.format(widget.unit) ?? _dashes;

  String? get _sessionTitle {
    final session = widget.plannedSession;
    if (session == null) return null;
    if (session.label != null) return session.label;
    final name = switch (session.kind) {
      SessionKind.recovery => 'Recovery run',
      SessionKind.easy => 'Easy run',
      SessionKind.long => 'Long run',
      SessionKind.marathonPace => 'Marathon pace',
      SessionKind.threshold => 'Threshold',
      SessionKind.interval => 'Intervals',
      SessionKind.timeTrial => 'Time trial',
      SessionKind.rest || SessionKind.strength => null,
    };
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.plannedSession;
    final title = _sessionTitle;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _TopBar(
              label: _statusLabel,
              pulsing: _recording && !_autoPaused,
              signal: gpsSignalFor(widget.recorder.lastFix),
              onCancel: widget.onCancel == null ? null : _cancel,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.md,
                  AppSpacing.xl,
                  AppSpacing.lg,
                ),
                children: <Widget>[
                  if (_problem != null) ...<Widget>[
                    _ProblemBanner(problem: _problem!),
                    const SizedBox(height: AppSpacing.xl),
                  ],

                  // The one number the screen is for.
                  HeroNumeral(
                    label: 'DISTANCE',
                    value: Distance.meters(
                      _distanceM,
                    ).inDisplayUnit(widget.unit),
                    unit: widget.unit.distanceSuffix,
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Time, then the two paces. Current is what a runner reads
                  // mid-stride; average is what they judge the run by after.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: <Widget>[
                      RunStat(
                        label: 'TIME',
                        value: _elapsed.hoursMinutesSeconds,
                      ),
                      RunStat(
                        label: 'PACE',
                        value: _currentPace,
                        muted: _currentPace == _dashes,
                      ),
                      RunStat(
                        label: 'AVG',
                        value: _averagePace,
                        muted: _averagePace == _dashes,
                      ),
                    ],
                  ),

                  if (title != null) ...<Widget>[
                    const SizedBox(height: AppSpacing.xl),
                    AppCard(
                      child: TargetBand(
                        title: title,
                        unit: widget.unit,
                        doneMeters: _distanceM,
                        targetMeters: session!.distanceMeters,
                      ),
                    ),
                  ],

                  const SizedBox(height: AppSpacing.xl),
                  _MapStrip(
                    points: _points,
                    focus: _focus,
                    expanded: _mapExpanded,
                    onTap: () => setState(() => _mapExpanded = !_mapExpanded),
                  ),

                  if (_splits.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpacing.xl),
                    const SectionLabel('SPLITS'),
                    const SizedBox(height: AppSpacing.md),
                    SplitList(
                      splits: _splits,
                      unit: widget.unit,
                      // Mid-effort nobody is reading kilometre two. The
                      // summary screen shows the lot.
                      maxRows: 4,
                      newestFirst: true,
                    ),
                  ],
                ],
              ),
            ),
            _Controls(
              recording: _recording,
              onTogglePause: _togglePause,
              onFinish: _finish,
            ),
          ],
        ),
      ),
    );
  }
}

/// Status, signal and the way out. Everything that says whether the app is
/// working, in one strip at the top.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.label,
    required this.pulsing,
    required this.signal,
    this.onCancel,
  });

  final String label;
  final bool pulsing;
  final GpsSignal signal;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, 20, 0),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 44,
            child: onCancel == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    color: AppColors.textSecondary,
                    tooltip: 'Cancel run',
                    onPressed: onCancel,
                  ),
          ),
          Expanded(
            child: Center(
              child: _StatusPill(label: label, pulsing: pulsing),
            ),
          ),
          SizedBox(
            width: 44,
            child: Align(
              alignment: Alignment.centerRight,
              child: GpsSignalBars(signal: signal),
            ),
          ),
        ],
      ),
    );
  }
}

/// The route, as a strip that opens.
///
/// Collapsed it is a glance — am I where I think I am. Tapped it is most of the
/// screen, for the moment somebody actually wants to look at where they have
/// been. It is never the whole screen, because the numbers are.
class _MapStrip extends StatelessWidget {
  const _MapStrip({
    required this.points,
    required this.focus,
    required this.expanded,
    required this.onTap,
  });

  final List<RunPoint> points;
  final LatLng? focus;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.slow,
        curve: AppMotion.entrance,
        height: expanded ? 380 : 132,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.elevated),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            RouteMap(
              points: points,
              focus: focus,
              // Taps belong to the expand gesture until it is open; once it
              // is, panning and zooming are the point.
              interactive: expanded,
              showPosition: true,
              followZoom: expanded ? 16 : 15,
            ),
            Positioned(
              right: 8,
              top: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.bg.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    expanded ? Icons.close_fullscreen : Icons.open_in_full,
                    size: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Pause/resume and finish, pinned so they are always under the thumb.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.recording,
    required this.onTogglePause,
    required this.onFinish,
  });

  final bool recording;
  final Future<void> Function() onTogglePause;
  final Future<void> Function() onFinish;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.sm,
        AppSpacing.xl,
        AppSpacing.md,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: OutlinedButton(
              onPressed: onTogglePause,
              child: Text(recording ? 'Pause' : 'Resume'),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: FilledButton(
              onPressed: onFinish,
              child: const Text('Finish'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Says why the run is not recording, and what would fix it.
///
/// The states differ in remedy, so they differ in copy and in action. Offering
/// "Open Settings" for a switched-off Location Services toggle sends people to
/// a screen that cannot fix it; offering to re-ask after a permanent refusal is
/// simply untrue. A denied read is a designed-for outcome, not an error state
/// (the same rule the HealthKit layer follows).
class _ProblemBanner extends StatelessWidget {
  const _ProblemBanner({required this.problem});

  final RecorderProblem problem;

  String get _message => switch (problem) {
    RecorderProblem.locationServicesOff =>
      'Location Services are off, so this run cannot be tracked. '
          'Turn them on in Settings → Privacy & Security → Location Services.',
    RecorderProblem.permissionDenied =>
      'Run needs your location to record a route. Nothing is being tracked '
          'until you allow it.',
    RecorderProblem.permissionDeniedForever =>
      'Location is turned off for Run, so there is nothing to record. '
          'You can change it in Settings.',
    RecorderProblem.locationFailed =>
      'Your location stopped arriving, so recording has paused. This usually '
          'clears on its own outdoors.',
  };

  /// Only where Settings can actually change the outcome.
  bool get _offersSettings =>
      problem == RecorderProblem.permissionDenied ||
      problem == RecorderProblem.permissionDeniedForever;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.elevated),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            _message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.textSecondary,
              height: 1.45,
            ),
          ),
          if (_offersSettings) ...<Widget>[
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: Geolocator.openAppSettings,
                child: const Text('Open Settings'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A pulsing dot + label showing whether recording is live, searching or
/// paused. The dot is monochrome (greyscale design language — no colour,
/// ADR-0009); motion, not hue, signals "live".
///
/// The pulse itself is `Pulse` from the design system now. It was hand-rolled
/// here, and the hand-rolled version repeated forever regardless of state —
/// burning a ticker under a paused pill and hanging any `pumpAndSettle` that
/// reached this screen. Principle 9: make it a component.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.pulsing});

  final String label;
  final bool pulsing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Pulse(
          active: pulsing,
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
          label,
          style: theme.textTheme.labelLarge?.copyWith(letterSpacing: 1.5),
        ),
      ],
    );
  }
}
