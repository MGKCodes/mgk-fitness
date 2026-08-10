import 'package:flutter/material.dart';

import 'package:mgk_ui/mgk_ui.dart';
import '../domain/training_plan.dart';

/// The whole training block as a single line: volume rising through the build,
/// dipping at each deload, falling away into the taper.
///
/// It replaces a list of one row per week. Sixteen rows of bars is a wall of
/// numbers a runner cannot act on — they are provisional by definition — and it
/// buried everything below it. The *shape* is the part that is actually decided,
/// and a shape is what a line draws.
///
/// Deliberately unlabelled. This is a picture of a plan, not a chart to read
/// values off; the week-by-week detail is one tap away for anyone who wants it.
class BlockArc extends StatefulWidget {
  const BlockArc({
    super.key,
    required this.weeks,
    this.currentIndex,
    this.height = 68,
  });

  final List<SkeletonWeek> weeks;

  /// The 1-based week the runner is in, marked on the line.
  final int? currentIndex;

  final double height;

  @override
  State<BlockArc> createState() => _BlockArcState();
}

class _BlockArcState extends State<BlockArc>
    with SingleTickerProviderStateMixin {
  /// The line draws itself left to right on first appearance, and the marker
  /// lands once the line reaches it.
  ///
  /// This is the one place in the app where motion carries meaning rather than
  /// polish: a training block *is* a progression, and watching it built left to
  /// right says that in a way a static curve cannot. It plays once — a shape
  /// that redraws every rebuild would be a fidget.
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: AppMotion.slow,
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _draw.value = 1;
      return;
    }
    _draw.forward();
  }

  @override
  void dispose() {
    _draw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: widget.height,
    width: double.infinity,
    child: AnimatedBuilder(
      animation: _draw,
      builder: (context, _) => CustomPaint(
        painter: _ArcPainter(
          weeks: widget.weeks,
          currentIndex: widget.currentIndex,
          progress: AppMotion.entrance.transform(_draw.value),
        ),
      ),
    ),
  );
}

class _ArcPainter extends CustomPainter {
  const _ArcPainter({
    required this.weeks,
    required this.progress,
    this.currentIndex,
  });

  final List<SkeletonWeek> weeks;
  final int? currentIndex;

  /// 0 to 1: how much of the line has been drawn.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (weeks.length < 2) return;

    final peak = weeks
        .map((w) => w.volumeMeters)
        .reduce((a, b) => a > b ? a : b);
    if (peak <= 0) return;

    // Room on all four sides. Horizontal matters as much as vertical: without
    // it the first and last weeks sit exactly on x=0 and x=width, and the
    // current-week marker on week one is drawn half outside the canvas.
    const inset = 7.0;
    const sideInset = 8.0;
    final usable = size.height - inset * 2;
    final span = size.width - sideInset * 2;
    final step = span / (weeks.length - 1);

    // The floor keeps the arc a *shape* rather than a graph. A block that never
    // drops below half its peak would otherwise draw as a flat line across the
    // top of the box, which says nothing about how it builds.
    const floor = 0.15;

    // A rhythm has the same volume every week, so every ratio is 1 and the arc
    // drew as a line pinned to the very top of the box with empty space under
    // it — which reads as a chart that failed to load rather than as "steady",
    // and is the exact fault the comment above describes for a different cause.
    //
    // Mid-height instead. There is no ramp to show, and a level line halfway up
    // says the true thing: this is the shape, and it does not change.
    final trough = weeks
        .map((w) => w.volumeMeters)
        .reduce((a, b) => a < b ? a : b);
    final isLevel = peak == trough;

    double heightFor(int i) {
      if (isLevel) return 0.5;
      final ratio = weeks[i].volumeMeters / peak;
      return floor + (1 - floor) * ratio;
    }

    Offset pointFor(int i) =>
        Offset(sideInset + step * i, inset + usable * (1 - heightFor(i)));

    final points = <Offset>[for (var i = 0; i < weeks.length; i++) pointFor(i)];

    // A smooth line rather than a polyline: a training block is a curve a coach
    // draws, and the corners of a polyline read as data points to be inspected.
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final midX = (a.dx + b.dx) / 2;
      line.cubicTo(midX, a.dy, midX, b.dy, b.dx, b.dy);
    }

    // Only the drawn portion of the line, measured along the path so the tip
    // travels at a constant speed rather than jumping between weeks.
    final metric = line.computeMetrics().first;
    final drawn = progress >= 1
        ? line
        : metric.extractPath(0, metric.length * progress);

    // A soft fill under the drawn line, so the shading arrives with the curve.
    final fill = Path.from(drawn)
      ..lineTo(drawn.getBounds().right, size.height)
      ..lineTo(sideInset, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            AppColors.primary.withValues(alpha: 0.28),
            AppColors.primary.withValues(alpha: 0.03),
          ],
        ).createShader(Offset.zero & size),
    );

    canvas.drawPath(
      drawn,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = AppColors.primary,
    );

    // Where the runner is. The one thing on here worth pointing at, so it is
    // the one thing marked.
    final current = currentIndex;
    if (current != null && current >= 1 && current <= weeks.length) {
      final at = points[current - 1];
      // The marker waits for the line to reach it.
      if (at.dx > drawn.getBounds().right + 0.5) return;

      canvas.drawLine(
        Offset(at.dx, at.dy + 4),
        Offset(at.dx, size.height),
        Paint()
          ..strokeWidth = 1
          ..color = AppColors.textPrimary.withValues(alpha: 0.25),
      );
      // Punched out of the fill so the dot reads on any part of the curve.
      canvas.drawCircle(at, 5, Paint()..color = AppColors.bg);
      canvas.drawCircle(at, 3.5, Paint()..color = AppColors.textPrimary);
    }
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.progress != progress ||
      old.currentIndex != currentIndex ||
      old.weeks.length != weeks.length;
}
