import 'package:flutter/material.dart';

import '../motion/app_motion.dart';
import '../theme/app_colors.dart';

/// Fades the foot of a scrolling region while there is more below it.
///
/// **A region that scrolls has to say so where it stops.** A sheet whose
/// content runs past its fold looks, on a small phone, exactly like a sheet
/// that has finished: the last line sits on the edge above the buttons and
/// nothing suggests a drag would find more. Run's consent sheet at 320pt put
/// "Never sent" and the retention line below that edge, and nothing on screen
/// said they were there (screen board C8). The fade is the hint, and it goes
/// once the end is reached, so a region that fits is drawn exactly as before.
///
/// Wrap the scrollable itself. [color] is whatever the region sits on, so the
/// fade reads as the content running under the edge rather than as a shadow.
class ScrollEdgeFade extends StatefulWidget {
  const ScrollEdgeFade({
    super.key,
    required this.child,
    this.color = AppColors.surface,
    this.extent = 36,
  });

  final Widget child;

  /// The ground under the scrolling region.
  final Color color;

  /// How tall the fade is.
  final double extent;

  @override
  State<ScrollEdgeFade> createState() => _ScrollEdgeFadeState();
}

class _ScrollEdgeFadeState extends State<ScrollEdgeFade> {
  bool _more = false;

  bool _read(ScrollMetrics metrics) {
    // Vertical only: a horizontal strip inside the region is not the region.
    if (metrics.axis != Axis.vertical) return false;
    final more = metrics.extentAfter > 0.5;
    if (more != _more) setState(() => _more = more);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      // Sent on first layout and whenever the content or the viewport changes
      // size, so a region that fits never shows the fade.
      onNotification: (n) => _read(n.metrics),
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) => _read(n.metrics),
        child: Stack(
          children: <Widget>[
            widget.child,
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: widget.extent,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _more ? 1 : 0,
                  duration: AppMotion.fast,
                  curve: AppMotion.standard,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          widget.color.withValues(alpha: 0),
                          widget.color,
                        ],
                      ),
                    ),
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
