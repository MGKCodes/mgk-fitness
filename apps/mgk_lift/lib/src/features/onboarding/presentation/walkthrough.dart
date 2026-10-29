import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

import '../../tracking/data/in_memory_session_recorder.dart';
import '../../tracking/domain/session.dart';
import '../../tracking/presentation/active_session_screen.dart';
import '../domain/practice_session.dart';
import '../domain/walkthrough_script.dart';

/// Lift's walkthrough over the real app (ADR-0006): the steps in
/// [WalkthroughStep], one at a time, then a practice set.
///
/// **Over the app, not in front of it.** The shell is running underneath, on
/// its real tabs, and [WalkthroughOverlay] (in `mgk_ui`) veils it with a hole
/// cut round one control, the coach's line beside it. This class is the
/// sequence: which tab to show, which control to light, when a step is not
/// there to be shown, and the practice session.
///
/// **One overlay entry, in the root overlay**, inserted before anything the
/// walkthrough pushes. A navigator keeps entries it does not own above its
/// routes, so the veil stays over the practice session when that is pushed
/// under it, and the shell is never rebuilt to make room for it.
///
/// ## A step that is not there is not shown
///
/// Each step names its control ([WalkthroughSpot]), and before it is shown
/// the control is looked for, on screen, for a few frames. Not found, the
/// step is passed over: the C with the coach switched off, *Your workouts*
/// behind a button that resumes an open session instead, the rest timer when
/// the set was not ticked. The walkthrough never points at nothing.
///
/// ## The practice set is never real
///
/// It runs in the real [ActiveSessionScreen], over an [InMemorySessionRecorder]
/// seeded by [practiceSession], with everything that would make it reach the
/// lifter's training left out: no library (so no *save as a workout*), no
/// planner (so no coach), no log (so no "last time" and no new best), no rest
/// alerts (so no notification scheduled and none asked for), no remembered
/// rest lengths, no backup, nothing called when it ends. The database, the
/// backup, history, bests, the log, a plan's weights and Track's *Resume*
/// all read the real recorder, which this never touches. Ending the
/// walkthrough closes the screen and drops the session.
class LiftWalkthrough {
  LiftWalkthrough({
    required this.navigator,
    required this.overlay,
    required this.targets,
    required this.goTo,
    required this.massUnit,
    required this.isSignedIn,
    required this.isCoached,
    required this.onEnded,
    this.from = WalkthroughStep.track,
  });

  /// Where the practice session is pushed: the shell's.
  final NavigatorState navigator;

  /// Where the veil goes: the root overlay, above every route.
  final OverlayState overlay;

  /// The controls the steps name, registered by the shell and the practice
  /// session.
  final WalkthroughTargets targets;

  /// Shows a tab. The shell's, since it owns which tab is showing.
  final void Function(WalkthroughPlace place) goTo;

  /// What the practice set's weight is shown in. Asked when the practice
  /// opens, so a unit loaded since the walkthrough began is the one used.
  final MassUnit Function() massUnit;

  /// Whether somebody is signed in, and whether their swap asks the coach:
  /// the two lines with a variant ([WalkthroughStep.lineFor]).
  final bool Function() isSignedIn;
  final bool Function() isCoached;

  /// Called once, when it ends: by *Start training*, *Skip* or back.
  final VoidCallback onEnded;

  /// Where it starts. The top, always, in the app; a later step for the
  /// preview harness and the plates, which photograph one step each.
  final WalkthroughStep from;

  final ValueNotifier<WalkthroughFrame?> _frame =
      ValueNotifier<WalkthroughFrame?>(null);

  OverlayEntry? _entry;
  WalkthroughStep? _step;
  _Practice? _practice;

  /// Which call to [_show] is current. A step looked for over several frames
  /// is abandoned the moment another is asked for, or the walkthrough ends.
  int _run = 0;
  bool _ended = false;

  /// Whether it is still going.
  bool get isRunning => !_ended;

  /// The step on screen, or the one being looked for.
  WalkthroughStep? get step => _step;

  /// Frames a step's control is looked for before the step is passed over.
  /// A control that is there is there on the first frame after its tab or
  /// screen is; this is headroom, not a wait.
  static const int _lookFor = 6;

  void start() {
    if (_entry != null || _ended) return;
    final entry = OverlayEntry(
      builder: (_) => WalkthroughOverlay(
        targets: targets,
        frame: _frame,
        onNext: next,
        onSkip: skip,
      ),
    );
    _entry = entry;
    overlay.insert(entry);
    unawaited(_show(from.index));
  }

  /// The card's button: the next step, or on the last one, the end.
  void next() {
    final current = _step;
    if (_ended || current == null || _frame.value == null) return;
    if (current == WalkthroughStep.done) return _end();
    unawaited(_show(current.index + 1));
  }

  /// *Skip*, or back: ends it from wherever it is, exactly as *Start
  /// training* does.
  void skip() => _end();

  /// Takes the walkthrough down without a word: the shell going away under
  /// it. Calls nothing back.
  void dispose() {
    if (_ended) return;
    _ended = true;
    _run++;
    _entry?.remove();
    _entry = null;
    // The shell is being taken down, which may be mid-frame: the navigator
    // is not touched until the frame is over, and not at all if it has gone.
    final practice = _practice;
    _practice = null;
    practice?.recorder.onChanged = null;
    if (practice != null) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (practice.route.isActive && navigator.mounted) {
          navigator.removeRoute(practice.route);
        }
      });
    }
    _disposeFrameLater();
  }

  bool _live(int run) => !_ended && run == _run;

  Future<void> _show(int index) async {
    final run = ++_run;
    _frame.value = null;
    if (index >= WalkthroughStep.values.length) return _end();
    final step = WalkthroughStep.values[index];
    _step = step;

    await _enter(step.place);
    if (!_live(run)) return;

    final spot = step.spot;
    if (spot != null) {
      final found = await _lookForSpot(spot, run);
      if (!_live(run)) return;
      if (!found) return _show(index + 1);
    }

    final last = step == WalkthroughStep.done;
    _frame.value = WalkthroughFrame(
      line: step.lineFor(signedIn: isSignedIn(), coached: isCoached()),
      target: spot,
      interactive: step.interactive,
      next: last ? kWalkthroughStart : kWalkthroughNext,
      skip: last ? null : kWalkthroughSkip,
    );
  }

  /// Puts the app where [place] is: a tab, or the practice session.
  Future<void> _enter(WalkthroughPlace? place) async {
    switch (place) {
      case null:
        return;
      case WalkthroughPlace.practice:
        await _openPractice();
      case WalkthroughPlace.track:
      case WalkthroughPlace.plan:
      case WalkthroughPlace.profile:
        _closePractice();
        goTo(place);
    }
  }

  /// Looks for [spot] on screen, a frame at a time, and scrolls it into view
  /// when it is found under the floating bar or off the edge.
  Future<bool> _lookForSpot(Object spot, int run) async {
    for (var frame = 0; frame < _lookFor; frame++) {
      await WidgetsBinding.instance.endOfFrame;
      if (!_live(run)) return false;
      if (targets.rectOf(spot) != null) {
        await _reveal(spot);
        return _live(run) && targets.rectOf(spot) != null;
      }
    }
    return false;
  }

  /// Scrolls [spot] into the part of the screen nothing floats over, when it
  /// is not already there. A control in no scroll view is left as it is.
  Future<void> _reveal(Object spot) async {
    final context = targets.contextOf(spot);
    final rect = targets.rectOf(spot);
    if (context == null || rect == null || !context.mounted) return;
    final size = MediaQuery.sizeOf(context);
    final inset = MediaQuery.paddingOf(context);
    final clear = Rect.fromLTRB(
      0,
      inset.top,
      size.width,
      size.height - inset.bottom - MediaQuery.viewPaddingOf(context).bottom,
    );
    if (clear.contains(rect.topLeft) && clear.contains(rect.bottomRight)) {
      return;
    }
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    await Scrollable.ensureVisible(
      context,
      alignment: 0.3,
      duration: still ? Duration.zero : AppMotion.base,
      curve: AppMotion.standard,
    );
  }

  /// Opens the practice session, once, and waits for it to finish arriving
  /// so the first step in it is shown on a screen at rest.
  Future<void> _openPractice() async {
    if (_practice != null) return;
    final unit = massUnit();
    final session = practiceSession(unit, at: DateTime.now());
    final recorder = InMemorySessionRecorder(session);
    final route = MaterialPageRoute<void>(
      builder: (_) => PopScope<void>(
        // Back is Skip, here as over the shell.
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) skip();
        },
        // A route is not below the shell's scope, so the session's controls
        // are handed the same targets here.
        child: WalkthroughScope(
          targets: targets,
          child: ActiveSessionScreen(
            recorder: recorder,
            session: session,
            massUnit: unit,
            // Everything else is left out on purpose: see the class comment.
          ),
        ),
      ),
    );
    final practice = _Practice(recorder, route);
    _practice = practice;
    recorder.onChanged = _onPracticeChanged;
    unawaited(
      navigator.push(route).then((_) {
        // Popped by something other than the walkthrough: it is over.
        if (identical(_practice, practice)) {
          _practice = null;
          _end();
        }
      }),
    );
    await _arrived(route);
  }

  /// Completes when [route] has finished its entrance, or has been taken
  /// away before it could.
  static Future<void> _arrived(ModalRoute<void> route) {
    final animation = route.animation;
    if (animation == null || animation.isCompleted) return Future.value();
    final arrived = Completer<void>();
    void listen(AnimationStatus status) {
      if (status.isAnimating) return;
      animation.removeStatusListener(listen);
      if (!arrived.isCompleted) arrived.complete();
    }

    animation.addStatusListener(listen);
    return arrived.future;
  }

  /// The practice set, ticked: on to the rest it started. *Next* would have
  /// done the same; this is the lifter doing it.
  void _onPracticeChanged(Session? session) {
    if (_ended || _step != WalkthroughStep.logASet) return;
    if (_frame.value == null || session == null) return;
    if (session.completedSets == 0) return;
    unawaited(_show(WalkthroughStep.logASet.index + 1));
  }

  void _closePractice() {
    final practice = _practice;
    _practice = null;
    if (practice == null) return;
    practice.recorder.onChanged = null;
    final route = practice.route;
    if (route.isActive) {
      if (route.isCurrent) {
        navigator.pop();
      } else {
        navigator.removeRoute(route);
      }
    }
    // Nothing to write and nowhere to write it: the session goes with the
    // recorder, and the recorder with this.
    unawaited(practice.recorder.discard());
  }

  void _end() {
    if (_ended) return;
    _ended = true;
    _run++;
    _frame.value = null;
    _entry?.remove();
    _entry = null;
    _closePractice();
    goTo(WalkthroughPlace.track);
    _disposeFrameLater();
    onEnded();
  }

  /// After the overlay has let go of it, which it does in the frame after
  /// its entry is removed.
  void _disposeFrameLater() {
    SchedulerBinding.instance.addPostFrameCallback((_) => _frame.dispose());
    SchedulerBinding.instance.scheduleFrame();
  }
}

/// The practice session while it is open.
class _Practice {
  _Practice(this.recorder, this.route);

  final InMemorySessionRecorder recorder;
  final ModalRoute<void> route;
}
