import 'package:flutter/material.dart';

import '../motion/app_motion.dart';

/// The tab roots of a shell: all of them kept alive, one of them shown, and
/// the change between them drawn.
///
/// **An `IndexedStack` that does not snap.** `IndexedStack` is the right
/// container for tab roots, because every tab keeps its scroll position and
/// its loaded state while another is showing. What it cannot do is move: a
/// tab change is one frame, the whole screen replaced under the finger. That
/// reads as a cut, and on a phone a cut reads as the app being abrupt.
///
/// So the tab leaving shifts a short way toward the side it came from and
/// fades, and the tab arriving shifts in from the side it lives on and settles.
/// The direction follows the bar: a tab to the right arrives from the right.
///
/// **A short shift, not a page turn.** The whole width sliding past is what a
/// swipe between pages looks like, and these are not pages: nothing is swiped
/// and no tab is "next". [shift] logical pixels is enough to say which way.
///
/// Everything [IndexedStack] promises still holds. Each child stays in the
/// tree in the same place whatever is showing, so state survives; a child
/// that is not on screen is offstage, takes no taps, and is skipped by a
/// finder that skips offstage widgets.
///
/// With Reduce Motion on, the change is immediate.
class TabStack extends StatefulWidget {
  const TabStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = AppMotion.slow,
    this.shift = 28,
  });

  /// The child that is showing.
  final int index;

  final List<Widget> children;

  /// How long a change takes, end to end.
  final Duration duration;

  /// How far a tab travels as it arrives or leaves, in logical pixels.
  final double shift;

  @override
  State<TabStack> createState() => _TabStackState();
}

class _TabStackState extends State<TabStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _change = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: 1,
  );

  /// The tab being left, while a change is under way.
  late int _from = widget.index;

  // The tab leaving is gone by the halfway mark, and the one arriving does not
  // start until a third of the way in: for a moment neither is at full
  // strength, which is what stops two screens of text being read at once.
  static const Interval _leaving = Interval(0, 0.5, curve: AppMotion.exit);
  static const Interval _arriving = Interval(0.3, 1, curve: AppMotion.entrance);

  @override
  void didUpdateWidget(TabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _change.duration = widget.duration;
    if (oldWidget.index == widget.index) return;
    _from = oldWidget.index;
    final bool still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      _change.value = 1;
    } else {
      _change.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _change.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _change,
    builder: (context, _) {
      final bool moving = _change.value < 1;
      final int to = widget.index;
      // +1 when the tab arriving lives to the right of the one leaving.
      final double side = to > _from ? 1 : -1;
      return Stack(
        children: <Widget>[
          for (var i = 0; i < widget.children.length; i++)
            _layer(
              i,
              arriving: i == to,
              leaving: moving && i == _from && i != to,
              side: side,
            ),
        ],
      );
    },
  );

  /// One tab, wrapped the same way whatever it is doing, so its element (and
  /// everything it has loaded) is never rebuilt from nothing by a change of
  /// tab.
  Widget _layer(
    int i, {
    required bool arriving,
    required bool leaving,
    required double side,
  }) {
    var opacity = 1.0;
    var dx = 0.0;
    if (leaving) {
      final double t = _leaving.transform(_change.value);
      opacity = 1 - t;
      dx = -side * widget.shift * t;
    } else if (arriving) {
      final double t = _arriving.transform(_change.value);
      opacity = t;
      dx = side * widget.shift * (1 - t);
    }
    return Offstage(
      key: ValueKey<int>(i),
      offstage: !arriving && !leaving,
      child: IgnorePointer(
        // Only the tab that is staying takes a tap. One on its way out would
        // act on a screen the runner has already left.
        ignoring: !arriving,
        child: Transform.translate(
          offset: Offset(dx, 0),
          child: Opacity(opacity: opacity, child: widget.children[i]),
        ),
      ),
    );
  }
}
