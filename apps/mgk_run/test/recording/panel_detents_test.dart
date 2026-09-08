import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_run_recorder.dart';
import 'package:mgk_run/src/features/recording/presentation/recording_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';

const Size kPhone = Size(393, 852);
const Size kSmallPhone = Size(320, 568);
const Size kMaxPhone = Size(430, 932);

/// **Three resting places, where there were two** (ADR-0031).
///
/// The old decision was a toggle: "with three stops a drag lands somewhere the
/// runner did not choose, and they have to look to find out where". That holds
/// for three stops of the *same* content and is what makes the third one safe
/// here — the peek is a different readout, not a smaller one, so landing on it
/// is unambiguous. The build 13 field test asked for it directly: the map full
/// screen, with time and distance only.
void main() {
  group('the fractions are ordered on every phone', () {
    // A pure-function test, and the one that earns itself:
    // `DraggableScrollableSheet` asserts its snap sizes are strictly
    // increasing, so a screen where peek meets collapsed is a crash rather
    // than a layout quirk. The collapsed detent is a *summed content height*,
    // so it grows with the band, the brief and a problem line — and at 320x568
    // with all three it is already 0.85.
    for (final size in <Size>[kSmallPhone, kPhone, kMaxPhone]) {
      for (final hasProblem in <bool>[false, true]) {
        for (final hasBrief in <bool>[false, true]) {
          test(
            '${size.width.toInt()}pt problem=$hasProblem brief=$hasBrief',
            () {
              final double peek = peekFractionFor(size.height);
              final double collapsed = collapsedFractionFor(
                size.height,
                hasProblem: hasProblem,
                hasBrief: hasBrief,
              );
              expect(
                peek,
                lessThan(collapsed),
                reason: 'the sheet asserts strictly increasing snap sizes',
              );
            },
          );
        }
      }
    }
  });

  testWidgets('dragging down leaves the two figures and the map', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(kPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final recorder = FakeRunRecorder();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RecordingScreen(recorder: recorder),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    // It opens on the numbers, not on the peek. The peek is somewhere you can
    // go, not where you start.
    expect(find.text('PACE /KM'), findsOneWidget);

    await tester.drag(find.text('DISTANCE'), const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('DISTANCE'), findsOneWidget);
    expect(find.text('TIME'), findsOneWidget);
    expect(
      find.text('PACE /KM'),
      findsNothing,
      reason: 'the peek is a different readout, not a clipped one',
    );

    await recorder.stop();
  });

  testWidgets('and dragging back up returns the full readout', (tester) async {
    await tester.binding.setSurfaceSize(kPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final recorder = FakeRunRecorder();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RecordingScreen(recorder: recorder),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    await tester.drag(find.text('DISTANCE'), const Offset(0, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('PACE /KM'), findsNothing);

    await tester.drag(find.text('DISTANCE'), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('PACE /KM'), findsOneWidget);

    await recorder.stop();
  });
}
