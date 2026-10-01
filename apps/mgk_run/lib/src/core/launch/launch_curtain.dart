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

/// The app's first two seconds: the icon's mark winds back, goes, and leaves
/// the app's name behind it.
///
/// **The app used to drop straight in.** The launch screen was a blank ground
/// and the first frame was Home, half loaded. Nothing said which app had
/// opened, and the first thing a runner saw was a screen still filling in.
///
/// **It costs no time.** [child] is built and loading underneath from the
/// first frame, so the seconds this takes are seconds the app was going to
/// spend reading the log anyway. It takes no input and blocks none for longer
/// than it is on screen.
///
/// Plays once per process: a cold start. Coming back to the app from the
/// background does not rebuild this, so it does not play again.
///
/// With Reduce Motion on it is not shown at all.
///
/// The design is "Slipstream", chosen on 1 October 2026 from four drawn in
/// Remotion (`apps/mgk_run/design/launch-films/`). [LaunchMarkPainter] is that
/// film rebuilt, beat for beat.
class LaunchCurtain extends StatefulWidget {
  const LaunchCurtain({super.key, required this.child, this.enabled = true});

  final Widget child;

  /// False shows [child] alone. Tests and the preview harness pass false:
  /// they have no launch to dress.
  final bool enabled;

  /// Whether the launch is over, as seen from under it: true once the curtain
  /// is gone and the app has come to rest, and true anywhere there is no
  /// curtain at all.
  ///
  /// **For anything that plays once and wants to be seen.** Home's coach says
  /// its line when the shell loads, and the shell loads behind the curtain: on
  /// build 28 the line opened, was typed and was most of the way through being
  /// held before anybody could see the screen it was on. What was left was a
  /// bar closing, which is how it was reported: "it kind of just happens and
  /// you can't really tell what it is".
  ///
  /// Depends on the launch, so a widget that reads this is rebuilt when it
  /// ends.
  static bool settledOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LaunchScope>()?.settled ??
      true;

  @override
  State<LaunchCurtain> createState() => _LaunchCurtainState();
}

/// Carries whether the launch is over to everything under it.
class _LaunchScope extends InheritedWidget {
  const _LaunchScope({required this.settled, required super.child});

  final bool settled;

  @override
  bool updateShouldNotify(_LaunchScope oldWidget) =>
      oldWidget.settled != settled;
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

  /// Over, or never played. See [LaunchCurtain.settledOf].
  bool _settled = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final bool still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!widget.enabled || still) return;
    _settled = false;
    _play.forward(from: 0).whenComplete(() {
      if (mounted) setState(() => _settled = true);
    });
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
    child: _LaunchScope(settled: _settled, child: widget.child),
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
            // not land on a button the runner cannot see yet.
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
/// The numbers are the Remotion film's, unchanged. They are in seconds rather
/// than fractions of the whole so the two can be read side by side.
abstract final class LaunchTimeline {
  static double seconds(double progress) =>
      progress * kLaunchDuration.inMilliseconds / 1000;

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
/// Three beats. The mark stands where the icon had it, then draws back and
/// tightens: the wind-up. It goes, and the name is uncovered behind it while
/// the air streaks past. It comes to rest as the last character of its own
/// name, with the studio's under it.
///
/// **The name is set in type, not drawn.** The first version of this drew its
/// own letters out of thick lines, and letters drawn by hand look hand-drawn.
/// The word here is the wordmark the welcome screen and Home already carry,
/// Inter at its heaviest but one, and the mark is the icon's exact geometry
/// (`tool/build_app_icons.py`). The motion does the work the lettering was
/// trying to do.
///
/// Everything is laid out for a phone 393 points wide and scaled to the
/// screen it is on.
class LaunchMarkPainter extends CustomPainter {
  const LaunchMarkPainter({required this.progress});

  final double progress;

  static const Color _silver = Color(0xFFC0C0C0);
  static const Color _white = Color(0xFFFFFFFF);

  // The air going past: each line its own lane, length, moment and strength.
  static const List<({double y, double length, double at, double opacity})>
  _air = <({double y, double length, double at, double opacity})>[
    (y: -58, length: 54, at: 0.58, opacity: 0.22),
    (y: -31, length: 96, at: 0.63, opacity: 0.14),
    (y: 37, length: 72, at: 0.60, opacity: 0.20),
    (y: 61, length: 120, at: 0.66, opacity: 0.12),
    (y: 88, length: 40, at: 0.70, opacity: 0.18),
    (y: -84, length: 30, at: 0.72, opacity: 0.14),
  ];

  /// The mark's measures at a canvas of [m], as the icon generator has them.
  static ({
    double stroke,
    double half,
    double lean,
    double gap,
    double rise,
    double width,
  })
  _markOf(double m) {
    final double w = 0.61 * m;
    return (
      stroke: 0.09 * m,
      half: 0.215 * w,
      lean: 0.2 * w,
      gap: 0.36 * w,
      rise: 0.215 * w,
      width: 0.36 * w + 0.2 * w + 0.09 * m,
    );
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
    final double cy = size.height / 2 - 10 * k;

    // ---- the ground: one soft light from the mark's heading.
    final double glow = seg(0.4, 1.1, out);
    if (glow > 0) {
      canvas.save();
      canvas.translate(width * 0.78, size.height * 0.30);
      canvas.scale(width * 1.2, size.height * 0.7);
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

    // ---- the lockup: the word, a space, the mark at cap height.
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

    const double small = 92;
    const double big = 150;
    final rest = _markOf(small * k);
    final double space = 13 * k;
    final double left = (width - (wordWidth + space + rest.width)) / 2;
    final double home = left + wordWidth + space + rest.width / 2;

    // ---- the three beats.
    final double back = seg(0.2, 0.56);
    final double dash = seg(0.56, 1.02, out);
    final double m = ui.lerpDouble(big, small, back)! * k;
    final double crouch = left - 6 * k + rest.width / 2;
    double along(double amount) => ui.lerpDouble(crouch, home, amount)!;
    final double cx = dash > 0
        ? along(dash)
        : ui.lerpDouble(width / 2, crouch, back)!;
    // Drawn in on itself as it winds back, and opening out again as it lands.
    final double spread = ui.lerpDouble(
      ui.lerpDouble(1, 0.78, back),
      1,
      seg(0.56, 0.9, out),
    )!;

    // ---- the air.
    final Paint air = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25 * k
      ..strokeCap = StrokeCap.round;
    for (final line in _air) {
      final double p = ((t - line.at) / 0.42).clamp(0.0, 1.0);
      if (p <= 0 || p >= 1) continue;
      final double x = ui.lerpDouble(
        width * 0.86,
        width * 0.06,
        out.transform(p),
      )!;
      final double fade = math.sin(math.pi * p);
      final double y = cy + line.y * k;
      canvas.drawLine(
        Offset(x, y),
        Offset(x + line.length * k * (0.4 + 0.6 * fade), y),
        air..color = _white.withValues(alpha: line.opacity * fade),
      );
    }

    // ---- the word, uncovered up to the mark's trailing edge. Nothing before
    // the dash: the mark starts in the middle of where the word will be.
    final double trailing = cx - _markOf(m).width / 2 - 6 * k;
    final double shown = dash <= 0
        ? 0
        : (trailing - left).clamp(0.0, wordWidth);
    if (shown > 0) {
      // Set so the capitals are centred on the mark, whatever the line box.
      final double baseline = word.computeDistanceToActualBaseline(
        TextBaseline.alphabetic,
      );
      final double top = cy + 0.3635 * fontSize - baseline;
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(left, top, shown, word.height));
      word.paint(canvas, Offset(left, top));
      canvas.restore();
    }

    // ---- the mark, and where it was a moment ago, fainter.
    final double before = along(seg(0.56 + 0.03, 1.02 + 0.03, out));
    final double speed = (along(dash) - before).abs();
    for (var ghost = 3; ghost >= 1; ghost--) {
      final double opacity = math.min(0.28, speed / (60 * k)) / ghost;
      if (opacity < 0.004) continue;
      _mark(canvas, cx - speed * ghost * 0.55, cy, m, spread, opacity);
    }
    _mark(canvas, cx, cy, m, spread, 1);

    // ---- the studio's name, under it.
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
          cy + 46 * k + ui.lerpDouble(6 * k, 0, named)!,
        ),
      );
    }

    canvas.restore();
  }

  /// The two chevrons, centred on ([cx], [cy]), at a canvas of [m].
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
    final double rise = g.rise * spread;
    final Paint pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = g.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 0; i < 2; i++) {
      final double x = cx - gap / 2 - g.lean / 2 + i * gap;
      final double y = cy + rise / 2 - i * rise;
      canvas.drawPath(
        Path()
          ..moveTo(x, y - g.half)
          ..lineTo(x + g.lean, y)
          ..lineTo(x, y + g.half),
        pen..color = (i == 0 ? _silver : _white).withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(LaunchMarkPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
