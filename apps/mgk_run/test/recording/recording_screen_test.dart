import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_run_recorder.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/recording/domain/run_recorder.dart';
import 'package:mgk_run/src/features/recording/presentation/recording_screen.dart';

void main() {
  testWidgets(
    'shows live stats and controls, and time advances while recording',
    (tester) async {
      final recorder = FakeRunRecorder(
        interval: const Duration(milliseconds: 100),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: RecordingScreen(recorder: recorder),
        ),
      );

      // Initial frame: recording, zeroed stats, both controls.
      expect(find.text('Recording'), findsOneWidget);
      expect(find.text('DISTANCE'), findsOneWidget);
      expect(find.text('0:00'), findsOneWidget);
      expect(find.text('0.00 km'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Pause'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Finish'), findsOneWidget);

      // Advance one second: the ticker moves time on and fixes accrue distance.
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('0:01'), findsOneWidget);
      expect(find.text('0.00 km'), findsNothing);

      await recorder.stop(); // cancel the replay timer before teardown
    },
  );

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
