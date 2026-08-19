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

/// The marker has to keep saying *by how much*.
///
/// [PaceBandMeter] documents the rail as wider than the band "so that being
/// outside it is still drawn somewhere, rather than pinned to an edge with no
/// sense of by how much". The first implementation extended the rail about a
/// band-width past each edge and clamped, and a band is roughly thirty seconds
/// wide — so anything much past half a minute off pinned and stopped saying
/// anything at all. Someone two minutes down got the same mark as someone
/// thirty-five seconds down.
void main() {
  late DateTime clock;

  final TrainingPaces paces = TrainingPaces.fromRace(
    Distance.meters(5000),
    const Duration(minutes: 24, seconds: 30),
  );

  /// Drives a threshold session — a corridor with two live edges — at [pace],
  /// and reports where the marker landed.
  Future<double> markerAt(WidgetTester tester, Duration pace) async {
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
          // Keyed by pace, because this helper is called more than once in a
          // test. Without it Flutter reuses the State at that tree position:
          // initState never runs again, the screen stays subscribed to the
          // *first* recorder, and every later measurement silently returns the
          // first one's answer. Two paces landing on the identical marker
          // position is what gave it away.
          key: ValueKey<Duration>(pace),
          recorder: recorder,
          plannedSession: const PlannedSession(
            weekday: DateTime.monday,
            kind: SessionKind.threshold,
            distanceMeters: 5000,
          ),
          paces: paces,
        ),
      ),
    );

    await tester.pump();
    for (int i = 0; i < 125; i++) {
      clock = clock.add(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 20));
    }

    final double position = tester
        .widget<PaceBandMeter>(find.byType(PaceBandMeter))
        .position;
    await recorder.stop();
    return position;
  }

  Duration slowerBy(int seconds) => Duration(
    seconds:
        bandFor(
          SessionKind.threshold,
          paces,
        )!.slow.secondsPerKilometer.round() +
        seconds,
  );

  testWidgets('further off the band is further along the rail, always', (
    WidgetTester tester,
  ) async {
    // Three runners, each a minute slower than the last, all well outside the
    // band. Under the old clamp all three sat on the same pixel.
    final double near = await markerAt(tester, slowerBy(40));
    final double far = await markerAt(tester, slowerBy(100));
    final double further = await markerAt(tester, slowerBy(160));

    expect(near, greaterThan(far));
    expect(far, greaterThan(further));
  });

  testWidgets('but it never reaches the end, so there is always room left', (
    WidgetTester tester,
  ) async {
    final double miles = await markerAt(tester, slowerBy(600));

    expect(miles, greaterThan(0));
    expect(miles, lessThan(PaceBandMeter.defaultBandStart));
  });

  testWidgets('inside the band it stays linear, where seconds matter', (
    WidgetTester tester,
  ) async {
    final PaceBand band = bandFor(SessionKind.threshold, paces)!;
    final int middle =
        ((band.slow.secondsPerKilometer + band.fast.secondsPerKilometer) / 2)
            .round();

    final double position = await markerAt(tester, Duration(seconds: middle));

    // Mid-band is mid-band: halfway between the lit segment's two edges.
    const double centre =
        (PaceBandMeter.defaultBandStart + PaceBandMeter.defaultBandEnd) / 2;
    expect(position, closeTo(centre, 0.06));
  });
}
