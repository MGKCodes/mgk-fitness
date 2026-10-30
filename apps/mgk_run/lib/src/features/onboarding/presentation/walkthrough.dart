import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../domain/walkthrough_script.dart';

/// Run's tour over the real app (ADR-0050): the steps in [TourStep], one at a
/// time, ending on the button that starts a run.
///
/// **Over the app, not in front of it.** The shell is running underneath, on
/// its real tabs, and [WalkthroughOverlay] (in `mgk_ui`) veils it with a hole
/// cut round one control, the coach's line beside it. This class is the
/// sequence: which tab to show, which control to light, and when a step is
/// not there to be shown. Lift's is the same shape with a practice set on the
/// end; Run's has none (see the script).
///
/// **One overlay entry, in the root overlay.** The shell is never rebuilt to
/// make room for it.
///
/// **Nothing behind the veil can be pressed.** Every step is a statement, so
/// no hole lets a tap through: the start button is lit at the end and cannot
/// start a run.
class RunTour {
  RunTour({
    required this.overlay,
    required this.targets,
    required this.goTo,
    required this.isSignedIn,
    required this.onEnded,
    this.from = TourStep.today,
  });

  /// Where the veil goes: the root overlay, above every route.
  final OverlayState overlay;

  /// The controls the steps name, registered by the shell's screens.
  final WalkthroughTargets targets;

  /// Shows a tab. The shell's, since it owns which tab is showing.
  final void Function(TourPlace place) goTo;

  /// Whether somebody is signed in: the one line with a variant.
  final bool Function() isSignedIn;

  /// Called once, when it ends: by *Done*, *Skip* or back.
  final VoidCallback onEnded;

  /// Where it starts. The top, always, in the app; a later step for the
  /// plates, which photograph one step each.
  final TourStep from;

  final ValueNotifier<WalkthroughFrame?> _frame =
      ValueNotifier<WalkthroughFrame?>(null);

  OverlayEntry? _entry;
  TourStep? _step;

  /// Which call to [_show] is current. A step looked for over several frames
  /// is abandoned the moment another is asked for, or the tour ends.
  int _run = 0;
  bool _ended = false;

  /// Whether it is still going.
  bool get isRunning => !_ended;

  /// The step on screen, or the one being looked for.
  TourStep? get step => _step;

  /// Frames a step's control is looked for before the step is passed over.
  /// A control that is there is there on the first frame after its tab is;
  /// this is headroom, not a wait.
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
    if (current == TourStep.values.last) return _end();
    unawaited(_show(current.index + 1));
  }

  /// *Skip*, or back: ends it from wherever it is, exactly as *Done* does.
  void skip() => _end();

  /// Takes the tour down without a word: the shell going away under it.
  /// Calls nothing back.
  void dispose() {
    if (_ended) return;
    _ended = true;
    _run++;
    _entry?.remove();
    _entry = null;
    _disposeFrameLater();
  }

  bool _live(int run) => !_ended && run == _run;

  Future<void> _show(int index) async {
    final run = ++_run;
    _frame.value = null;
    if (index >= TourStep.values.length) return _end();
    final step = TourStep.values[index];
    _step = step;

    final place = step.place;
    if (place != null) goTo(place);

    final last = step == TourStep.values.last;
    final found = await _lookForSpot(step.spot, run);
    if (!_live(run)) return;
    // The way out is said even with nothing to light; any other step that
    // has nothing to point at is passed over.
    if (!found && !last) return _show(index + 1);

    _frame.value = WalkthroughFrame(
      line: step.lineFor(signedIn: isSignedIn()),
      target: found ? step.spot : null,
      next: last ? kTourDone : kTourNext,
      skip: last ? null : kTourSkip,
    );
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

  void _end() {
    if (_ended) return;
    _ended = true;
    _run++;
    _frame.value = null;
    _entry?.remove();
    _entry = null;
    goTo(TourPlace.home);
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
