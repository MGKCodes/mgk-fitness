import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:geolocator/geolocator.dart'
    show Geolocator, LocationAccuracy, LocationPermission, LocationSettings;
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../../coaching/domain/pace_model.dart';
import '../../coaching/domain/prescribed_distance.dart';
import '../../coaching/domain/race_day.dart' show aboutRaceTime;
import '../../coaching/domain/session_effort.dart';
import '../../coaching/domain/training_plan.dart';
import '../../coaching/presentation/session_labels.dart';
import '../domain/route_metrics.dart';
import '../domain/run_point.dart';
import '../../../core/config/app_config.dart';
import 'route_map.dart';

/// What the start screen has been told about where the runner is.
///
/// Three answers, because they are three different things to say to somebody
/// about to run: here you are, still looking, and not allowed to look.
@immutable
class StartFix {
  /// A position, with how good it is.
  const StartFix.at(RunPoint this.point) : allowed = true;

  /// Allowed to look, and nothing back yet.
  const StartFix.searching() : point = null, allowed = true;

  /// The app may not read location. Pressing Start is what asks.
  const StartFix.notAllowed() : point = null, allowed = false;

  final RunPoint? point;
  final bool allowed;
}

/// Asks the phone where it is, once. The start screen calls this every few
/// seconds while it is open.
typedef StartLocator = Future<StartFix> Function();

/// How often the start screen asks again.
const Duration kStartLocateEvery = Duration(seconds: 3);

/// The phone's own answer.
///
/// **One fix at a time, never the stream.** `geolocator` keeps a single
/// position stream for the whole app and hands the same one to every caller,
/// with the first caller's settings. The recorder opens that stream with
/// settings of its own (background updates, the Android notification), so a
/// stream opened here and still alive when the run begins would be the stream
/// the run is recorded on, without them. A one-shot fix is a separate call and
/// cannot get in the way.
///
/// **Never a prompt.** A runner who has not allowed location is asked when
/// they press Start, where the recorder has always asked. This only reads
/// what has been allowed already.
Future<StartFix> locateForStart() async {
  final LocationPermission permission = await Geolocator.checkPermission();
  if (permission != LocationPermission.whileInUse &&
      permission != LocationPermission.always) {
    return const StartFix.notAllowed();
  }
  try {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: Duration(seconds: 8),
      ),
    );
    return StartFix.at(
      RunPoint(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        timestamp: position.timestamp,
      ),
    );
  } on TimeoutException {
    return const StartFix.searching();
  }
}

/// How long the count-in runs for.
///
/// Three seconds, because it is doing two jobs and both want the same number:
/// long enough to get a phone into a pocket or an armband, and short enough
/// that somebody standing at a junction does not resent it. A longer count
/// starts measuring the wait rather than covering it.
const Duration kCountInDuration = Duration(seconds: 3);

/// The screen between deciding to run and running.
///
/// **Tapping *Record a run* used to start the clock.** The recorder began on
/// the same tap that opened the screen, so the first seconds of every run were
/// spent putting the phone away — recorded as running, at whatever pace a
/// pocket happens to be. The build 12 field test asked for this directly:
/// "open the run screen first, require an explicit separate start button, with
/// a countdown before recording actually begins".
///
/// It is also the honest place for the other thing that test asked for. The map
/// here **is** pannable, and the in-run map still is not, which is a
/// distinction rather than an inconsistency:
/// [RecordingScreen]'s own doc records why it takes no gestures — a pannable
/// map under a draggable sheet is a gesture-arena fight, and an earlier layout
/// lost it so completely that taps on the map did nothing at all. There is no
/// sheet here. Nothing is being dragged over this map, so nothing is competing
/// for the gesture, and a runner who wants to look at where they are about to
/// go can. Panning mid-run is still the wrong behaviour and still refused.
class RunStartScreen extends StatefulWidget {
  const RunStartScreen({
    super.key,
    required this.onStart,
    this.onCancel,
    this.plannedSession,
    this.paces,
    this.unit = UnitSystem.metric,
    this.focus,
    this.locate,
    this.countIn = kCountInDuration,
  });

  /// Called once the count-in has finished and recording should begin.
  final VoidCallback onStart;

  /// Backing out before anything has been recorded.
  final VoidCallback? onCancel;

  /// What the plan prescribed today, when it prescribed anything. Shown so the
  /// runner is reminded what they came out for before they set off, rather than
  /// discovering it on the in-run panel at 400 metres.
  final PlannedSession? plannedSession;

  /// The coach's paces, for the band today's session asks for and how long it
  /// should take. Null without a time trial, and the panel then says how the
  /// session should feel and leaves the numbers out.
  final TrainingPaces? paces;

  final UnitSystem unit;

  /// Where to look while there is no route yet.
  ///
  /// **An injection seam, not the only source.** This was declared and passed
  /// by nobody — `HomeShell` builds this screen without it — so `RouteMap` took
  /// the null, hit its "nothing to show and nowhere to look" branch, and drew
  /// the word *Finding you* on a plain ground forever. The map on this screen
  /// never appeared at all, and the first one a runner saw was the in-run map
  /// after pressing Start. Reported as C13 on the build 13 sheet, and the fifth
  /// defect in this release of the same shape: an argument nobody passed.
  ///
  /// Left null by the app and filled by [_RunStartScreenState._loadFocus] and
  /// then by [locate]. Supplied by tests and the preview harness, neither of
  /// which has a location plugin.
  final LatLng? focus;

  /// Where the runner is now, asked every [kStartLocateEvery] while the screen
  /// is open. Null uses the phone's own answer, [locateForStart].
  final StartLocator? locate;

  /// Overridable so a widget test does not have to wait three real seconds.
  final Duration countIn;

  @override
  State<RunStartScreen> createState() => _RunStartScreenState();
}

class _RunStartScreenState extends State<RunStartScreen> {
  /// Seconds left, or null while the runner has not started the count-in.
  int? _remaining;
  Timer? _ticker;

  /// The last fix the phone already had, so the map can draw before this screen
  /// has one of its own. Null until it answers, and on a phone that has none.
  LatLng? _focus;

  /// The newest answer to "where am I", or null before the first one.
  StartFix? _fix;
  Timer? _again;
  bool _asking = false;

  /// False once asking has thrown: a build with no location plugin (a widget
  /// test, the web preview) is not going to grow one in three seconds.
  bool _canAsk = true;

  /// Whether the map keeps to the runner. A pan parks it; the control that
  /// appears then puts it back.
  bool _following = true;

  /// How tall the panel is, so the map can end where it begins.
  double _panelHeight = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFocus());
    unawaited(_locate());
  }

  /// Lifted from [RecordingScreen], which does exactly this for the same
  /// reason: a cached fix costs nothing, arrives immediately, and is the
  /// difference between a map and a word.
  Future<void> _loadFocus() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null || !mounted || _focus != null) return;
      setState(() => _focus = LatLng(last.latitude, last.longitude));
    } catch (_) {
      // No cached fix, or no permission to read one. The acquiring state is
      // then the truthful answer rather than a failure.
    }
  }

  /// Asks where the runner is, and arranges to ask again.
  ///
  /// **This is what puts the runner on the map.** The screen used to read the
  /// phone's last known position once and never look again: a street map of
  /// wherever the phone last was, with nothing on it to say where the runner
  /// is. It also means the GPS has been running for as long as the screen has
  /// been open, so the run starts with a fix rather than hunting for one.
  ///
  /// Not during the count-in, and not after: from there the recorder owns the
  /// phone's location.
  Future<void> _locate() async {
    if (_asking || !mounted || _remaining != null || !_canAsk) return;
    _asking = true;
    StartFix? fix;
    try {
      fix = await (widget.locate ?? locateForStart)();
    } catch (_) {
      _canAsk = false;
    }
    _asking = false;
    if (!mounted) return;
    if (fix != null) {
      final RunPoint? at = fix.point;
      setState(() {
        _fix = fix;
        if (at != null) _focus = LatLng(at.latitude, at.longitude);
      });
    }
    if (_canAsk && _remaining == null) {
      _again = Timer(kStartLocateEvery, () => unawaited(_locate()));
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _again?.cancel();
    super.dispose();
  }

  void _begin() {
    if (_remaining != null) return;
    _again?.cancel();
    final int seconds = widget.countIn.inSeconds;
    // A zero-length count-in is a legitimate configuration (a test, or a
    // preference nobody has yet asked for) and must not leave the screen
    // showing a number that never counts down.
    if (seconds <= 0) {
      widget.onStart();
      return;
    }
    setState(() => _remaining = seconds);
    _ticker = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) return;
      final int next = (_remaining ?? 1) - 1;
      if (next > 0) {
        setState(() => _remaining = next);
        return;
      }
      t.cancel();
      widget.onStart();
    });
  }

  /// Cancelling the count-in, which must be possible: three seconds is long
  /// enough to change your mind, and a count nobody can stop is a countdown to
  /// something being done *to* them.
  void _abandon() {
    _ticker?.cancel();
    setState(() => _remaining = null);
    unawaited(_locate());
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int? remaining = _remaining;
    // The injected one wins, so a test or the harness can pin where to look.
    final LatLng? focus = widget.focus ?? _focus;
    final EdgeInsets safe = MediaQuery.paddingOf(context);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // The map stops where the panel starts (less the panel's rounded
          // shoulders), so the runner's dot is in the middle of the map they
          // can see rather than behind the panel.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: (_panelHeight - 28).clamp(0.0, double.infinity),
            child: RouteMap(
              points: const <RunPoint>[],
              focus: focus,
              // The whole reason this screen is a good home for the request.
              interactive: true,
              showPosition: true,
              follow: _following,
              onUserPan: () {
                if (_following) setState(() => _following = false);
              },
              followZoom: 16,
              emptyLabel: 'Finding you',
              tileUrlTemplate: AppConfig.current.mapTileUrlTemplate,
              attribution: AppConfig.current.mapAttribution,
              // Clear of the panel's shoulders.
              creditInsets: const EdgeInsets.only(right: 6, bottom: 34),
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ReportHeight(
              onHeight: (double height) {
                if (mounted && height != _panelHeight) {
                  setState(() => _panelHeight = height);
                }
              },
              child: _StartPanel(
                session: widget.plannedSession,
                paces: widget.paces,
                unit: widget.unit,
                fix: _fix,
                bottomInset: safe.bottom,
                onStart: _begin,
              ),
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _OnMap(
                    child: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: remaining == null ? widget.onCancel : null,
                      tooltip: 'Not now',
                    ),
                  ),
                  const Spacer(),
                  // Only while the map is parked, as on the in-run map: a
                  // recentre control on a map that is already centred is
                  // furniture.
                  if (!_following && focus != null)
                    _OnMap(
                      child: IconButton(
                        icon: const Icon(Icons.my_location),
                        onPressed: () => setState(() => _following = true),
                        tooltip: 'Recentre',
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Dimmed under the count, so the numeral is legible over whatever
          // the basemap happens to be showing, and the panel is out of reach.
          if (remaining != null)
            ColoredBox(
              color: const Color(0xE6000000),
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      '$remaining',
                      style: theme.textTheme.displayLarge?.copyWith(
                        fontSize: 120,
                        fontWeight: FontWeight.w600,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    AppTextButton(label: 'Stop', onPressed: _abandon),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A control over the map: a dark disc under it, so it reads on any street.
class _OnMap extends StatelessWidget {
  const _OnMap({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.bg.withValues(alpha: 0.72),
      shape: BoxShape.circle,
    ),
    child: child,
  );
}

/// Everything the runner is told before they press Start.
///
/// **The screen said "6 km · easy run" and nothing else.** That is the name of
/// the session, which the runner read on Home one tap ago. What they need
/// standing at the kerb is what the name does not say: how fast, for about how
/// long, how it should feel, and whether the phone knows where they are. All
/// of it was in the app already, on the session brief and the in-run panel;
/// none of it was here.
class _StartPanel extends StatelessWidget {
  const _StartPanel({
    required this.session,
    required this.paces,
    required this.unit,
    required this.fix,
    required this.bottomInset,
    required this.onStart,
  });

  final PlannedSession? session;
  final TrainingPaces? paces;
  final UnitSystem unit;
  final StartFix? fix;
  final double bottomInset;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final PlannedSession? run = session;

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.surface)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg,
          AppSpacing.lg + bottomInset,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _GpsLine(fix: fix),
            const SizedBox(height: AppSpacing.lg),
            if (run == null) ..._freeRun(theme) else ..._prescribed(theme, run),
            const SizedBox(height: AppSpacing.xl),
            PrimaryButton(label: 'Start', onPressed: onStart),
          ],
        ),
      ),
    );
  }

  List<Widget> _freeRun(ThemeData theme) => <Widget>[
    const SectionLabel('Free run'),
    const SizedBox(height: AppSpacing.sm),
    Text(
      'Run as you like',
      style: theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
      ),
    ),
    const SizedBox(height: AppSpacing.xs),
    Text(
      'Nothing counts down and nothing is judged. The route, the splits and '
      'the pace are recorded.',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: AppColors.textSecondary,
        height: 1.4,
      ),
    ),
  ];

  List<Widget> _prescribed(ThemeData theme, PlannedSession run) {
    final SessionEffort effort = effortFor(run.kind);
    final TrainingPaces? zones = paces;
    final PaceBand? band = zones == null ? null : bandFor(run.kind, zones);
    final bool hasDistance = run.distanceMeters > 0;
    // A runner's own name for the session ("parkrun") is kept as they wrote it.
    final String name = run.label ?? sessionName(run);
    final Duration? about = band == null || !hasDistance
        ? null
        : Duration(
            seconds:
                (run.distanceMeters / 1000 * band.middle.secondsPerKilometer)
                    .round(),
          );

    return <Widget>[
      const SectionLabel("Today's session"),
      const SizedBox(height: AppSpacing.sm),
      Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          if (hasDistance) ...<Widget>[
            Text(
              // In Home's words, since Home is the tap before this: a
              // prescription, in whole units, not a measurement.
              formatPrescribed(run.distanceMeters, unit),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (band != null) ...<Widget>[
            Expanded(
              flex: 5,
              child: StatBlock(
                // The unit is in the label, so the figure is only the two
                // paces: with "/km" after it the widest of the three ran
                // into its neighbour on a phone.
                label: 'Pace ${unit.paceSuffix}',
                value: _withoutUnit(band.format(unit), unit),
                shrinkToFit: true,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          if (about != null) ...<Widget>[
            Expanded(
              flex: 4,
              child: StatBlock(
                label: 'About',
                value: aboutRaceTime(about),
                shrinkToFit: true,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            flex: 3,
            child: StatBlock(
              label: 'Effort',
              value: effort.rpe,
              shrinkToFit: true,
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.lg),
      Text(
        // How to tell, from the inside, that it is being run right. The line
        // the brief leads with, and the one a pace cannot replace on a hill.
        effort.feel,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: AppColors.textSecondary,
          height: 1.4,
        ),
      ),
    ];
  }
}

/// "5:47–6:15 /km" as "5:47–6:15".
String _withoutUnit(String band, UnitSystem unit) {
  final String suffix = ' ${unit.paceSuffix}';
  return band.endsWith(suffix)
      ? band.substring(0, band.length - suffix.length)
      : band;
}

/// Whether the phone knows where the runner is, in one line.
///
/// Green only when a run started now would be measured properly: the same
/// accuracy the recorder counts distance at. A fix worse than that is said to
/// be weak rather than passed off as ready, and one the recorder would throw
/// away is still "finding".
class _GpsLine extends StatelessWidget {
  const _GpsLine({required this.fix});

  final StartFix? fix;

  @override
  Widget build(BuildContext context) {
    final StartFix? now = fix;
    final RunPoint? at = now?.point;
    final double? accuracy = at?.accuracyMeters;

    final String label;
    final Color dot;
    String? detail;
    if (now != null && !now.allowed) {
      label = 'Location is not on for Run';
      detail = 'Start asks for it';
      dot = AppColors.textTertiary;
    } else if (accuracy == null || accuracy > kMaxRecordableAccuracyMeters) {
      label = 'Finding GPS';
      dot = AppColors.textTertiary;
    } else if (accuracy > kMaxHorizontalAccuracyMeters) {
      label = 'GPS is weak';
      detail = 'within ${accuracy.round()} m';
      dot = AppColors.primary;
    } else {
      label = 'GPS ready';
      detail = 'within ${accuracy.round()} m';
      dot = AppColors.success;
    }

    return Row(
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          label,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        if (detail != null)
          Text(
            detail,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 13,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}

/// Reports its child's height after layout, and again when it changes.
class _ReportHeight extends SingleChildRenderObjectWidget {
  const _ReportHeight({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderReportHeight(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderReportHeight renderObject,
  ) {
    renderObject.onHeight = onHeight;
  }
}

class _RenderReportHeight extends RenderProxyBox {
  _RenderReportHeight(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final double height = size.height;
    if (height == _reported) return;
    _reported = height;
    // After the frame: telling the parent now would be a setState in layout.
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}
