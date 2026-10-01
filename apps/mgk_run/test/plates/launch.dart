/// **The launch animation, as frames.**
///
/// It runs for under two seconds and nobody can review something that has
/// gone before they have looked at it. So it is drawn here stopped: the beats
/// on one sheet, in order, and the three that matter at phone size. To watch
/// it move, see `launch_film.dart`.
///
/// Regenerate with:
///
///     flutter test test/plates/launch.dart
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/launch/launch_curtain.dart';
import 'package:mgk_ui/mgk_ui.dart';

import 'plate.dart';

/// One stopped frame of the animation, filling whatever it is given.
class _Frame extends StatelessWidget {
  const _Frame(this.progress);

  final double progress;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.bg,
    child: CustomPaint(
      painter: LaunchMarkPainter(progress: progress),
      child: const SizedBox.expand(),
    ),
  );
}

void main() {
  // The beats, in seconds: the mark, the wind-up, the dash with the name
  // coming out from behind it, the rest, and the lift.
  const List<double> beats = <double>[
    0.00,
    0.40,
    0.56,
    0.64,
    0.72,
    0.84,
    1.10,
    1.50,
    1.80,
  ];

  testWidgets('the beats, on one sheet', (tester) async {
    const Size cell = Size(300, 300);
    await plate(
      tester,
      'launch-sheet',
      ColoredBox(
        color: AppColors.surface,
        child: Wrap(
          spacing: 2,
          runSpacing: 2,
          children: <Widget>[
            for (final double t in beats)
              SizedBox.fromSize(
                size: cell,
                child: Stack(
                  children: <Widget>[
                    _Frame(t * 1000 / kLaunchDuration.inMilliseconds),
                    Positioned(
                      left: 10,
                      top: 8,
                      child: Text(
                        '${(t * 1000).round()} ms',
                        style: const TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          color: AppColors.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      size: const Size(3 * 300 + 4, 3 * 300 + 4),
      pixelRatio: 2,
    );
  });

  for (final (String name, double t) in <(String, double)>[
    ('launch-mark', 0.0),
    ('launch-dash', 0.70),
    ('launch-word', 1.50),
  ]) {
    testWidgets(name, (tester) async {
      await plate(
        tester,
        name,
        _Frame(t * 1000 / kLaunchDuration.inMilliseconds),
      );
    });
  }
}
