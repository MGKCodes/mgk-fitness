import 'package:flutter/material.dart';

import '../motion/press_scale.dart';
import '../theme/app_theme.dart';

/// Who a [ProviderSignInButton] signs in with.
enum SignInProvider { apple, google }

/// **Continue with Apple** or **Continue with Google**: a white button with the
/// provider's mark, the same height and corners as [PrimaryButton].
///
/// **The one place the suite is not greyscale, and deliberately.** Both marks
/// belong to their owners and each owner says how it is drawn: Apple's in black
/// on white for a dark screen, Google's "G" in its own four colours on a light
/// fill, never recoloured. ADR-0009's greyscale is the suite's own voice; these
/// are someone else's, set down beside it.
///
/// **White, both of them.** Apple's guidelines put its white button on dark
/// backgrounds and rule out the black one there; Google's neutral fill is the
/// nearest light match. Two buttons of equal weight also keep the rule Apple
/// sets for offering it at all: Sign in with Apple no less prominent than any
/// other way in.
///
/// The marks are drawn rather than shipped as images, so they are sharp at any
/// size and the package carries no binary for them.
class ProviderSignInButton extends StatelessWidget {
  const ProviderSignInButton.apple({
    super.key,
    required this.onPressed,
    this.busy = false,
  }) : provider = SignInProvider.apple;

  const ProviderSignInButton.google({
    super.key,
    required this.onPressed,
    this.busy = false,
  }) : provider = SignInProvider.google;

  final SignInProvider provider;

  /// Null draws it disabled — while another way of signing in is under way.
  final VoidCallback? onPressed;

  /// The provider's own sheet is up, or its answer is being checked.
  final bool busy;

  /// [PrimaryButton]'s height, so the two stack without their edges
  /// disagreeing.
  static const double height = 52;

  String get label => switch (provider) {
    SignInProvider.apple => 'Continue with Apple',
    SignInProvider.google => 'Continue with Google',
  };

  @override
  Widget build(BuildContext context) {
    final enabled = !busy && onPressed != null;
    final (fill, ink) = switch (provider) {
      // Apple's white style.
      SignInProvider.apple => (Colors.white, Colors.black),
      // Google's neutral theme: #F2F2F2 fill, #1F1F1F text, no stroke.
      SignInProvider.google => (
        const Color(0xFFF2F2F2),
        const Color(0xFF1F1F1F),
      ),
    };
    final mark = switch (provider) {
      SignInProvider.apple => AppleLogo(size: 18, color: ink),
      SignInProvider.google => const GoogleLogo(size: 18),
    };

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      // The tap a screen reader sends: the child's own is excluded with its
      // semantics, so without this a double-tap found nothing to press.
      onTap: enabled ? onPressed : null,
      excludeSemantics: true,
      child: PressScale(
        enabled: enabled,
        onTap: enabled ? onPressed : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: onPressed == null && !busy ? 0.5 : 1,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            // The mark and the words centred together, as Apple draws its own
            // button, so the two buttons' words start in the same place.
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Center(
                    child: busy
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ink,
                            ),
                          )
                        : mark,
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    // The label every other button in the suite has, so the
                    // three choices under each other read as one set.
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Apple's logo, for a Sign in with Apple button and nothing else.
///
/// The outline is the one the `sign_in_with_apple` plugin draws its own button
/// with, from `flutter_apple_sign_in` (MIT License, Copyright (c) 2019 Rody
/// Davis / Tom Gilder), in a box 25 wide to 31 high.
class AppleLogo extends StatelessWidget {
  const AppleLogo({super.key, this.size = 18, this.color = Colors.black});

  /// The logo's height.
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size(size * 25 / 31, size),
    painter: _ApplePainter(color),
  );
}

class _ApplePainter extends CustomPainter {
  const _ApplePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * .50779, h * .28732)
      ..cubicTo(
        w * .4593,
        h * .28732,
        w * .38424,
        h * .24241,
        w * .30519,
        h * .24404,
      )
      ..cubicTo(
        w * .2009,
        h * .24512,
        w * .10525,
        h * .29328,
        w * .05145,
        h * .36957,
      )
      ..cubicTo(
        w * -.05683,
        h * .5227,
        w * .02355,
        h * .74888,
        w * .12916,
        h * .87333,
      )
      ..cubicTo(
        w * .18097,
        h * .93394,
        w * .24209,
        h * 1.00211,
        w * .32313,
        h * .99995,
      )
      ..cubicTo(
        w * .40084,
        h * .99724,
        w * .43007,
        h * .95883,
        w * .52439,
        h * .95883,
      )
      ..cubicTo(
        w * .61805,
        h * .95883,
        w * .64462,
        h * .99995,
        w * .72699,
        h * .99833,
      )
      ..cubicTo(
        w * .81069,
        h * .99724,
        w * .86383,
        h * .93664,
        w * .91498,
        h * .8755,
      )
      ..cubicTo(
        w * .97409,
        h * .80515,
        w * .99867,
        h * .73698,
        w * 1,
        h * .73319,
      )
      ..cubicTo(
        w * .99801,
        h * .73265,
        w * .83726,
        h * .68233,
        w * .83526,
        h * .53082,
      )
      ..cubicTo(
        w * .83394,
        h * .4042,
        w * .96214,
        h * .3436,
        w * .96812,
        h * .34089,
      )
      ..cubicTo(
        w * .89505,
        h * .25378,
        w * .78279,
        h * .24404,
        w * .7436,
        h * .24187,
      )
      ..cubicTo(
        w * .6413,
        h * .23538,
        w * .55561,
        h * .28732,
        w * .50779,
        h * .28732,
      )
      ..close()
      ..moveTo(w * .68049, h * .15962)
      ..cubicTo(w * .72367, h * .11742, w * .75223, h * .05844, w * .74426, 0)
      ..cubicTo(
        w * .68249,
        h * .00216,
        w * .60809,
        h * .03355,
        w * .56359,
        h * .07575,
      )
      ..cubicTo(
        w * .52373,
        h * .11309,
        w * .48919,
        h * .17315,
        w * .49849,
        h * .23051,
      )
      ..cubicTo(
        w * .56691,
        h * .23484,
        w * .63732,
        h * .20183,
        w * .68049,
        h * .15962,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ApplePainter oldDelegate) => oldDelegate.color != color;
}

/// Google's "G", in its four colours, which Google's guidelines do not allow
/// to change.
///
/// Drawn from Google's own 48-unit sign-in mark.
class GoogleLogo extends StatelessWidget {
  const GoogleLogo({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: const _GooglePainter());
}

class _GooglePainter extends CustomPainter {
  const _GooglePainter();

  static final Path _red = Path()
    ..moveTo(24, 9.5)
    ..cubicTo(27.54, 9.5, 30.71, 10.72, 33.21, 13.1)
    ..lineTo(40.06, 6.25)
    ..cubicTo(35.9, 2.38, 30.47, 0, 24, 0)
    ..cubicTo(14.62, 0, 6.51, 5.38, 2.56, 13.22)
    ..lineTo(10.54, 19.41)
    ..cubicTo(12.43, 13.72, 17.74, 9.5, 24, 9.5)
    ..close();

  static final Path _blue = Path()
    ..moveTo(46.98, 24.55)
    ..cubicTo(46.98, 22.98, 46.83, 21.46, 46.6, 20)
    ..lineTo(24, 20)
    ..lineTo(24, 29.02)
    ..lineTo(36.94, 29.02)
    ..cubicTo(36.36, 31.98, 34.68, 34.5, 32.16, 36.2)
    ..lineTo(39.89, 42.2)
    ..cubicTo(44.4, 38.02, 46.98, 31.84, 46.98, 24.55)
    ..close();

  static final Path _yellow = Path()
    ..moveTo(10.53, 28.59)
    ..cubicTo(10.05, 27.14, 9.77, 25.6, 9.77, 24)
    ..cubicTo(9.77, 22.4, 10.04, 20.86, 10.53, 19.41)
    ..lineTo(2.55, 13.22)
    ..cubicTo(0.92, 16.46, 0, 20.12, 0, 24)
    ..cubicTo(0, 27.88, 0.92, 31.54, 2.56, 34.78)
    ..lineTo(10.53, 28.59)
    ..close();

  static final Path _green = Path()
    ..moveTo(24, 48)
    ..cubicTo(30.48, 48, 35.93, 45.87, 39.89, 42.19)
    ..lineTo(32.16, 36.19)
    ..cubicTo(30.01, 37.64, 27.24, 38.49, 24, 38.49)
    ..cubicTo(17.74, 38.49, 12.43, 34.27, 10.53, 28.58)
    ..lineTo(2.55, 34.77)
    ..cubicTo(6.51, 42.62, 14.62, 48, 24, 48)
    ..close();

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(size.width / 48, size.height / 48)
      ..drawPath(_red, Paint()..color = const Color(0xFFEA4335))
      ..drawPath(_blue, Paint()..color = const Color(0xFF4285F4))
      ..drawPath(_yellow, Paint()..color = const Color(0xFFFBBC05))
      ..drawPath(_green, Paint()..color = const Color(0xFF34A853))
      ..restore();
  }

  @override
  bool shouldRepaint(_GooglePainter oldDelegate) => false;
}
