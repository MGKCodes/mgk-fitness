import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// A movement as it looks while it is held and dragged to a new place: lifted
/// a little off the list — a slight scale and a shadow — and set back down on
/// the drop.
///
/// **One look for both places a lifter reorders movements**, the running
/// session and the workout editor, so the gesture learnt in one reads the same
/// in the other. It is the editor's lift as it was ("a dragged row lifts,
/// slight scale and shadow", the logging rework's Phase 5), moved here rather
/// than copied.
///
/// [gapBelow] is the space under the card that belongs to the list item — the
/// gap to the next card, which each item carries as padding. The shadow stops
/// at the card's own edge: drawn round the whole item, it hung a dark band in
/// that gap, under nothing.
///
/// Nothing here is a colour of its own. The card keeps its surface; the
/// shadow is the platform's elevation, in the black the editor already used.
Widget liftedWhileDragged(
  Widget child,
  Animation<double> animation, {
  double gapBelow = 0,
}) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, child) => Transform.scale(
      scale: 1 + 0.03 * animation.value,
      child: Stack(
        // The item's own constraints, so the card is laid out exactly as it
        // was in the list rather than loosened to its narrowest.
        fit: StackFit.passthrough,
        children: <Widget>[
          Positioned.fill(
            bottom: gapBelow,
            child: Material(
              color: Colors.transparent,
              elevation: 8 * animation.value,
              shadowColor: Colors.black,
              borderRadius: AppRadius.cardAll,
            ),
          ),
          child!,
        ],
      ),
    ),
    child: child,
  );
}
