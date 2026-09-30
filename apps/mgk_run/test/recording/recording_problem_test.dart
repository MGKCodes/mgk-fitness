import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_run_recorder.dart';
import 'package:mgk_run/src/features/coaching/domain/pace_model.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/recording/domain/run_recorder.dart';
import 'package:mgk_run/src/features/recording/presentation/recording_screen.dart';
import 'package:mgk_units/mgk_units.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// A phone, not Flutter's default 800x600 surface — see recording_screen_test.
const Size kPhone = Size(393, 852);

/// Counts how many times the screen asked the recorder to start.
class _CountingRecorder extends FakeRunRecorder {
  _CountingRecorder(RecorderProblem problem) : super(failsWith: problem);

  int starts = 0;

  @override
  Future<void> start() async {
    starts++;
    await super.start();
  }
}

/// The five ways recording can fail, and what each one offers to do about it.
///
/// `RecorderProblem` distinguishes two refusals on purpose — one "can be asked
/// for again", the other says "re-asking does nothing, Settings only" — and the
/// panel used to collapse them, sending both to `openAppSettings`. For the
/// re-askable one that is the wrong remedy and much the worse path: leave the
/// app, find Run in a list, find Location, change it, come back, start the run
/// again, against one tap that re-shows the prompt just dismissed.
void main() {
  Future<_CountingRecorder> pumpProblem(
    WidgetTester tester,
    RecorderProblem problem,
  ) async {
    await tester.binding.setSurfaceSize(kPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final _CountingRecorder recorder = _CountingRecorder(problem);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RecordingScreen(
          recorder: recorder,
          // A planned session, so the band would exist if nothing had gone
          // wrong — otherwise "no band" would pass for the wrong reason.
          plannedSession: const PlannedSession(
            weekday: DateTime.monday,
            kind: SessionKind.easy,
            distanceMeters: 5000,
          ),
          paces: TrainingPaces.fromRace(
            Distance.meters(5000),
            const Duration(minutes: 24, seconds: 30),
          ),
        ),
      ),
    );
    await tester.pump();
    return recorder;
  }

  testWidgets('a refusal that can be asked again offers to ask again', (
    WidgetTester tester,
  ) async {
    final _CountingRecorder recorder = await pumpProblem(
      tester,
      RecorderProblem.permissionDenied,
    );

    expect(find.text('Continue'), findsOneWidget);
    expect(
      find.text('Open Settings'),
      findsNothing,
      reason: 'Settings is the long way round when the prompt still works',
    );

    final int before = recorder.starts;
    await tester.tap(find.text('Continue'));
    await tester.pump();
    expect(recorder.starts, before + 1);

    await recorder.stop();
  });

  testWidgets('a permanent refusal offers Settings, because asking will not '
      'work', (WidgetTester tester) async {
    final _CountingRecorder recorder = await pumpProblem(
      tester,
      RecorderProblem.permissionDeniedForever,
    );

    expect(find.text('Open Settings'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);

    await recorder.stop();
  });

  testWidgets(
    // EDGE-16: approximate location (iOS Precise Location off, or the
    // Android equivalent) is granted permission, so there is no in-app
    // prompt that could fix it — Settings is the only remedy, the same as
    // a permanent permission refusal.
    'reduced accuracy offers Settings too, and names Precise Location',
    (WidgetTester tester) async {
      final _CountingRecorder recorder = await pumpProblem(
        tester,
        RecorderProblem.reducedAccuracy,
      );

      expect(find.text('Open Settings'), findsOneWidget);
      expect(find.text('Allow location'), findsNothing);
      expect(find.textContaining('Precise Location'), findsOneWidget);

      await recorder.stop();
    },
  );

  testWidgets('a device-wide switch offers no button at all, and says where '
      'to go', (WidgetTester tester) async {
    final _CountingRecorder recorder = await pumpProblem(
      tester,
      RecorderProblem.locationServicesOff,
    );

    // Neither button can reach it: openAppSettings lands on Run's own page,
    // which does not hold the device's Location Services switch.
    expect(find.text('Open Settings'), findsNothing);
    expect(find.text('Continue'), findsNothing);
    expect(find.textContaining('Location Services are off'), findsOneWidget);

    await recorder.stop();
  });

  testWidgets('a source that simply failed offers nothing, and says it usually '
      'clears', (WidgetTester tester) async {
    final _CountingRecorder recorder = await pumpProblem(
      tester,
      RecorderProblem.locationFailed,
    );

    expect(find.text('Open Settings'), findsNothing);
    expect(find.text('Continue'), findsNothing);
    expect(find.textContaining('clears on its own'), findsOneWidget);

    await recorder.stop();
  });

  testWidgets('the coach says nothing while there is nothing to say it about', (
    WidgetTester tester,
  ) async {
    final _CountingRecorder recorder = await pumpProblem(
      tester,
      RecorderProblem.permissionDenied,
    );

    // The panel has just said nothing is being tracked. A pace rail underneath
    // it is a second, contradictory answer to the same question — and
    // FINDING YOUR PACE claims to be looking for a pace on a run that never
    // started.
    expect(find.text('FINDING YOUR PACE'), findsNothing);
    expect(find.textContaining('NO FASTER THAN'), findsNothing);
    expect(find.byType(PaceBandMeter), findsNothing);
    // The message itself is still there, and so is the way out.
    expect(find.textContaining('Nothing is being tracked'), findsOneWidget);
    expect(find.text('Finish'), findsOneWidget);

    await recorder.stop();
  });

  testWidgets('every problem state keeps Finish reachable', (
    WidgetTester tester,
  ) async {
    for (final RecorderProblem problem in RecorderProblem.values) {
      final _CountingRecorder recorder = await pumpProblem(tester, problem);

      // A runner who cannot record still has to be able to leave the screen.
      final Rect finish = tester.getRect(find.text('Finish'));
      expect(
        (Offset.zero & kPhone).contains(finish.center),
        isTrue,
        reason: 'Finish is off-screen on $problem',
      );
      expect(tester.takeException(), isNull);

      await recorder.stop();
    }
  });
}
