import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_run_recorder.dart';
import 'package:mgk_run/src/features/coaching/domain/pace_model.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/recording/presentation/recording_screen.dart';
import 'package:mgk_units/mgk_units.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// A phone, not Flutter's default 800x600 surface — see recording_screen_test.
const Size kPhone = Size(393, 852);

/// What the screen says once the fixes stop arriving.
///
/// The top strip already knew: `gpsSignalFor` ages the last fix and reports
/// `GpsSignal.none`, so the label reads "No signal" and the bars empty. The
/// numbers did not. `rollingPace` measures its window back from the newest
/// point's own timestamp and is handed no clock, so with fixes stopped it
/// returned the last honest window indefinitely — a confident 7:52 beside a
/// frozen distance and a screen saying it had lost you.
void main() {
  late DateTime clock;

  /// A trace that runs out is how the fake starves the screen of fixes without
  /// leaving the recording state. Pausing looks similar from the inside and is
  /// a different screen entirely: it says Paused, and offers Resume.
  FakeRunRecorder starving(int points) {
    clock = DateTime(2026, 1, 1, 8);
    return FakeRunRecorder(
      interval: const Duration(milliseconds: 20),
      trace: demoRunTrace().take(points).toList(),
      now: () => clock,
    );
  }

  Future<void> advance(WidgetTester tester, int points) async {
    await tester.pump();
    for (int i = 0; i < points; i++) {
      clock = clock.add(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<FakeRunRecorder> pumpRun(
    WidgetTester tester, {
    required int fixes,
    bool planned = false,
  }) async {
    await tester.binding.setSurfaceSize(kPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final FakeRunRecorder recorder = starving(fixes);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RecordingScreen(
          recorder: recorder,
          // Only where a test needs the band. Without a session there is no
          // band at all, so asserting that no verdict shows would pass for the
          // wrong reason.
          plannedSession: planned
              ? const PlannedSession(
                  weekday: DateTime.monday,
                  kind: SessionKind.easy,
                  distanceMeters: 5000,
                )
              : null,
          paces: planned
              ? TrainingPaces.fromRace(
                  Distance.meters(5000),
                  const Duration(minutes: 24, seconds: 30),
                )
              : null,
        ),
      ),
    );
    await advance(tester, fixes);
    return recorder;
  }

  testWidgets('while fixes arrive, the live pace is a number', (
    WidgetTester tester,
  ) async {
    final FakeRunRecorder recorder = await pumpRun(tester, fixes: 125);

    expect(find.text('No signal'), findsNothing);
    // Six minutes and 0.7 km in, both pace columns have something honest to
    // say, so nothing on the row is dashed.
    expect(find.text('--:--'), findsNothing);

    await recorder.stop();
  });

  testWidgets('once they stop, it dashes rather than holding the last one', (
    WidgetTester tester,
  ) async {
    final FakeRunRecorder recorder = await pumpRun(tester, fixes: 125);

    // The trace is spent. The run is still recording and the clock still runs,
    // which is exactly the state that used to read as confident.
    await advance(tester, 30);

    expect(find.text('No signal'), findsOneWidget);
    expect(
      find.text('--:--'),
      findsOneWidget,
      reason: 'the live pace must not survive the fixes it was computed from',
    );

    await recorder.stop();
  });

  testWidgets('and the band stops judging a pace it no longer has', (
    WidgetTester tester,
  ) async {
    final FakeRunRecorder recorder = await pumpRun(
      tester,
      fixes: 125,
      planned: true,
    );

    // Warmed up and still hearing satellites: the band is judging.
    final Iterable<String> before = <String>[
      'PICK IT UP',
      'ON TARGET',
      'EASE OFF',
    ].where((String v) => find.text(v).evaluate().isNotEmpty);
    expect(before, isNotEmpty, reason: 'the band should be speaking here');

    await advance(tester, 30);

    // No pace means no standing, so no instruction is issued against a number
    // the screen has just admitted it cannot compute.
    for (final String verdict in <String>[
      'PICK IT UP',
      'ON TARGET',
      'EASE OFF',
    ]) {
      expect(find.text(verdict), findsNothing);
    }
    expect(find.text('FINDING YOUR PACE'), findsOneWidget);

    await recorder.stop();
  });
}
