import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../brand.dart';

/// How long the launch runs in all: the curtain, and the app settling into
/// place behind it as the curtain goes.
const Duration kLaunchDuration = Duration(milliseconds: 2200);

/// When the curtain is gone and the app takes touches again. The last quarter
/// of a second of [kLaunchDuration] is the app alone, coming to rest.
const Duration kLaunchCurtainUp = Duration(milliseconds: 1940);

/// The app's first two seconds: the icon's mark dips, drives up, and lifts
/// the app's name into place under it.
///
/// **The app used to drop straight in.** The launch window was charcoal and
/// the first frame was Track, still reading the log. Nothing said which app
/// had opened.
///
/// **It costs no time.** [child] is built and loading underneath from the
/// first frame, so the seconds this takes are seconds the app was going to
/// spend reading the log anyway. It takes no input and blocks none for longer
/// than it is on screen.
///
/// Plays once per process: a cold start. Coming back to the app from the
/// background does not rebuild this, so it does not play again. A lifter
/// reopening the app between sets is coming back, not starting, and goes
/// straight to the session.
///
/// With Reduce Motion on it is not shown at all.
///
/// **The same launch as Run's, turned through a right angle.** Run's mark
/// winds back and dashes to the right, because a run is distance; this one
/// dips and drives up, because a lift is load. The beats, their timing and
/// the curtain around them are Run's, so the two apps open alike. The curtain
/// is a copy of Run's rather than one shared widget only because sharing it
/// means editing Run from Lift's lane; if both keep it, it belongs in
/// `mgk_ui`.
class LaunchCurtain extends StatefulWidget {
  const LaunchCurtain({super.key, required this.child, this.enabled = true});

  final Widget child;

  /// False shows [child] alone. Tests and the preview harness pass false:
  /// they have no launch to dress.
  final bool enabled;

  @override
  State<LaunchCurtain> createState() => _LaunchCurtainState();
}

class _LaunchCurtainState extends State<LaunchCurtain>
    with SingleTickerProviderStateMixin {
  // Made in initState, not on first use: where the curtain never plays, the
  // first use would be dispose, which is too late to ask for a ticker.
  late final AnimationController _play;

  @override
  void initState() {
    super.initState();
    // Finished from the start, so a launch that never plays is one at rest.
    _play = AnimationController(
      vsync: this,
      duration: kLaunchDuration,
      value: 1,
    );
  }

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final bool still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!widget.enabled || still) return;
    _play.forward(from: 0);
  }

  @override
  void dispose() {
    _play.dispose();
    super.dispose();
  }

  // **One shape of tree, with or without the curtain.** Returning the child
  // bare once the animation was done would move it from "inside a transform,
  // first of a stack" to "the only thing here", and Flutter rebuilds what
  // moves: the whole app, from nothing, two seconds after it had loaded.
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _play,
    // Handed through, so the app is not rebuilt on every frame of this.
    child: widget.child,
    builder: (context, app) {
      final double t = LaunchTimeline.seconds(_play.value);
      return Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // The app arrives rather than being cut to: a touch large behind
          // the curtain, and settling as it goes.
          Transform.scale(scale: LaunchTimeline.appScale(t), child: app),
          if (t < LaunchTimeline.liftEnd)
            // Takes every touch while it is up. A tap meant for nothing must
            // not land on a button the lifter cannot see yet.
            AbsorbPointer(
              child: Opacity(
                opacity: 1 - LaunchTimeline.lift(t),
                child: ColoredBox(
                  color: AppColors.bg,
                  child: CustomPaint(
                    painter: LaunchMarkPainter(progress: _play.value),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

/// The launch's beats, in seconds from the first frame.
///
/// Run's numbers, unchanged, and in seconds rather than fractions of the whole
/// so the two apps' launches can be read side by side.
abstract final class LaunchTimeline {
  static double seconds(double progress) =>
      progress * kLaunchDuration.inMilliseconds / 1000;

  /// The mark dips, from when to when.
  static const double dipStart = 0.2;
  static const double dipEnd = 0.56;

  /// The mark drives up, and has landed.
  static const double driveEnd = 1.02;

  /// The curtain starts to lift, and is gone.
  static const double liftStart = 1.62;
  static const double liftEnd = 1.94;

  /// Arrives fast and settles.
  static const Curve out = Cubic(0.16, 1, 0.3, 1);

  /// Both ends soft: a move between two rests.
  static const Curve inOut = Cubic(0.65, 0, 0.35, 1);

  /// Leaves slowly, then goes.
  static const Curve leaving = Cubic(0.5, 0, 0.75, 0);

  /// 0 before [a], 1 after [b], eased between.
  static double seg(double t, double a, double b, [Curve curve = inOut]) =>
      curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

  /// How far the curtain has lifted, 0 to 1.
  static double lift(double t) => seg(t, liftStart, liftEnd, leaving);

  /// The app's size behind the curtain.
  static double appScale(double t) =>
      ui.lerpDouble(1.035, 1, seg(t, liftStart, liftEnd + 0.25, out))!;
}

/// Draws the launch at [progress], 0 to 1 of [kLaunchDuration].
///
/// Public so the frames can be drawn to a plate and looked at.
///
/// Three beats. The mark stands where the icon had it, then sinks and draws
/// in on itself: the dip before a lift. It drives up, and the name rises from
/// under its own baseline as if carried, while the air falls past on either
/// side. It comes to rest above its own name, with the studio's under both.
///
/// **The name is set in type, not drawn.** It is the wordmark Track's header
/// already carries, Inter at its heaviest but one, and the mark is the icon's
/// exact geometry (`tool/build_app_icons.py`, the `lift` heading). The motion
/// does the work.
///
/// **Stacked, where Run's is in a line.** Run's mark rests after its name
/// because that is the way it travels. This one travels up, so it rests above.
///
/// Everything is laid out for a phone 393 points wide and scaled to the
/// screen it is on.
class LaunchMarkPainter extends CustomPainter {
  const LaunchMarkPainter({required this.progress});

  final double progress;

  static const Color _silver = Color(0xFFC0C0C0);
  static const Color _white = Color(0xFFFFFFFF);

  // The air falling past: each line its own lane, length, moment and
  // strength. The lanes are either side of the name, never across it.
  static const List<({double x, double length, double at, double opacity})>
  _air = <({double x, double length, double at, double opacity})>[
    (x: -96, length: 54, at: 0.58, opacity: 0.22),
    (x: 104, length: 96, at: 0.63, opacity: 0.14),
    (x: -128, length: 72, at: 0.60, opacity: 0.20),
    (x: 136, length: 120, at: 0.66, opacity: 0.12),
    (x: 160, length: 40, at: 0.70, opacity: 0.18),
    (x: -156, length: 30, at: 0.72, opacity: 0.14),
  ];

  /// The mark's measures at a canvas of [m], as the icon generator has them.
  static ({double stroke, double half, double lean, double gap}) _markOf(
    double m,
  ) {
    final double w = 0.61 * m;
    return (stroke: 0.09 * m, half: 0.215 * w, lean: 0.2 * w, gap: 0.36 * w);
  }

  /// How tall the mark's ink is at a canvas of [m]: both chevrons and the
  /// round ends of their strokes.
  static double _markHeight(double m) {
    final g = _markOf(m);
    return g.gap + g.lean + g.stroke;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final double t = LaunchTimeline.seconds(progress);
    double seg(double a, double b, [Curve curve = LaunchTimeline.inOut]) =>
        LaunchTimeline.seg(t, a, b, curve);
    const Curve out = LaunchTimeline.out;

    // One phone's worth of layout, scaled to this one.
    final double k = (size.width / 393).clamp(0.8, 1.5);
    final double width = size.width;
    final double cx = width / 2;
    final double cy = size.height / 2 - 10 * k;

    // ---- the ground: one soft light from the mark's heading, which is up.
    final double glow = seg(0.4, 1.1, out);
    if (glow > 0) {
      canvas.save();
      canvas.translate(width * 0.5, size.height * 0.16);
      canvas.scale(width * 1.15, size.height * 0.62);
      canvas.drawCircle(
        Offset.zero,
        1,
        Paint()
          ..shader = ui.Gradient.radial(
            Offset.zero,
            1,
            <Color>[
              const Color(0xFF3A3A3A).withValues(alpha: 0.55 * glow),
              const Color(0x003A3A3A),
            ],
            const <double>[0, 0.62],
          ),
      );
      canvas.restore();
    }

    // What follows grows a little as the curtain lifts, about the centre.
    final double lift = LaunchTimeline.lift(t);
    canvas.save();
    final Offset centre = size.center(Offset.zero);
    canvas.translate(centre.dx, centre.dy);
    canvas.scale(ui.lerpDouble(1, 1.06, lift)!);
    canvas.translate(-centre.dx, -centre.dy);

    // ---- the lockup: the mark, a space, the word under it.
    final double fontSize = 60 * k;
    final double tracking = 3 * k;
    final TextPainter word = TextPainter(
      text: TextSpan(
        text: kAppName.toUpperCase(),
        style: TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontWeight: FontWeight.w800,
          fontSize: fontSize,
          letterSpacing: tracking,
          color: _white,
          height: 1.22,
          leadingDistribution: TextLeadingDistribution.even,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Tracking is added after every letter, the last included. Not ink.
    final double wordWidth = word.width - tracking;
    // Inter's capitals, as a share of the font size.
    final double capHeight = 0.727 * fontSize;

    const double small = 112;
    const double big = 150;
    final double markHeight = _markHeight(small * k);
    final double space = 20 * k;
    // The whole lockup, centred on the line the icon's mark stood on.
    final double top = cy - (markHeight + space + capHeight) / 2;
    final double home = top + markHeight / 2;
    final double baselineY = top + markHeight + space + capHeight;

    // ---- the three beats.
    final double dip = seg(LaunchTimeline.dipStart, LaunchTimeline.dipEnd);
    final double drive = seg(
      LaunchTimeline.dipEnd,
      LaunchTimeline.driveEnd,
      out,
    );
    final double m = ui.lerpDouble(big, small, dip)! * k;
    // As low as it goes: a little under where the icon had it.
    final double low = cy + 30 * k;
    double up(double amount) => ui.lerpDouble(low, home, amount)!;
    final double markY = drive > 0 ? up(drive) : ui.lerpDouble(cy, low, dip)!;
    // Drawn in on itself as it dips, and opening out again as it lands.
    final double spread = ui.lerpDouble(
      ui.lerpDouble(1, 0.72, dip),
      1,
      seg(LaunchTimeline.dipEnd, 0.9, out),
    )!;

    // ---- the air.
    final Paint air = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25 * k
      ..strokeCap = StrokeCap.round;
    for (final line in _air) {
      final double p = ((t - line.at) / 0.42).clamp(0.0, 1.0);
      if (p <= 0 || p >= 1) continue;
      final double y = ui.lerpDouble(
        cy - 200 * k,
        cy + 170 * k,
        out.transform(p),
      )!;
      final double fade = math.sin(math.pi * p);
      final double x = cx + line.x * k;
      canvas.drawLine(
        Offset(x, y),
        Offset(x, y - line.length * k * (0.4 + 0.6 * fade)),
        air..color = _white.withValues(alpha: line.opacity * fade),
      );
    }

    // ---- the word, rising from under its own baseline a beat behind the
    // mark. Nothing before the drive.
    final double risen = seg(
      LaunchTimeline.dipEnd + 0.06,
      LaunchTimeline.driveEnd + 0.08,
      out,
    );
    if (risen > 0) {
      final double baseline = word.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      final double left = cx - wordWidth / 2;
      final double wordTop = baselineY - baseline;
      canvas.save();
      // The floor it comes up through: just under the baseline, so the feet
      // of the letters are never cut once it has landed.
      canvas.clipRect(Rect.fromLTRB(0, wordTop, width, baselineY + 1.5 * k));
      word.paint(
        canvas,
        Offset(left, wordTop + (1 - risen) * (capHeight + 6 * k)),
      );
      canvas.restore();
    }

    // ---- the mark, and where it was a moment ago, fainter.
    final double before = up(
      seg(LaunchTimeline.dipEnd + 0.03, LaunchTimeline.driveEnd + 0.03, out),
    );
    final double speed = (up(drive) - before).abs();
    for (var ghost = 3; ghost >= 1; ghost--) {
      final double opacity = math.min(0.28, speed / (36 * k)) / ghost;
      if (opacity < 0.004) continue;
      _mark(canvas, cx, markY + speed * ghost * 0.9, m, spread, opacity);
    }
    _mark(canvas, cx, markY, m, spread, 1);

    // ---- the studio's name, under both.
    final double named = seg(1.0, 1.4, out);
    if (named > 0) {
      final double captionTracking = 4.2 * k;
      final TextPainter caption = TextPainter(
        text: TextSpan(
          text: kPlatformName.toUpperCase(),
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 10 * k,
            letterSpacing: captionTracking,
            color: AppColors.textSecondary.withValues(alpha: 0.88 * named),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      caption.paint(
        canvas,
        Offset(
          (width - (caption.width - captionTracking)) / 2,
          baselineY + 22 * k + ui.lerpDouble(6 * k, 0, named)!,
        ),
      );
    }

    canvas.restore();
  }

  /// The two chevrons, their ink centred on ([cx], [cy]), at a canvas of [m].
  /// The lower one is silver and the upper one white, as on the icon.
  void _mark(
    Canvas canvas,
    double cx,
    double cy,
    double m,
    double spread,
    double opacity,
  ) {
    final g = _markOf(m);
    final double gap = g.gap * spread;
    // The icon hangs the chevrons from the canvas centre, which leaves their
    // ink a little high. Here the ink itself is centred.
    final double base = cy + g.lean / 2;
    final Paint pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = g.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 0; i < 2; i++) {
      final double y = base + gap / 2 - i * gap;
      canvas.drawPath(
        Path()
          ..moveTo(cx - g.half, y)
          ..lineTo(cx, y - g.lean)
          ..lineTo(cx + g.half, y),
        pen..color = (i == 0 ? _silver : _white).withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(LaunchMarkPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
