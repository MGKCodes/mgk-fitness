import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_run_recorder.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/recording/domain/run_recorder.dart';
import 'package:mgk_run/src/features/recording/presentation/recording_screen.dart';

void main() {
  testWidgets(
    'shows live stats and controls, and time advances while recording',
    (tester) async {
      var clock = DateTime(2026, 1, 1, 8);
      final recorder = FakeRunRecorder(
        interval: const Duration(milliseconds: 100),
        now: () => clock,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: RecordingScreen(recorder: recorder),
        ),
      );

      // Initial frame: no fix has landed yet, so the screen says so rather
      // than presenting a confident 0.00 km.
      expect(find.text('Acquiring GPS'), findsOneWidget);
      expect(find.text('DISTANCE'), findsOneWidget);
      expect(find.text('0:00'), findsOneWidget);
      // Value and unit are separate widgets — the hero numeral sets the number
      // at 112pt and the unit small beside it, so `0.00 km` is never one string.
      expect(find.text('0.00'), findsOneWidget);
      expect(find.text('km'), findsOneWidget);
      // Current pace and average, both honestly absent this early.
      expect(find.text('PACE'), findsOneWidget);
      expect(find.text('AVG'), findsOneWidget);
      expect(find.text('--:-- /km'), findsNWidgets(2));
      expect(find.widgetWithText(OutlinedButton, 'Pause'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Finish'), findsOneWidget);

      // Advance: fixes land, so the label settles to Recording, the clock
      // moves off the recorder's wall time, and distance leaves zero.
      clock = clock.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(AppMotion.slow); // let the numeral finish counting

      expect(find.text('Recording'), findsOneWidget);
      expect(find.text('0:01'), findsOneWidget);
      expect(find.text('0.00'), findsNothing);

      await recorder.stop(); // cancel the replay timer before teardown
    },
  );

  testWidgets('elapsed time survives the app being backgrounded', (
    tester,
  ) async {
    // The ticker is throttled and then suspended while iOS holds the app in
    // the background, so it cannot be what counts the time. Jumping the clock
    // without delivering the intervening ticks is that suspension.
    var clock = DateTime(2026, 1, 1, 8);
    final recorder = FakeRunRecorder(
      interval: const Duration(milliseconds: 100),
      now: () => clock,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RecordingScreen(recorder: recorder),
      ),
    );

    clock = clock.add(const Duration(minutes: 12, seconds: 30));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('12:30'), findsOneWidget);

    await recorder.stop();
  });

  testWidgets('shows the current pace separately from the average', (
    tester,
  ) async {
    // The old screen labelled a cumulative average "PACE" — which is the
    // question a runner asks mid-stride and the one number that cannot answer
    // it. Two figures, two labels, and neither pretending to be the other.
    var clock = DateTime(2026, 1, 1, 8);
    final recorder = FakeRunRecorder(
      interval: const Duration(milliseconds: 20),
      now: () => clock,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RecordingScreen(recorder: recorder),
      ),
    );

    clock = clock.add(const Duration(minutes: 4));
    await tester.pump(const Duration(seconds: 4));
    await tester.pump(AppMotion.slow);

    expect(find.text('PACE'), findsOneWidget);
    expect(find.text('AVG'), findsOneWidget);
    // Enough of the canned trace has replayed for both to be real numbers.
    expect(find.text('--:-- /km'), findsNothing);

    await recorder.stop();
  });

  testWidgets("shows today's session and progress toward it", (tester) async {
    final recorder = FakeRunRecorder(
      interval: const Duration(milliseconds: 20),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RecordingScreen(
          recorder: recorder,
          plannedSession: const PlannedSession(
            weekday: DateTime.monday,
            kind: SessionKind.easy,
            distanceMeters: 5000,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('Easy run'), findsOneWidget);
    expect(find.textContaining('of 5.00 km'), findsOneWidget);

    await recorder.stop();
  });

  testWidgets('an unplanned day shows no target block at all', (tester) async {
    // Principle 6: absent beats zero. An empty "TODAY" card on a day with no
    // session is a scoreboard nobody is playing on.
    final recorder = FakeRunRecorder(
      interval: const Duration(milliseconds: 20),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RecordingScreen(recorder: recorder),
      ),
    );
    await tester.pump();

    expect(find.text('TODAY'), findsNothing);

    await recorder.stop();
  });

  testWidgets('a refused permission says so, and offers Settings', (
    tester,
  ) async {
    final recorder = FakeRunRecorder(
      failsWith: RecorderProblem.permissionDeniedForever,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RecordingScreen(recorder: recorder),
      ),
    );
    await tester.pump();

    expect(
      find.textContaining('Location is turned off for Run'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Open Settings'), findsOneWidget);
    // Nothing is being recorded, so it must not claim to be.
    expect(find.text('Recording'), findsNothing);
  });

  testWidgets('location services off does not offer a useless Settings link', (
    tester,
  ) async {
    // The app-settings deep link cannot reach the system location switch, so
    // offering it would send someone to a screen that cannot fix their problem.
    final recorder = FakeRunRecorder(
      failsWith: RecorderProblem.locationServicesOff,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RecordingScreen(recorder: recorder),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Location Services are off'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Open Settings'), findsNothing);
  });

  testWidgets('pause swaps the control and status label', (tester) async {
    final recorder = FakeRunRecorder(
      interval: const Duration(milliseconds: 100),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RecordingScreen(recorder: recorder),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Pause'));
    await tester.pump(); // deliver the status change
    await tester.pump();

    expect(find.text('Paused'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Resume'), findsOneWidget);

    await recorder.stop(); // cancel the replay timer before teardown
  });

  testWidgets('cancel confirms, then discards and fires onCancel', (
    tester,
  ) async {
    final recorder = FakeRunRecorder(
      interval: const Duration(milliseconds: 100),
    );
    var cancelled = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RecordingScreen(
          recorder: recorder,
          onCancel: () => cancelled = true,
        ),
      ),
    );

    // The close affordance is present only when onCancel is wired.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump(); // showDialog
    await tester.pump(const Duration(milliseconds: 300)); // transition
    expect(find.text('Discard this run?'), findsOneWidget);

    await tester.tap(find.text('Discard'));
    await tester.pump(); // pop dialog, discard() begins
    await tester.pump(); // discard() completes -> onCancel

    expect(cancelled, isTrue);
    expect(recorder.status, RecorderStatus.stopped); // timer cancelled
  });

  testWidgets('cancel can be dismissed with Keep running', (tester) async {
    final recorder = FakeRunRecorder(
      interval: const Duration(milliseconds: 100),
    );
    var cancelled = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RecordingScreen(
          recorder: recorder,
          onCancel: () => cancelled = true,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Keep running'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // dialog dismissed

    expect(cancelled, isFalse);
    expect(find.text('Recording'), findsOneWidget); // still recording

    await recorder.stop(); // cancel the replay timer before teardown
  });
}
