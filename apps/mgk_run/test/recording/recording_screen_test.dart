import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_run_recorder.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/pace_model.dart';
import 'package:mgk_units/mgk_units.dart';
import 'package:mgk_run/src/features/recording/domain/live_metrics.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';
import 'package:mgk_run/src/features/recording/domain/run_recorder.dart';
import 'package:mgk_run/src/features/recording/presentation/recording_screen.dart';

/// A phone, not Flutter's default 800x600 test surface.
///
/// **The surface size is load-bearing in this file.** Every test here used to
/// run at the default, which is nearly twice a phone's width, so a readout row
/// that overflowed by 23px on an iPhone fitted comfortably and shipped green.
/// Three separate layout defects reached a device that way. Pinning the surface
/// to real phone dimensions is what lets these tests see them at all.
const Size kPhone = Size(393, 852);

/// The narrowest phone still worth supporting.
const Size kSmallPhone = Size(320, 568);

void main() {
  testWidgets(
    'shows live stats and controls, and time advances while recording',
    (tester) async {
      await tester.binding.setSurfaceSize(kPhone);
      addTearDown(() => tester.binding.setSurfaceSize(null));

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
      // The unit lives in the column label now rather than being repeated in
      // every value — which is what buys the width three figures need on a
      // real phone.
      expect(find.text('PACE /KM'), findsOneWidget);
      expect(find.text('AVG /KM'), findsOneWidget);
      expect(find.text('--:--'), findsNWidgets(2));
      // Pause is the filled control while the run is going, and Finish is not
      // on the screen at all — see the control row in `recording_screen.dart`
      // and the group below for what the swap is protecting.
      expect(find.widgetWithText(FilledButton, 'Pause'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Lap'), findsOneWidget);
      expect(find.text('Finish'), findsNothing);
      // Each control carries a glyph as well as its word, asked for off the
      // build 13 field test: text alone is hard to hit at a glance while
      // moving. **Both**, not one — the word is asserted above, because an
      // icon-only control asks somebody out of breath to recognise a glyph at
      // arm's length, and `Finish` is not worth guessing at.
      expect(find.widgetWithIcon(FilledButton, Icons.pause), findsOneWidget);
      expect(
        find.widgetWithIcon(OutlinedButton, Icons.flag_outlined),
        findsOneWidget,
      );

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

  testWidgets('says the signal is gone when fixes stop arriving', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(kPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // The failure this exists for, reproduced on an emulator before it was
    // written: the GPS feed was cut and the screen carried on saying
    // "Recording" with three bars, while the average pace inflated every
    // second against a distance that had stopped. Nothing errors when fixes
    // stop arriving, so `problem` stays null and nothing said a word.
    //
    // A trace of two points and then silence, which is what a tunnel looks
    // like: the recorder is still `recording` throughout -- the run was never
    // paused or stopped, it just went quiet.
    final start = DateTime(2026, 1, 1, 8);
    var clock = start;
    final recorder = FakeRunRecorder(
      interval: const Duration(milliseconds: 20),
      now: () => clock,
      trace: <RunPoint>[
        RunPoint(
          latitude: 51.5,
          longitude: -0.12,
          accuracyMeters: 5,
          timestamp: start,
        ),
        RunPoint(
          latitude: 51.5001,
          longitude: -0.12,
          accuracyMeters: 5,
          timestamp: start.add(const Duration(seconds: 1)),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RecordingScreen(recorder: recorder),
      ),
    );

    clock = start.add(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Recording'), findsOneWidget);
    expect(find.text('No signal'), findsNothing);

    // The trace is spent. Let the clock run past the staleness threshold.
    clock = clock.add(kStaleFixAfter + const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('No signal'), findsOneWidget);
    expect(find.text('Recording'), findsNothing);
    expect(
      recorder.status,
      RecorderStatus.recording,
      reason: 'the run has not stopped -- that is the whole point',
    );
  });

  testWidgets('elapsed time survives the app being backgrounded', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(kPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
    await tester.binding.setSurfaceSize(kPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

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

    expect(find.text('PACE /KM'), findsOneWidget);
    expect(find.text('AVG /KM'), findsOneWidget);
    // Enough of the canned trace has replayed for both to be real numbers.
    expect(find.text('--:--'), findsNothing);

    await recorder.stop();
  });

  testWidgets("shows today's session and progress toward it", (tester) async {
    await tester.binding.setSurfaceSize(kPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

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

    // The session block lives *below the fold*: the collapsed panel is sized to
    // the figures a runner reads mid-stride, and today's target is not one of
    // them. Reaching it means opening the sheet, which is the behaviour being
    // asserted as much as the content is.
    expect(find.text('Easy run'), findsNothing);

    // Dragged from a point inside the panel, not from the sheet widget's
    // centre: DraggableScrollableSheet lays out across the whole screen, so its
    // centre is over the map — and since the map became pannable (ADR-0031) a
    // drag there pans it rather than doing nothing. That this drag still opens
    // the sheet is the assertion that the two do not contend: the panel is an
    // opaque surface above the map, so a pointer landing on it is the sheet's
    // for the whole gesture.
    await tester.dragFrom(const Offset(196, 700), const Offset(0, -420));
    // Fixed pumps, not pumpAndSettle: the fake recorder emits on a repeating
    // timer, so the tree never goes quiet and settling waits forever. Same trap
    // as the busy-spinner one in this app's CLAUDE.md.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('Easy run'), findsOneWidget);
    expect(find.textContaining('of 5.00 km'), findsOneWidget);

    await recorder.stop();
  });

  testWidgets('an unplanned day shows no target block at all', (tester) async {
    await tester.binding.setSurfaceSize(kPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
    await tester.binding.setSurfaceSize(kPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
    await tester.binding.setSurfaceSize(kPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

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

  testWidgets('pause swaps the controls and the status label', (tester) async {
    await tester.binding.setSurfaceSize(kPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final recorder = FakeRunRecorder(
      interval: const Duration(milliseconds: 100),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RecordingScreen(recorder: recorder),
      ),
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Pause'));
    await tester.pump(); // deliver the status change
    await tester.pump();

    expect(find.text('Paused'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Resume'), findsOneWidget);
    // Lap goes with the running state: there is no lap in progress to cut.
    expect(find.text('Lap'), findsNothing);

    await recorder.stop(); // cancel the replay timer before teardown
  });

  group('a run cannot end from the running state', () {
    // The field test's own screenshot is the argument (`IMG_4685`): Lap, Pause
    // and Finish side by side, with Finish the filled one — the loudest, most
    // findable control on the screen, and the only one of the three that
    // cannot be undone. An hour of running was one mistap from over.

    Future<FakeRunRecorder> open(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(kPhone);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final recorder = FakeRunRecorder(
        interval: const Duration(milliseconds: 100),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: RecordingScreen(recorder: recorder),
        ),
      );
      return recorder;
    }

    testWidgets('Finish is absent while the run is going', (tester) async {
      final recorder = await open(tester);

      expect(find.text('Finish'), findsNothing);
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Lap'), findsOneWidget);

      await recorder.stop();
    });

    testWidgets('and appears once the runner pauses', (tester) async {
      final recorder = await open(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Pause'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Finish'), findsOneWidget);
      // Outlined, not filled. A runner who stopped at a crossing is far more
      // likely to be carrying on, so Resume is the one under the thumb and
      // ending the run is the one they have to look for.
      expect(find.widgetWithText(OutlinedButton, 'Finish'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Resume'), findsOneWidget);

      await recorder.stop();
    });

    testWidgets('and Finish, once reached, still finishes', (tester) async {
      final recorder = await open(tester);
      var finished = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: RecordingScreen(recorder: recorder, onFinish: () => finished++),
        ),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Pause'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Finish'));
      await tester.pump();
      await tester.pump();

      expect(finished, 1);
      expect(recorder.status, RecorderStatus.stopped);
    });
  });

  testWidgets('cancel confirms, then discards and fires onCancel', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(kPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

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
    await tester.binding.setSurfaceSize(kPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

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

  // ---------------------------------------------------------------------------
  // Layout at real device widths.
  //
  // **This group exists because three separate defects shipped past a green
  // suite.** Every test above ran at Flutter's default 800x600 surface, which is
  // nearly twice a phone's width: the readout row overflowed by 23px on an
  // iPhone and fitted comfortably in the harness, and the controls fell off the
  // bottom of a 375x667 screen while passing on a 600pt-tall one. A widget test
  // that never states a size is not testing a layout.
  // ---------------------------------------------------------------------------
  group('lays out on real phones', () {
    const sizes = <String, Size>{
      'iPhone SE (1st gen)': kSmallPhone,
      'iPhone SE (2nd/3rd gen)': Size(375, 667),
      'iPhone 15': kPhone,
      'iPhone 15 Pro Max': Size(430, 932),
    };

    for (final entry in sizes.entries) {
      testWidgets('${entry.key} — nothing overflows and the controls are '
          'reachable without scrolling', (tester) async {
        await tester.binding.setSurfaceSize(entry.value);
        addTearDown(() => tester.binding.setSurfaceSize(null));

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
              paces: TrainingPaces.fromRace(
                Distance.meters(5000),
                const Duration(minutes: 24, seconds: 30),
              ),
              onCancel: () {},
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 200));

        // A RenderFlex overflow is reported as a framework exception, and
        // silently swallowed unless something asks for it.
        expect(tester.takeException(), isNull);

        // Reachable means *on screen*, not merely built: a control the runner
        // has to scroll to find is one they cannot use mid-stride.
        //
        // Both states, because the row swaps: Lap and Pause while running, then
        // Resume and Finish once paused. The detent is a computed sum, so a
        // second row that laid out taller than the first would strand Finish
        // exactly the way a guessed fraction used to strand all three.
        final screen = Offset.zero & entry.value;
        void expectReachable(List<String> labels) {
          for (final label in labels) {
            final rect = tester.getRect(find.text(label));
            expect(
              screen.contains(rect.center),
              isTrue,
              reason: '$label is off-screen at ${entry.key}',
            );
          }
        }

        expectReachable(<String>['Lap', 'Pause']);

        await tester.tap(find.widgetWithText(FilledButton, 'Pause'));
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
        expectReachable(<String>['Resume', 'Finish']);

        // And the figure the screen exists for.
        expect(find.text('DISTANCE'), findsOneWidget);

        await recorder.stop();
      });
    }
  });
}
