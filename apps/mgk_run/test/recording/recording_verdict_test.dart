import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_run_recorder.dart';
import 'package:mgk_run/src/features/coaching/domain/pace_model.dart';
import 'package:mgk_run/src/features/coaching/domain/session_effort.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/recording/presentation/recording_screen.dart';
import 'package:mgk_units/mgk_units.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// A phone, not Flutter's default 800x600 surface — see recording_screen_test.
const Size kPhone = Size(393, 852);

/// The two instructions are not worth the same, and the session decides which
/// of them is real.
///
/// On an easy, recovery or long day the band is a **ceiling**: running under it
/// is the session working. PICK IT UP there is a quality-session rule applied to
/// a day that is not about pace, and it fires hardest on a tired runner at the
/// end of a long one. On threshold, marathon pace and a time trial the pace *is*
/// the session, so both directions are real.
void main() {
  late DateTime clock;

  final TrainingPaces paces = TrainingPaces.fromRace(
    Distance.meters(5000),
    const Duration(minutes: 24, seconds: 30),
  );

  /// Far enough outside the band to clear the hysteresis margin either way.
  Duration slowerThan(PaceBand band) =>
      Duration(seconds: band.slow.secondsPerKilometer.round() + 75);
  Duration fasterThan(PaceBand band) =>
      Duration(seconds: band.fast.secondsPerKilometer.round() - 75);

  /// Returns the recorder so the caller can stop it *inside* the test body.
  /// The fake replays on a repeating timer and the binding asserts none are
  /// pending when the body ends, which a tearDown runs too late to satisfy.
  Future<FakeRunRecorder> pumpRun(
    WidgetTester tester, {
    required SessionKind kind,
    required Duration pace,
  }) async {
    await tester.binding.setSurfaceSize(kPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    clock = DateTime(2026, 1, 1, 8);
    final FakeRunRecorder recorder = FakeRunRecorder(
      interval: const Duration(milliseconds: 20),
      trace: demoRunTrace(pacePerKm: pace),
      now: () => clock,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RecordingScreen(
          recorder: recorder,
          plannedSession: PlannedSession(
            weekday: DateTime.monday,
            kind: kind,
            distanceMeters: 5000,
          ),
          paces: paces,
        ),
      ),
    );

    // Past both warm-up gates, so the band is speaking.
    await tester.pump();
    for (int i = 0; i < 125; i++) {
      clock = clock.add(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 20));
    }
    return recorder;
  }

  group('an easy session caps effort rather than bounding it', () {
    testWidgets('running under the band is on target, not a failing', (
      WidgetTester tester,
    ) async {
      final PaceBand band = bandFor(SessionKind.easy, paces)!;
      final FakeRunRecorder rec = await pumpRun(
        tester,
        kind: SessionKind.easy,
        pace: slowerThan(band),
      );

      expect(find.text('ON TARGET'), findsOneWidget);
      expect(
        find.text('PICK IT UP'),
        findsNothing,
        reason: 'nobody needs chasing for running an easy day easily',
      );

      await rec.stop();
    });

    testWidgets('running over it still earns the instruction', (
      WidgetTester tester,
    ) async {
      final PaceBand band = bandFor(SessionKind.easy, paces)!;
      final FakeRunRecorder rec = await pumpRun(
        tester,
        kind: SessionKind.easy,
        pace: fasterThan(band),
      );

      expect(find.text('EASE OFF'), findsOneWidget);

      await rec.stop();
    });

    testWidgets('and the lower edge is not labelled, because it is not one', (
      WidgetTester tester,
    ) async {
      final PaceBand band = bandFor(SessionKind.easy, paces)!;
      final FakeRunRecorder rec = await pumpRun(
        tester,
        kind: SessionKind.easy,
        pace: slowerThan(band),
      );

      final PaceBandMeter meter = tester.widget<PaceBandMeter>(
        find.byType(PaceBandMeter),
      );
      expect(meter.slowLabel, isNull);
      expect(meter.fastLabel, isNotNull);
      // The lit region means "acceptable", so on a ceiling it starts at the
      // rail's beginning rather than at a lower bound the session lacks.
      expect(meter.bandStart, 0);

      await rec.stop();
    });
  });

  group(
    'a threshold session is about the pace, so both directions are real',
    () {
      testWidgets('running under the band is worth saying', (
        WidgetTester tester,
      ) async {
        final PaceBand band = bandFor(SessionKind.threshold, paces)!;
        final FakeRunRecorder rec = await pumpRun(
          tester,
          kind: SessionKind.threshold,
          pace: slowerThan(band),
        );

        expect(find.text('PICK IT UP'), findsOneWidget);

        await rec.stop();
      });

      testWidgets('and the band keeps both its edges', (
        WidgetTester tester,
      ) async {
        final PaceBand band = bandFor(SessionKind.threshold, paces)!;
        final FakeRunRecorder rec = await pumpRun(
          tester,
          kind: SessionKind.threshold,
          pace: slowerThan(band),
        );

        final PaceBandMeter meter = tester.widget<PaceBandMeter>(
          find.byType(PaceBandMeter),
        );
        expect(meter.slowLabel, isNotNull);
        expect(meter.bandStart, PaceBandMeter.defaultBandStart);

        await rec.stop();
      });
    },
  );
}
