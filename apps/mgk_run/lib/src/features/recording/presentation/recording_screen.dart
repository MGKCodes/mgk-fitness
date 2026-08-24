import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' show Geolocator;
import 'package:latlong2/latlong.dart' show LatLng;

import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../../coaching/domain/pace_model.dart';
import '../../coaching/domain/prescribed_distance.dart';
import '../../coaching/domain/session_effort.dart';
import '../../coaching/domain/training_plan.dart';
import '../../coaching/presentation/session_labels.dart';
import '../domain/live_metrics.dart';
import '../domain/route_metrics.dart';
import '../domain/run_point.dart';
import '../domain/run_recorder.dart';
import '../domain/run_split.dart';
import 'recording_readout.dart';
import 'route_map.dart';

/// The hero numeral's point size on this screen.
const double _heroSize = 96;

/// How tall the collapsed panel needs to be, in logical pixels.
///
/// **Derived from the content, not picked as a fraction of the screen.** It was
/// a fraction — 0.42 — and that is only ever correct on the one phone it was
/// tuned against: the panel's contents have a fixed intrinsic height, so a
/// fraction of a *shorter* screen is a smaller box holding the same thing. At
/// 375x667 that put the controls below the fold, and at 320x568 the pace meter
/// went with them. A runner who cannot reach Pause without scrolling has a
/// broken screen, not a cramped one.
///
/// Summed from the parts rather than written as one number so that changing
/// [_heroSize] moves it, instead of silently invalidating it.
/// The pace band and its verdict, which are only present on a planned day with
/// a time trial behind it.
const double _bandBlockHeight = AppSpacing.lg + 34 + 6 + 18;

/// How far, or how long, before the coach will hand a verdict down.
///
/// `rollingPace` is honest from 25 m — enough to *report a number*. It is
/// nowhere near enough to *issue an instruction*. Every run starts from a
/// standstill, so the first thirty-second window is an acceleration, and the
/// verdict derived from it is `PICK IT UP` on every run ever recorded —
/// including the ones that go on to be far too fast. Firing the most negative
/// reading at the moment it is least earned is how a runner learns to stop
/// believing the band.
///
/// Either trips it, whichever comes first: 400 m so a quick runner is not held
/// for three minutes, three minutes so a slow one is not held for 400 m.
const double kVerdictWarmUpMeters = 400;
const Duration kVerdictWarmUpTime = Duration(minutes: 3);

/// The effort brief, while it sits above the fold — see [_EffortBrief].
///
/// Its prose is capped at two lines up here for the same reason this whole sum
/// exists: the detent is computed, not measured, and a third line would push
/// the controls off the bottom of a small phone.
///
/// Two lines of prose and the gap above them, and nothing else. It used to
/// carry an `RPE n` label as well, which is where the missing 14 + 6 went — the
/// sum shrank with the thing it was measuring.
const double _briefBlockHeight = AppSpacing.lg + 41;

/// A problem message and, where one helps, the Settings button under it. Only
/// present when recording has actually failed — but when it is, it pushes the
/// controls down, and a detent that does not know about it strands them off
/// the bottom exactly as a fixed fraction used to.
const double _problemBlockHeight = 96 + AppSpacing.lg;

double _panelContentHeight({
  required bool hasBand,
  required bool hasProblem,
  required bool hasBrief,
}) =>
    AppSpacing.md + // top padding
    16 + // sheet handle and its gap
    12 + // DISTANCE eyebrow
    10 + // eyebrow gap
    _heroSize + // the numeral
    AppSpacing.lg + // gap
    52 + // TIME / PACE / AVG label and value
    (hasBand ? _bandBlockHeight : 0) +
    (hasBrief ? _briefBlockHeight : 0) +
    (hasProblem ? _problemBlockHeight : 0) +
    AppSpacing.xl + // gap
    48 + // the control row — two buttons, whichever pair is showing
    AppSpacing.lg; // bottom padding

/// The most of the screen the collapsed panel may take *because of the brief*.
///
/// The brief buys its height from the map, and on a short screen there is not
/// enough map to sell. At 320x568 the panel went to 0.79 with the brief up,
/// leaving a strip barely taller than the position marker — the trade is worth
/// making on a phone with room and not on one without. Nothing breaks below
/// this; the controls stay reachable either way. It simply stops being a good
/// deal.
const double kBriefMaxCollapsedFraction = 0.70;

/// Whether the effort brief can afford to sit above the fold on this screen.
bool briefFitsOn(
  double height, {
  double bottomInset = 0,
  required bool hasBand,
  required bool hasProblem,
}) {
  if (height <= 0) return false;
  final withBrief =
      _panelContentHeight(
        hasBand: hasBand,
        hasProblem: hasProblem,
        hasBrief: true,
      ) +
      bottomInset;
  return withBrief / height <= kBriefMaxCollapsedFraction;
}

/// The panel's full extent, as a fraction of the screen.
///
/// **Two resting places, not three.** A middle detent sounds generous and costs
/// the gesture its meaning: with three stops a drag lands somewhere the runner
/// did not choose, and they have to look to find out where. Two is a toggle you
/// can work without reading — the numbers, or everything.
const double _fullFraction = 0.92;

/// The collapsed detent for a screen of [height], as the fraction
/// [DraggableScrollableSheet] wants.
///
/// Clamped at the top so a very short screen does not hand the whole display to
/// the panel and leave no map at all, and at the bottom so a very tall one does
/// not strand the controls in a field of empty glass.
double collapsedFractionFor(
  double height, {
  double bottomInset = 0,
  bool hasBand = true,
  bool hasProblem = false,
  bool hasBrief = false,
}) {
  if (height <= 0) return 0.42;
  final content = _panelContentHeight(
    hasBand: hasBand,
    hasProblem: hasProblem,
    hasBrief: hasBrief,
  );
  return ((content + bottomInset) / height).clamp(0.32, 0.88);
}

/// The in-run screen: a glass panel over a live map.
///
/// **Numbers first, map second — by hierarchy rather than by area.** An earlier
/// version of this screen filled the display with the map and floated the
/// readout on it, and was reverted because the hero numeral shrank to 44pt to
/// stay out of the map's way: the one figure a runner glances down for was set
/// at the size this language uses for a summary tile. The replacement demoted
/// the map to a 132pt strip, which fixed the hierarchy by giving up the map.
///
/// This does neither. The numbers own a *surface* — the panel has a ground of
/// its own, so the hero can be larger here than it was on the strip layout, and
/// the map is free to fill the screen behind it. What made the first attempt
/// fail was that the readout had nowhere to live, not that the map was big.
///
/// The panel rests in two places: collapsed it is the figures read mid-stride,
/// opened it is the session brief, the laps and the splits, none of which
/// anybody reads while moving. Its collapsed height is derived from its own
/// content, not from a fraction of the screen — see [collapsedFractionFor].
///
/// **The map takes no gestures.** It follows the runner and is not pannable,
/// which is both the right in-run behaviour — panning mid-run loses your own
/// position, and the summary screen is where a route is explored — and the
/// thing that keeps the sheet drag unambiguous. A pannable map under a
/// draggable sheet is a gesture-arena fight, and the strip layout lost it:
/// taps on its body did nothing at all.
///
/// Driven entirely by the [RunRecorder] seam, so it renders against a fake in
/// the preview and tests, and against the real geolocator-backed recorder on
/// device. Distances and paces are formatted at the display edge; the stored
/// values stay metric.
class RecordingScreen extends StatefulWidget {
  const RecordingScreen({
    super.key,
    required this.recorder,
    this.unit = UnitSystem.metric,
    this.onFinish,
    this.onCancel,
    this.plannedSession,
    this.paces,
  });

  final RunRecorder recorder;
  final UnitSystem unit;
  final VoidCallback? onFinish;
  final VoidCallback? onCancel;

  /// What the plan prescribed today, when it prescribed anything.
  final PlannedSession? plannedSession;

  /// The runner's derived training zones. Null when they have no time trial to
  /// derive one from, and then the pace is simply a number with no verdict
  /// attached — an absent judgement rather than a guessed one.
  final TrainingPaces? paces;

  // No week here. This screen took `weekDoneMeters` and `weekTargetMeters` for
  // a THIS WEEK band below the fold; the band went (weekly load is a dashboard
  // question, not a mid-run one) and the two parameters went with it rather
  // than being left as arguments the shell computes and nothing reads.

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  final List<RunPoint> _points = <RunPoint>[];
  double _distanceM = 0;
  List<RunSplit> _splits = const <RunSplit>[];
  late RecorderStatus _status = widget.recorder.status;
  RecorderProblem? _problem;
  LatLng? _focus;

  /// Held across frames so the verdict can be sticky. See [_standingFor].
  PaceStanding _standing = PaceStanding.unknown;

  /// Laps the runner marked by hand, and where the current one started.
  ///
  /// Separate from [_splits], which are the automatic kilometre cuts. A manual
  /// lap answers a different question — "how was that hill", "how was that
  /// rep" — and a runner who presses the button has said where the boundary is
  /// more precisely than a distance rule ever could.
  final List<RunSplit> _laps = <RunSplit>[];
  double _lapAnchorMeters = 0;
  Duration _lapAnchorElapsed = Duration.zero;

  void _markLap() {
    final distance = _distanceM - _lapAnchorMeters;
    final duration = _elapsed - _lapAnchorElapsed;
    // A lap of nothing is a mistap, not a lap — and it gets no confirmation,
    // because confirming a thing that did not happen is worse than silence.
    if (distance < 1 || duration <= Duration.zero) return;
    unawaited(AppHaptics.commit());
    setState(() {
      _laps.add(
        RunSplit(
          index: _laps.length + 1,
          distanceMeters: distance,
          duration: duration,
        ),
      );
      _lapAnchorMeters = _distanceM;
      _lapAnchorElapsed = _elapsed;
    });
  }

  StreamSubscription<RunPoint>? _pointSub;
  StreamSubscription<RecorderStatus>? _statusSub;
  StreamSubscription<RecorderProblem?>? _problemSub;
  Timer? _ticker;

  /// Whole display units already felt, so a kilometre ticks once and not on
  /// every fix that lands inside it.
  int _milestonesFelt = 0;

  /// Whether the last look said the signal had gone, so the loss is announced
  /// on the edge rather than every second it stays lost.
  bool _signalWasLost = false;

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
      _feelMilestone();
    });
    _statusSub = widget.recorder.statusChanges.listen((status) {
      setState(() => _status = status);
      _syncTicker();
    });
    _problemSub = widget.recorder.problems.listen(
      (problem) => setState(() => _problem = problem),
    );
    widget.recorder.start();
    _status = widget.recorder.status;
    _problem = widget.recorder.problem;
    _syncTicker();
  }

  /// A repaint tick only while the clock is moving — elapsed itself is read
  /// from the recorder's wall clock, never accumulated here.
  void _syncTicker() {
    if (_status == RecorderStatus.recording) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        _feelSignal();
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

  Future<void> _loadFocus() async {
    try {
      final last = await Geolocator.getLastKnownPosition();
      if (last == null || !mounted) return;
      setState(() => _focus = LatLng(last.latitude, last.longitude));
    } catch (_) {
      // No cached fix, or no permission to read one. Nothing to say.
    }
  }

  Duration get _elapsed => widget.recorder.elapsed;
  bool get _recording => _status == RecorderStatus.recording;
  bool get _acquiring => _recording && _points.isEmpty && _problem == null;

  /// Fixes have stopped arriving, and nothing reported it.
  ///
  /// Distinct from [_acquiring], which is the honest opening state of a run
  /// that has not had a fix *yet*. This is a run that was being tracked and has
  /// gone quiet — a tunnel, a permission downgraded mid-run, an OS that has
  /// deprioritised the app. No stream errors, so [_problem] stays null, and
  /// without this the screen goes on saying "Recording" over a frozen distance
  /// for as long as the runner cares to look at it.
  bool get _signalLost {
    if (!_recording || _problem != null) return false;
    final since = widget.recorder.sinceLastFix;
    return since != null && since >= kStaleFixAfter;
  }

  String get _statusLabel {
    if (_problem != null) return 'Not recording';
    if (_acquiring) return 'Acquiring GPS';
    if (!_recording) return 'Paused';
    if (_signalLost) return 'No signal';
    return 'Recording';
  }

  static const double _paceFloorMeters = 100;

  /// `--:--`, with no unit — the suffix lives in the label on this layout.
  static const String _dashes = '--:--';

  /// Minutes and seconds only. The `/km` is in the column label, which is what
  /// buys the width three values need: with the suffix inside each value the
  /// row needs ~394dp and an iPhone 15 has 353dp, so it overflows and the
  /// figures collide. The label was doing nothing; now it carries the unit.
  String _bare(Pace pace) {
    final text = pace.format(widget.unit);
    final suffix = ' ${widget.unit.paceSuffix}';
    return text.endsWith(suffix)
        ? text.substring(0, text.length - suffix.length)
        : text;
  }

  String get _averagePace {
    if (_distanceM < _paceFloorMeters || _elapsed == Duration.zero) {
      return _dashes;
    }
    return _bare(Pace.from(Distance.meters(_distanceM), _elapsed));
  }

  /// The live pace, or null once the fixes stop as well as when there has not
  /// been enough movement to say.
  ///
  /// [rollingPace] windows off the newest point's own timestamp and is handed
  /// no clock, so it cannot tell a runner who has stopped from a phone that has
  /// stopped hearing satellites: it keeps returning the last honest window for
  /// as long as the screen is open. This is the half of its contract only the
  /// caller can keep, because only the caller knows what time it is.
  ///
  /// Dashed rather than greyed, which is the treatment the *average* gets in
  /// the same state. The distinction is real: an average over a run that
  /// happened is still a fact about that run, and stops being updated. A
  /// current pace over fixes that stopped arriving is not a fact about
  /// anything.
  Pace? get _current => _signalLost ? null : rollingPace(_points);

  /// Whether the run has gone far enough, or long enough, to be judged.
  ///
  /// See [kVerdictWarmUpMeters]. Note this gates the *verdict*, not the pace:
  /// the figure keeps updating from the first honest window, because reporting
  /// what somebody is doing and telling them to do something else are
  /// different claims with different burdens of proof.
  bool get _warmedUp =>
      _distanceM >= kVerdictWarmUpMeters || _elapsed >= kVerdictWarmUpTime;

  String get _currentPace {
    final pace = _current;
    return pace == null ? _dashes : _bare(pace);
  }

  /// The band today's session asks for, or null when there is no session, no
  /// time trial to derive zones from, or the session has no pace at all.
  PaceBand? get _band {
    final session = widget.plannedSession;
    final paces = widget.paces;
    if (session == null || paces == null) return null;
    // **No band on an interval session.**
    //
    // `bandFor` returns the interval band for the whole session, but an
    // interval session is not run at one pace — it alternates work and
    // recovery, and `PlannedSession` carries no rep structure to say which the
    // runner is in. Showing one band would tell somebody jogging their recovery
    // that they are failing, which is worse than showing nothing. Absent until
    // the plan knows about reps (principle 7).
    if (session.kind == SessionKind.interval) return null;
    return bandFor(session.kind, paces);
  }

  /// Whether today's band is a **ceiling** rather than a corridor.
  ///
  /// The two instructions are not worth the same. On an easy, recovery or long
  /// session, running slower than the band is the session working, not failing:
  /// nobody's aerobic base suffers from twenty seconds a kilometre, and the
  /// point of the day is time on the feet. Running *faster* defeats it
  /// entirely, so EASE OFF earns its place and PICK IT UP does not — it is a
  /// quality-session rule applied to a day that is not about pace, and it fires
  /// hardest on a tired runner at the end of a long one, which is the worst
  /// possible moment to nag somebody for being tired.
  ///
  /// On threshold, marathon pace and a time trial the pace *is* the session, so
  /// both directions are real. Intervals never get a band at all — see [_band].
  bool get _effortCapped => switch (widget.plannedSession?.kind) {
    SessionKind.easy || SessionKind.recovery || SessionKind.long => true,
    SessionKind.threshold ||
    SessionKind.marathonPace ||
    SessionKind.timeTrial => false,
    // No band on these, so the answer is never used. Spelled out rather than
    // defaulted so a new kind has to be considered here.
    SessionKind.interval ||
    SessionKind.rest ||
    SessionKind.strength ||
    null => false,
  };

  /// Where the current effort sits, with hysteresis.
  ///
  /// **Sticky on purpose.** GPS pace is noisy enough that a bare comparison
  /// flips the verdict every second or two, and a readout that alternates
  /// between "ease off" and "on target" while the runner holds one effort is an
  /// irritant they will turn off. Leaving the band needs a clear margin;
  /// returning to it does not. The same hysteresis the autopause uses, for the
  /// same reason.
  PaceStanding _standingFor(PaceBand band, Pace? current) {
    if (current == null) return PaceStanding.unknown;
    // A ceiling has no lower edge to fall off, so being under it is simply
    // being within it. Resolved here rather than in the copy so the rail, the
    // verdict and the hysteresis all agree about what state the runner is in.
    if (_effortCapped) {
      final capped = _rawStandingFor(band, current);
      return capped == PaceStanding.under ? PaceStanding.inBand : capped;
    }
    return _rawStandingFor(band, current);
  }

  PaceStanding _rawStandingFor(PaceBand band, Pace? current) {
    if (current == null) return PaceStanding.unknown;
    final now = current.secondsPerKilometer;
    final slow = band.slow.secondsPerKilometer;
    final fast = band.fast.secondsPerKilometer;
    // A margin proportional to the band, so it scales with the runner rather
    // than being a fixed number of seconds that means different things at
    // 4:00 /km and at 7:00 /km.
    final margin = (slow - fast) * 0.15;

    if (_standing == PaceStanding.inBand) {
      if (now > slow + margin) return PaceStanding.under;
      if (now < fast - margin) return PaceStanding.over;
      return PaceStanding.inBand;
    }
    if (now > slow) return PaceStanding.under;
    if (now < fast) return PaceStanding.over;
    return PaceStanding.inBand;
  }

  /// The marker's place along the rail, 0 (slow) to 1 (fast).
  ///
  /// The rail is wider than the band so that being outside it is still drawn
  /// somewhere, rather than pinned to an edge with no sense of by how much.
  double _railPosition(PaceBand band, Pace current) {
    final slow = band.slow.secondsPerKilometer;
    final fast = band.fast.secondsPerKilometer;
    final width = slow - fast;
    if (width <= 0) return 0.5;

    const inside = PaceBandMeter.defaultBandStart;
    const span = PaceBandMeter.defaultBandEnd - inside;
    final now = current.secondsPerKilometer;

    // Linear inside the band, where a second either way is the whole question.
    if (now <= slow && now >= fast) {
      return inside + span * ((slow - now) / width);
    }

    // **Compressed outside it, rather than clamped.**
    //
    // The rail used to extend one band-width-ish past each edge and then clamp,
    // which meant it delivered the opposite of what it promised: the meter's
    // own doc says the rail is wider than the band "so that being outside it is
    // still drawn somewhere, rather than pinned to an edge with no sense of by
    // how much", and a band is about thirty seconds wide, so anything much past
    // half a minute off pinned and stopped saying anything. Somebody two
    // minutes down got the same mark as somebody thirty-five seconds down.
    //
    // A band width out spends half the remaining rail, two widths three
    // quarters, and so on — approaching the end without ever arriving. The
    // marker therefore always moves when the pace moves, and the gradation
    // stays finest where the runner is closest to the band, which is where it
    // is worth having.
    final overshoot = now > slow ? (now - slow) / width : (fast - now) / width;
    final compressed = inside * (overshoot / (overshoot + 1));
    return now > slow ? inside - compressed : inside + span + compressed;
  }

  String? _verdict(PaceStanding standing) => switch (standing) {
    PaceStanding.under => 'PICK IT UP',
    PaceStanding.inBand => 'ON TARGET',
    PaceStanding.over => 'EASE OFF',
    PaceStanding.unknown => null,
  };

  /// Asks again, for the one refusal that can be asked again.
  ///
  /// `_ensureAvailable` in the geolocator source already re-requests when the
  /// permission is merely `denied`, so starting again is the whole retry. If it
  /// comes back refused — or refused permanently, which is what a second
  /// refusal becomes on Android and what iOS reports immediately — the recorder
  /// emits the new problem and this panel redraws itself into the state that
  /// offers Settings instead. Nothing here needs to know which platform it is
  /// on.
  Future<void> _askAgain() => widget.recorder.start();

  /// A kilometre — or a mile — turning over.
  ///
  /// **One of only two haptics on this screen the runner did not ask for**, and
  /// it is the case [AppHaptics.milestone] exists for: somebody mid-stride
  /// cannot read a screen, and the distance ticking past a round number is the
  /// thing they would look down for if they could.
  ///
  /// Counted off the display unit rather than off `_splits`, for two reasons.
  /// `splitsFor` includes a trailing *partial* split, so its length grows the
  /// moment a new kilometre starts rather than when one finishes. And a runner
  /// in miles should feel a mile, not a kilometre they never asked to be
  /// measured in.
  void _feelMilestone() {
    if (!_recording) return;
    final whole = Distance.meters(
      _distanceM,
    ).inDisplayUnit(widget.unit).floor();
    if (whole <= _milestonesFelt) return;
    _milestonesFelt = whole;
    unawaited(AppHaptics.milestone());
  }

  /// The signal going, felt on the edge.
  ///
  /// The other unbidden one, and it earns the exception the same way: the run
  /// carries on looking like a run — the clock still moves — while the distance
  /// quietly stops growing. A runner who cannot look would otherwise find out
  /// at the end. Fired once as it goes and once as it returns, never every
  /// second it stays gone.
  void _feelSignal() {
    final lost = _signalLost;
    if (lost == _signalWasLost) return;
    _signalWasLost = lost;
    unawaited(lost ? AppHaptics.problem() : AppHaptics.selection());
  }

  Future<void> _togglePause() {
    // A state the runner chose, and one they often choose without looking —
    // at a crossing, mid-sentence. The tick is how they know it took.
    unawaited(AppHaptics.selection());
    return _recording ? widget.recorder.pause() : widget.recorder.resume();
  }

  Future<void> _finish() async {
    unawaited(AppHaptics.commit());
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
          AppTextButton(
            label: 'Keep running',
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          AppTextButton(
            label: 'Discard',
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          ),
        ],
      ),
    );
    if (discard != true) return;
    await widget.recorder.discard();
    if (mounted) widget.onCancel?.call();
  }

  @override
  Widget build(BuildContext context) {
    final band = _band;
    final current = _current;
    // Unknown until warmed up, which reads as FINDING YOUR PACE rather than as
    // an instruction — and takes the rail's marker with it, since
    // [PaceBandMeter] draws no marker on an unknown standing. That is the
    // right call here and not just an inherited one: during the warm-up the
    // rolling pace is an acceleration off a standstill, so a marker pinned to
    // the slow end would say "you are slow" exactly as loudly as the words
    // did. The rail stays, showing the shape of what is being asked for
    // without yet placing the runner inside it.
    if (band != null) {
      _standing = _warmedUp
          ? _standingFor(band, current)
          : PaceStanding.unknown;
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          // The brief rides above the fold only while the verdict is held.
          // It is the answer to "what am I doing", which is the question of
          // the first few minutes — and once the band starts speaking, the
          // panel gives the height back and the map takes it, by which time
          // the route has a shape worth the space.
          final showBrief =
              !_warmedUp &&
              widget.plannedSession != null &&
              briefFitsOn(
                height,
                bottomInset: MediaQuery.paddingOf(context).bottom,
                hasBand: band != null && _problem == null,
                hasProblem: _problem != null,
              );
          final collapsed = collapsedFractionFor(
            height,
            bottomInset: MediaQuery.paddingOf(context).bottom,
            // No band while recording has failed. The panel is already saying
            // why there is nothing; a pace rail underneath is a second and
            // contradictory answer to the same question — the reasoning the
            // map already uses for its emptyLabel.
            hasBand: band != null && _problem == null,
            hasProblem: _problem != null,
            hasBrief: showBrief,
          );
          // **The map is a full screen tall, hung above the fold.**
          //
          // The camera centres on the runner, so with the map filling the
          // Scaffold the position dot lands at the middle of the *screen* —
          // which is behind the panel. Shifting the whole map up by the panel's
          // half-height puts the dot in the middle of the part you can actually
          // see, without lying to the map about where its centre is.
          final mapTop = ((1 - collapsed) / 2 - 0.5) * height;

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Positioned(
                top: mapTop,
                left: 0,
                right: 0,
                height: height,
                // Takes no gestures at all — see the class doc.
                child: IgnorePointer(
                  child: RouteMap(
                    points: _points,
                    focus: _focus,
                    interactive: false,
                    showPosition: true,
                    followZoom: 16,
                    // Silent when recording has failed. The panel has just said
                    // why there is nothing to draw; a map claiming to be
                    // looking for you underneath it is a second, contradictory
                    // answer to the same question.
                    emptyLabel: _problem == null ? 'Finding you' : null,
                  ),
                ),
              ),

              // Positioned, not a bare Stack child: `StackFit.expand` stretches
              // an unpositioned child to fill, and a Row inside one centres its
              // contents vertically — which put the status pill in the middle
              // of the map instead of at the top of it.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: _TopStrip(
                    label: _statusLabel,
                    // The pulse is the screen's claim that something is
                    // arriving. It has to stop when nothing is, or it becomes
                    // the loudest part of the lie.
                    pulsing: _recording && !_signalLost,
                    signal: gpsSignalFor(
                      widget.recorder.lastFix,
                      sinceFix: widget.recorder.sinceLastFix,
                    ),
                    onCancel: widget.onCancel == null ? null : _cancel,
                  ),
                ),
              ),

              _Panel(
                collapsedFraction: collapsed,
                distanceM: _distanceM,
                elapsed: _elapsed,
                unit: widget.unit,
                currentPace: _currentPace,
                averagePace: _averagePace,
                // While the signal is gone the average is elapsed time divided
                // by a distance that has stopped growing, so it drifts slower
                // every second and keeps looking like a measurement. Greyed to
                // say it is no longer being computed from anything.
                averageStale: _signalLost,
                dashes: _dashes,
                band: band,
                standing: _standing,
                railPosition: band == null || current == null
                    ? 0.5
                    : _railPosition(band, current),
                // No slow label when the band is a ceiling: naming a lower
                // edge implies falling below it means something, and on these
                // sessions it does not. The fast edge is the whole instruction.
                bandSlowLabel: band == null || _effortCapped
                    ? null
                    : _bare(band.slow),
                bandFastLabel: band == null ? null : _bare(band.fast),
                verdict: _verdict(_standing),
                effortCapped: _effortCapped,
                showBrief: showBrief,
                splits: _splits,
                session: widget.plannedSession,
                climbMeters: climbMeters(_points),
                laps: _laps,
                problem: _problem,
                onAskAgain: _askAgain,
                recording: _recording,
                onLap: _markLap,
                onTogglePause: _togglePause,
                onFinish: _finish,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Status, signal and the way out, floating over the map.
class _TopStrip extends StatelessWidget {
  const _TopStrip({
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.xs, 20, 0),
      child: Row(
        children: <Widget>[
          // Everything on this strip sits on a scrim, not just the status pill.
          // The pill had one and the close button and signal bars did not,
          // which is only invisible while the basemap happens to be dark: over
          // a pale stretch — or the flat white tiles a failed provider returns
          // — the way out of the screen disappears and the status stays.
          SizedBox(
            width: 44,
            child: onCancel == null
                ? null
                : _Scrim(
                    circular: true,
                    child: AppIconButton(
                      icon: Icons.close,
                      tooltip: 'Cancel run',
                      onPressed: onCancel,
                      color: AppColors.textPrimary,
                    ),
                  ),
          ),
          Expanded(
            child: Center(
              // A pill, not bare text: over a live basemap there is no
              // guaranteed contrast behind it, and the status is the one thing
              // that has to stay readable whatever the map is doing.
              child: _Scrim(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 6,
                ),
                // Scaled down rather than clipped or truncated. The strip
                // reserves 44pt each side for the close button and the signal
                // bars, so on a 320pt screen the pill gets about 204pt — and
                // "Acquiring GPS", the longest status and the one shown in the
                // first seconds of every run, needs about 214pt. A status that
                // reads "Acquiring…" is worse than one set a point smaller.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Pulse(
                        active: pulsing,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.textPrimary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: theme.textTheme.labelMedium?.copyWith(
                          letterSpacing: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: Align(
              alignment: Alignment.centerRight,
              child: _Scrim(child: GpsSignalBars(signal: signal)),
            ),
          ),
        ],
      ),
    );
  }
}

/// The readout, as a glass sheet that drags up.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.collapsedFraction,
    required this.distanceM,
    required this.elapsed,
    required this.unit,
    required this.currentPace,
    required this.averagePace,
    required this.averageStale,
    required this.dashes,
    required this.band,
    required this.standing,
    required this.railPosition,
    required this.bandSlowLabel,
    required this.bandFastLabel,
    required this.verdict,
    required this.effortCapped,
    required this.showBrief,
    required this.splits,
    required this.session,
    required this.climbMeters,
    required this.laps,
    required this.problem,
    required this.onAskAgain,
    required this.recording,
    required this.onLap,
    required this.onTogglePause,
    required this.onFinish,
  });

  final double collapsedFraction;
  final double distanceM;
  final Duration elapsed;
  final UnitSystem unit;
  final String currentPace;
  final String averagePace;
  final bool averageStale;
  final String dashes;
  final PaceBand? band;
  final PaceStanding standing;
  final double railPosition;
  final String? bandSlowLabel;
  final String? bandFastLabel;
  final String? verdict;

  /// Whether the band is a ceiling rather than a corridor, which changes what
  /// the meter lights: everything up to the fast edge, rather than a segment
  /// with a lower bound the session does not have.
  final bool effortCapped;

  /// Whether the effort brief sits in the collapsed panel rather than below
  /// the fold. Must agree with the `hasBrief` the detent was computed with, or
  /// the panel is taller than the height reserved for it.
  final bool showBrief;
  final List<RunSplit> splits;
  final PlannedSession? session;
  final double? climbMeters;
  final List<RunSplit> laps;
  final RecorderProblem? problem;

  /// Re-requests location. Only reachable from the refusal that can be
  /// re-requested; see [_ProblemLine].
  final Future<void> Function() onAskAgain;
  final bool recording;
  final VoidCallback onLap;
  final Future<void> Function() onTogglePause;
  final Future<void> Function() onFinish;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: collapsedFraction,
      minChildSize: collapsedFraction,
      maxChildSize: _fullFraction,
      snap: true,
      // No intermediate snap: the sheet is a toggle, not a dial.
      snapSizes: <double>[collapsedFraction, _fullFraction],
      builder: (context, controller) => GlassSurface(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
        padding: EdgeInsets.zero,
        // The panel sits flush against the bottom of the screen, so a sheen
        // across its top edge is the only thing giving it a lit direction.
        child: ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.md,
            AppSpacing.xl,
            AppSpacing.lg,
          ),
          children: <Widget>[
            const SheetHandle(),

            if (problem != null) ...<Widget>[
              _ProblemLine(problem: problem!, onAskAgain: onAskAgain),
              const SizedBox(height: AppSpacing.lg),
            ],

            // The one number the screen is for, unchallenged.
            //
            // `animate: false` because this figure is *live*. CountUp tweens
            // over 420ms, which is right for a summary appearing and wrong for
            // a distance ticking up: the number on screen is never the number,
            // and at the start of a run it disagrees visibly with the readouts
            // beside it — a 0.01 km hero next to a rolling pace that cannot
            // exist under 25 m of movement.
            //
            // `w300` rather than the default hairline, and tracking eased from
            // -2 to -1. Picked off a side-by-side plate (`?screen=hero-weights`,
            // w100 to w400) as the lightest cut that still holds when the screen
            // is read at arm's length while moving: below w300 the figure washes
            // out, above it the numeral stops looking designed and starts
            // looking like a default. The supporting row below — bold at w600 —
            // had also out-shouted a figure three times its size, so weight was
            // what inverted the hierarchy, not scale.
            //
            // The decimal point is a separate fix and not a matter of weight at
            // all: see HeroNumeral._spans, which spares separators the tabular
            // digit cell that made `0.45` read as two numbers.
            HeroNumeral(
              label: 'DISTANCE',
              value: Distance.meters(distanceM).inDisplayUnit(unit),
              unit: unit.distanceSuffix,
              size: _heroSize,
              weight: FontWeight.w300,
              letterSpacing: -1,
              animate: false,
            ),
            const SizedBox(height: AppSpacing.lg),

            // Three values, and the unit lives in the label so they fit.
            //
            // `w400` rather than the scale's `w600`: these support the hero,
            // and a bold supporting row is what made a 96pt figure read as the
            // quieter thing. `shrinkToFit` because elapsed time is the one
            // value here with no upper bound — crossing an hour adds two
            // characters, and a `Text` in a tight `Expanded` clips silently.
            Row(
              children: <Widget>[
                Expanded(
                  child: StatBlock(
                    label: 'TIME',
                    value: elapsed.hoursMinutesSeconds,
                    size: StatSize.hero,
                    align: CrossAxisAlignment.center,
                    valueWeight: FontWeight.w400,
                    shrinkToFit: true,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _PaceStat(
                    label: 'PACE ${unit.paceSuffix}',
                    value: currentPace,
                    absent: currentPace == dashes,
                  ),
                ),
                // On a planned session the third column is what is *left*,
                // not what has averaged.
                //
                // Average pace is the only figure on this row a runner cannot
                // act on: it reports how the run has gone, which is the
                // summary screen's job and told better there, and for the
                // opening minutes it reserves a third of the row for `--:--`.
                // What is left answers the question the pace band provokes —
                // hold this, and for how much longer — and it has a value from
                // the first metre. Without a plan there is no distance to
                // count down to, so the average keeps the slot.
                const SizedBox(width: AppSpacing.sm),
                // Without a plan there is nothing to count down to, so the
                // average keeps the slot.
                //
                // Dropping to two columns was tried and reverted. The empty
                // `--:--` that prompted it lasts under a minute — the average
                // appears at [_paceFloorMeters], 100 m — and it is already the
                // quietest thing on the row. Removing a runner's only summary
                // figure for the whole of every unplanned run, to save forty
                // seconds of a dash that is deliberately faint, is a worse
                // screen than the one it fixes.
                Expanded(
                  child: session == null
                      ? _PaceStat(
                          label: 'AVG ${unit.paceSuffix}',
                          value: averagePace,
                          absent: averagePace == dashes || averageStale,
                        )
                      : Builder(
                          builder: (context) {
                            // Label and figure from one call, so they cannot
                            // disagree about which side of the prescription the
                            // runner is on — a `TO GO` heading over a count
                            // going back up is the exact failure this column
                            // already had once.
                            final left = _remaining(session!, distanceM, unit);
                            return StatBlock(
                              label: left.label,
                              value: left.value,
                              size: StatSize.hero,
                              align: CrossAxisAlignment.center,
                              valueWeight: FontWeight.w400,
                              shrinkToFit: true,
                            );
                          },
                        ),
                ),
              ],
            ),

            // The coach's verdict: the band the plan asked for, and where the
            // runner is inside it. Deterministic — derived from the profile's
            // time trial in Dart, never from a model, and absent entirely when
            // there is no plan or no time trial to derive it from.
            // Suppressed while recording has failed, and the two flags have
            // to agree: `collapsedFractionFor` is told the same thing, or the
            // detent reserves height for a block that is not drawn.
            //
            // The screen has just said in plain English that nothing is being
            // tracked. Rendering FINDING YOUR PACE under that claims to be
            // looking for a pace on a run that never started — the same lie as
            // a confident figure over fixes that stopped arriving, except this
            // one contradicts a sentence two lines above it.
            if (band != null && problem == null) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              // The band's edges are written under the ends of the rail rather
              // than as a range beside the verdict. As a range they said what
              // the target was; on the rail they say which way is which, which
              // is the only thing that makes the marker's position mean
              // anything. It also stops an instruction and a reference figure
              // sharing one line at equal weight.
              PaceBandMeter(
                standing: standing,
                position: railPosition,
                slowLabel: bandSlowLabel,
                fastLabel: bandFastLabel,
                // Uppercased to sit with the other labels on this panel; the
                // meter appends it to each pace and adds the direction words
                // itself, so the caller hands over bare figures.
                unitSuffix: unit.paceSuffix.toUpperCase(),
                // Lit from the rail's start on a capped session, so the lit
                // region means "acceptable" in both cases rather than meaning
                // "the band" in one and something narrower in the other.
                bandStart: effortCapped ? 0 : PaceBandMeter.defaultBandStart,
              ),
              const SizedBox(height: 6),
              SectionLabel(
                verdict ?? 'FINDING YOUR PACE',
                emphasis: LabelEmphasis.stat,
              ),
            ],

            // What the session is for, while the band is still holding its
            // tongue. The two are deliberately the same threshold: the screen
            // either tells you what to do, or tells you what you are here to
            // do, and never neither.
            if (showBrief && session != null) ...<Widget>[
              const SizedBox(height: AppSpacing.lg),
              _EffortBrief(effort: effortFor(session!.kind), maxLines: 2),
            ],

            const SizedBox(height: AppSpacing.xl),
            // **Finishing is two acts, and only the first is on this row while
            // the runner is running.**
            //
            // Lap, Pause and Finish used to sit side by side with Finish as the
            // filled one — the loudest control on the screen, the one a thumb
            // finds without looking, and the only one of the three that cannot
            // be undone. An hour of effort was one mistap from over, and the
            // mistap was the *easy* target. Nothing about that is fixable by
            // adding a confirmation dialog to it: the answer is that a run
            // cannot end from the running state at all.
            //
            // So: Pause and Lap while moving, Resume and Finish once stopped.
            // Two buttons either way, so the row keeps one height and the
            // collapsed detent's sum stays true — and the filled one is always
            // the reversible one, because that is the button being aimed at.
            Row(
              children: <Widget>[
                if (recording) ...<Widget>[
                  // Lap is on the row rather than below the fold: it is the one
                  // control that is useless unless it is under the thumb at the
                  // moment the runner crests the hill. It goes when paused,
                  // where there is no lap being run to cut.
                  Expanded(
                    child: _ControlButton(label: 'Lap', onPressed: onLap),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _ControlButton(
                      label: 'Pause',
                      filled: true,
                      onPressed: onTogglePause,
                    ),
                  ),
                ] else ...<Widget>[
                  // Resume is filled and Finish is not, which inverts the old
                  // row on purpose: a runner who paused at a crossing is far
                  // more likely to be carrying on than stopping, and the button
                  // that ends the run should be the one they have to look for.
                  Expanded(
                    child: _ControlButton(
                      label: 'Resume',
                      filled: true,
                      onPressed: onTogglePause,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _ControlButton(label: 'Finish', onPressed: onFinish),
                  ),
                ],
              ],
            ),

            // --- below the fold ---------------------------------------------
            //
            // Enough to keep "TODAY" off the collapsed edge, and no more.
            //
            // It was 96, back when the collapsed height was a guessed fraction
            // and the gap had to absorb the error. Now that the detent is
            // derived from this content the edge lands just past the controls,
            // so the gap only has to be a section break — and a 96pt one read
            // as a hole once the sheet was open, which is the state it is
            // actually looked at in.
            const SizedBox(height: AppSpacing.xxl + AppSpacing.sm),

            if (session != null) ...<Widget>[
              TargetBand(
                title: _sessionTitle(session!),
                unit: unit,
                doneMeters: distanceM,
                targetMeters: session!.distanceMeters,
              ),
              // What the session is *for*, and how it should feel from the
              // inside. This is the half of the coach that survives having no
              // network: `effortFor` is a pure function over the session kind,
              // so it is here on a run in a tunnel, and it answers the question
              // the band above provokes — the meter says ease off, and this
              // says what easy is supposed to feel like.
              //
              // Uncapped down here, and absent entirely while it is above the
              // fold: the same paragraph twice on one sheet reads as a bug.
              if (!showBrief) ...<Widget>[
                const SizedBox(height: AppSpacing.lg),
                _EffortBrief(effort: effortFor(session!.kind)),
              ],
            ],

            if (climbMeters != null) ...<Widget>[
              const SizedBox(height: AppSpacing.xxl),
              // One label, not two: a CLIMB heading over an ASCENT stat spends
              // a line of type saying the same word twice.
              StatBlock(
                label: 'CLIMB',
                value: '${climbMeters!.round()} m',
                size: StatSize.standard,
              ),
            ],

            // No weekly load here any more.
            //
            // A THIS WEEK band carried "including this run" against the week's
            // target, on the argument that a plan is about a block rather than
            // a run. True, and it is a dashboard's argument: nobody eight
            // kilometres into a Sunday long run needs to be told what Thursday
            // looks like, and it was drawn on the one screen where every pixel
            // is either the run in front of them or noise. Home is where the
            // week is answered.
            if (laps.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.xxl),
              const SectionLabel('LAPS'),
              const SizedBox(height: AppSpacing.md),
              SplitList(splits: laps, unit: unit, newestFirst: true),
            ],

            if (splits.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppSpacing.xxl),
              const SectionLabel('SPLITS'),
              const SizedBox(height: AppSpacing.md),
              SplitList(splits: splits, unit: unit),
            ],
          ],
        ),
      ),
    );
  }
}

/// One of the in-run controls.
///
/// **The label never wraps**, and this survives the row going from three
/// buttons to two. Three across a 320pt screen left about 88pt each once
/// padding was taken out, and the default button padding pushed "Pause" and
/// "Finish" onto two lines — a control that reads `Finis` over `h` looks broken
/// in the exact moment a runner is reaching for it. Two buttons have room to
/// spare, but the guard costs nothing and the row has been three before:
/// tighter padding, a single line, and scale-down as the last resort.
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.label,
    required this.onPressed,
    this.filled = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final child = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(label, maxLines: 1, softWrap: false),
    );
    final padding = const EdgeInsets.symmetric(horizontal: AppSpacing.sm);

    return filled
        ? FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(padding: padding),
            child: child,
          )
        : OutlinedButton(
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(padding: padding),
            child: child,
          );
  }
}

/// A dark wash behind anything that has to stay readable over a live map.
///
/// The map is somebody else's imagery and its brightness is not ours to
/// predict, so every control floating on it carries its own ground.
class _Scrim extends StatelessWidget {
  const _Scrim({
    required this.child,
    this.padding = const EdgeInsets.all(4),
    this.circular = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.bg.withValues(alpha: 0.72),
        borderRadius: circular
            ? BorderRadius.circular(999)
            : BorderRadius.circular(AppRadius.chip),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// A pace column, quieter still when there is no pace to show.
///
/// An absent value is drawn a step smaller as well as a step greyer. Muting
/// only the colour left `--:--` occupying a full-size column at full weight —
/// as much of the eye as a real figure, for information that does not exist.
class _PaceStat extends StatelessWidget {
  const _PaceStat({
    required this.label,
    required this.value,
    required this.absent,
  });

  final String label;
  final String value;
  final bool absent;

  @override
  Widget build(BuildContext context) {
    return StatBlock(
      label: label,
      value: value,
      size: absent ? StatSize.large : StatSize.hero,
      align: CrossAxisAlignment.center,
      valueWeight: absent ? FontWeight.w300 : FontWeight.w400,
      valueColor: absent ? AppColors.textTertiary : null,
      shrinkToFit: true,
    );
  }
}

/// The session's effort, in the runner's terms rather than the watch's.
///
/// Deterministic and offline: [effortFor] is a switch over the session kind, so
/// this is never a model call and never fails. The RPE is the scale runners are
/// actually taught — a percentage of pace is not a unit of anything, since pace
/// and effort are not proportional.
class _EffortBrief extends StatelessWidget {
  const _EffortBrief({required this.effort, this.maxLines});

  final SessionEffort effort;

  /// Capped when the brief sits above the fold, where the collapsed detent is
  /// a computed sum and an unexpected third line would push Finish off the
  /// bottom of a small phone. Uncapped below it, where the sheet scrolls.
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // **No RPE here, and no effort label either.**
        //
        // The label went first: it sat under the session title and repeated it
        // — "Easy run" followed by "EASY" — two lines one word apart saying the
        // same thing. `RPE 3` replaced it and lasted until the first real run,
        // where it turned out to be the same mistake one level down. A number
        // on a ten-point scale is a thing to convert before it is a thing to
        // act on, and nobody eight kilometres in is doing arithmetic about how
        // hard this is meant to feel. The sentence below already says it in
        // words, which is the form that survives being read at a glance while
        // moving.
        //
        // It is not gone from the app — `SessionEffort.rpe` is the scale
        // runners are taught, and it belongs on a session brief, read sitting
        // down, before the run.
        Text(
          effort.feel,
          maxLines: maxLines,
          overflow: maxLines == null ? null : TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

/// The third column on a planned day: what is left of today's session, or how
/// far past it the runner has gone.
///
/// **Counted against what the runner was told, not against what is stored.**
/// The stored number is metric and on a whole-kilometre grid; a miles runner
/// reads "4 mi" on Plan, which is 6,437 m, and a countdown against the stored
/// 7,000 m opened at 4.35 under a heading that said 4. Two numbers for one
/// session, and the one on the screen they are holding mid-run is the wrong
/// one. [prescribedMeters] is exactly this conversion and `fulfils` has always
/// judged the session by it — see `prescribed_distance.dart`, ADR-0011.
///
/// **And it goes past zero.** It used to clamp, which meant the column froze at
/// `0.00` under a label still reading TO GO: a prescription rendered as a meter
/// that fills and then stops, so running further read as either done or as
/// nothing at all. A prescription is a suggestion, never a floor and never a
/// ceiling (ADR-0011), and a runner who keeps going has made a decision rather
/// than overrun a target. So the label changes and the figure counts up again.
({String label, String value}) _remaining(
  PlannedSession session,
  double doneM,
  UnitSystem unit,
) {
  final prescribed = prescribedMeters(session.distanceMeters, unit);
  final remaining = prescribed - doneM;
  final past = remaining < 0;
  return (
    label: '${past ? 'PAST' : 'TO GO'} ${unit.distanceSuffix}',
    value: Distance.meters(
      remaining.abs(),
    ).inDisplayUnit(unit).toStringAsFixed(2),
  );
}

/// What today's session is called — the runner's own word for it when they have
/// one, the kind's name otherwise. Never the bare weekday: "Today" under a
/// section label already reading TODAY says nothing twice.
/// What the session running right now is called.
///
/// This was a private fourth copy of the naming table, and it had already
/// drifted: it said "Marathon pace" and "Threshold" where every other surface
/// now says "Marathon pace run" and "Threshold run", so the same session had
/// two names depending on whether the runner was looking at the plan or doing
/// it. That is the exact failure [sessionName] exists to prevent, reintroduced
/// by a copy made before it did.
///
/// No time-of-day prefix, even though this is the one surface that certainly
/// knows the hour. The runner is *in* the run; telling them it is the afternoon
/// is a fact they are currently standing in.
String _sessionTitle(PlannedSession session) => sessionName(session);

/// A problem, stated on the panel rather than as a banner over the map.
class _ProblemLine extends StatelessWidget {
  const _ProblemLine({required this.problem, required this.onAskAgain});

  final RecorderProblem problem;
  final Future<void> Function() onAskAgain;

  /// The states differ in remedy, so they differ in copy. Offering "Open
  /// Settings" for a switched-off Location Services toggle sends people to a
  /// screen that cannot fix it.
  ///
  /// The device-settings path is per-platform, and has to be: it read
  /// "Settings → Privacy & Security → Location Services" on every
  /// platform, which is Apple's path and simply wrong on Android. Harmless
  /// while there was one platform, a plain defect since ADR-0021 — and the kind
  /// that hides in copy rather than in code.
  String get _message => switch (problem) {
    RecorderProblem.locationServicesOff =>
      'Location Services are off, so this run cannot be tracked. '
          'Turn them on in $_locationServicesPath.',
    RecorderProblem.permissionDenied =>
      'Run needs your location to record a route. Nothing is being tracked '
          'until you allow it.',
    RecorderProblem.permissionDeniedForever =>
      'Location is turned off for Run, so there is nothing to record. '
          'You can change it in Settings.',
    // Not "recording has paused": `_onSourceError` sets a problem and never
    // touches the status, so the run is still recording and the clock is still
    // running — and Pause means something specific two controls below this.
    RecorderProblem.locationFailed =>
      'Your location stopped arriving, so nothing is being added to this run. '
          'It usually clears on its own outdoors.',
  };

  /// Where the device's own location switch lives, in that platform's words.
  static String get _locationServicesPath => Platform.isAndroid
      ? 'Settings → Location'
      : 'Settings → Privacy & Security → Location Services';

  /// **The two refusals are not the same refusal.**
  ///
  /// `RecorderProblem` draws the distinction on purpose — one "can be asked for
  /// again", the other says "re-asking does nothing, Settings only" — and this
  /// widget used to collapse it, sending both to `openAppSettings`. That is the
  /// wrong remedy for the re-askable one and much the worse path: leave the
  /// app, find Run in a list, find Location, change it, come back, start the
  /// run again. Against one tap that re-shows the prompt they just dismissed.
  ///
  /// So: ask again where asking works, Settings where it does not.
  bool get _offersAskAgain => problem == RecorderProblem.permissionDenied;

  /// Only where Settings can actually change the outcome. A denied read is a
  /// designed-for outcome, not an error state — and Settings cannot reach the
  /// device-wide Location Services switch at all, which is why that state gets
  /// a written path instead of a button.
  bool get _offersSettings =>
      problem == RecorderProblem.permissionDeniedForever;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          _message,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        if (_offersAskAgain)
          Align(
            alignment: Alignment.centerLeft,
            child: AppTextButton(
              label: 'Allow location',
              onPressed: onAskAgain,
            ),
          ),
        if (_offersSettings)
          Align(
            alignment: Alignment.centerLeft,
            child: AppTextButton(
              label: 'Open Settings',
              onPressed: Geolocator.openAppSettings,
            ),
          ),
      ],
    );
  }
}
