import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' show Geolocator;
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../../coaching/domain/training_plan.dart';
import '../domain/run_point.dart';
import '../../../core/config/app_config.dart';
import 'route_map.dart';

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
    this.unit = UnitSystem.metric,
    this.focus,
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
  /// Left null by the app and filled by [_RunStartScreenState._loadFocus],
  /// which is where [RecordingScreen] gets the same answer. Supplied by tests
  /// and the preview harness, neither of which has a location plugin.
  final LatLng? focus;

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

  @override
  void initState() {
    super.initState();
    unawaited(_loadFocus());
  }

  /// Lifted from [RecordingScreen], which does exactly this for the same
  /// reason: a cached fix costs nothing, arrives immediately, and is the
  /// difference between a map and a word.
  Future<void> _loadFocus() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null || !mounted) return;
      setState(() => _focus = LatLng(last.latitude, last.longitude));
    } catch (_) {
      // No cached fix, or no permission to read one. The acquiring state is
      // then the truthful answer rather than a failure.
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _begin() {
    if (_remaining != null) return;
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
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int? remaining = _remaining;
    final PlannedSession? session = widget.plannedSession;
    // The injected one wins, so a test or the harness can pin where to look.
    final LatLng? focus = widget.focus ?? _focus;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          RouteMap(
            points: const <RunPoint>[],
            focus: focus,
            // The whole reason this screen is a good home for the request.
            interactive: true,
            showPosition: true,
            followZoom: 16,
            emptyLabel: 'Finding you',
            tileUrlTemplate: AppConfig.current.mapTileUrlTemplate,
            attribution: AppConfig.current.mapAttribution,
          ),

          // Dimmed under the count, so the numeral is legible over whatever the
          // basemap happens to be showing. Absent otherwise: the map is the
          // point of this screen until the runner has committed.
          if (remaining != null)
            const ColoredBox(
              color: Color(0xCC000000),
              child: SizedBox.expand(),
            ),

          SafeArea(
            child: Column(
              children: <Widget>[
                Align(
                  alignment: Alignment.centerLeft,
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: remaining == null ? widget.onCancel : null,
                    tooltip: 'Not now',
                  ),
                ),
                const Spacer(),
                if (remaining != null) ...<Widget>[
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
                ] else ...<Widget>[
                  if (session != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: Text(
                        _sessionLine(session, widget.unit),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: PrimaryButton(label: 'Start', onPressed: _begin),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What today asks for, in one line, in the runner's own unit.
String _sessionLine(PlannedSession session, UnitSystem unit) {
  if (session.distanceMeters <= 0) return session.kind.name;
  final Distance distance = Distance.meters(session.distanceMeters);
  return '${distance.format(unit)} · ${session.kind.name}';
}
