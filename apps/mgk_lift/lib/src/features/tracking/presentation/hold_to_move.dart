import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Makes [child] the place a movement in the session is held to be moved —
/// and folds the movement to its header **before** it lifts.
///
/// ## Why it folds first
///
/// Flutter's reorderable list measures the item being dragged once, as it
/// lifts, and scrolls itself for as long as that whole rectangle reaches past
/// the top or bottom of the screen. An open card is 300 pixels and more, so
/// one held by its name halfway down the screen already reaches past the
/// bottom: the list scrolled on its own under a thumb that had not moved, and
/// in two seconds carried the card to the end of the session. That was found
/// in a test on 29 October 2026, before any of this shipped. A card taller
/// than the screen also trips one of the list's assertions.
///
/// So a hold folds the card to its header, and the lift waits for the frame
/// that lays the fold out. The list measures the header: it scrolls when the
/// header itself reaches an edge, which is when a thumb means it to, and the
/// gap the card leaves is a header's worth, so more of the session is in view
/// to choose a place from. The screen opens the card again where it lands.
///
/// ## Otherwise, the platform's hold
///
/// The same as [ReorderableDelayedDragStartListener]: about half a second
/// still, and a finger that moves before then is whatever it would have been
/// anyway — a scroll, or a tap on what is underneath. Once the half second is
/// up the hold is this gesture's, as the platform's is: a finger that starts
/// moving while the fold is laid out is carrying the card, not scrolling.
class HoldToMove extends ReorderableDragStartListener {
  const HoldToMove({
    super.key,
    required super.index,
    required super.child,
    required this.onHeld,
    required this.onLetGo,
  });

  /// The hold has lasted: fold the movement now. The lift follows on the next
  /// frame, so the list measures what this drew.
  final VoidCallback onHeld;

  /// The finger has gone — dropped, cancelled, or never lifted at all. Only
  /// ever called after [onHeld].
  ///
  /// **A drop is not the moment to unfold.** By then the list has begun
  /// flying the card back to its place, and what it flies is this card;
  /// unfold it mid-flight and it grows over the cards around it. The screen
  /// waits for the landing.
  final VoidCallback onLetGo;

  @override
  MultiDragGestureRecognizer createRecognizer() =>
      _FoldThenLift(debugOwner: this, onHeld: onHeld, onLetGo: onLetGo);
}

class _FoldThenLift extends MultiDragGestureRecognizer {
  _FoldThenLift({
    required super.debugOwner,
    required this.onHeld,
    required this.onLetGo,
  });

  final VoidCallback onHeld;
  final VoidCallback onLetGo;

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) => _Held(
    event.position,
    event.kind,
    gestureSettings,
    onHeld: onHeld,
    onLetGo: onLetGo,
  );

  @override
  String get debugDescription => 'hold to move';
}

/// One finger on a movement, from touch to letting go.
///
/// The platform's delayed pointer state with one step put between the hold
/// and the lift: the gesture is won at the hold, as the platform's is, but the
/// drag the list starts from it waits for the frame that lays the fold out.
class _Held extends MultiDragPointerState {
  _Held(
    super.initialPosition,
    super.kind,
    super.gestureSettings, {
    required this.onHeld,
    required this.onLetGo,
  }) {
    _timer = Timer(kLongPressTimeout, _fold);
  }

  final VoidCallback onHeld;
  final VoidCallback onLetGo;

  Timer? _timer;

  /// Told the screen to fold the movement.
  bool _folded = false;

  /// The fold has been laid out, so the list may measure it.
  bool _laidOut = false;

  /// The finger has gone, and this state with it.
  bool _gone = false;

  /// The go-ahead to start the drag, held until the fold is laid out.
  GestureMultiDragStartCallback? _starter;

  void _fold() {
    _timer = null;
    _folded = true;
    onHeld();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_gone) return;
      _laidOut = true;
      final starter = _starter;
      _starter = null;
      starter?.call(initialPosition);
    });
    SchedulerBinding.instance.ensureVisualUpdate();
    // Won now, not after the frame: a finger that sets off at once is
    // carrying the card, and the list's own scroll must not take it.
    if (_starter == null) resolve(GestureDisposition.accepted);
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    if (_laidOut) {
      starter(initialPosition);
    } else {
      _starter = starter;
    }
  }

  @override
  void checkForResolutionAfterMove() {
    // Past the hold the finger is carrying the card; the distance it covers
    // while the fold is laid out is handed to the drag when it starts.
    if (_timer == null) return;
    if (pendingDelta!.distance > computeHitSlop(kind, gestureSettings)) {
      resolve(GestureDisposition.rejected);
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _gone = true;
    _timer?.cancel();
    _timer = null;
    if (_folded) onLetGo();
    super.dispose();
  }
}
