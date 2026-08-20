import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_run_recorder.dart';
import 'package:mgk_run/src/features/recording/presentation/recording_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// A phone, not Flutter's default 800x600 surface — see recording_screen_test.
const Size kPhone = Size(393, 852);

const String kTick = 'HapticFeedbackType.selectionClick';
const String kCommit = 'HapticFeedbackType.mediumImpact';
const String kProblem = 'HapticFeedbackType.heavyImpact';

/// Records what the screen asks the platform to feel like.
List<String> recordHaptics(WidgetTester tester) {
  final List<String> fired = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        fired.add((call.arguments as String?) ?? 'vibrate');
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return fired;
}

/// The one surface in the suite where a haptic the runner did not ask for is
/// justified: mid-stride, they cannot read the screen.
///
/// Everything else here answers a finger. See [AppHaptics] for the rule.
void main() {
  late DateTime clock;

  FakeRunRecorder recorderAt({int? traceLength}) {
    clock = DateTime(2026, 1, 1, 8);
    return FakeRunRecorder(
      interval: const Duration(milliseconds: 20),
      trace: traceLength == null
          ? null
          : demoRunTrace().take(traceLength).toList(),
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

  Future<void> pumpRun(WidgetTester tester, FakeRunRecorder recorder) async {
    await tester.binding.setSurfaceSize(kPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: RecordingScreen(recorder: recorder),
      ),
    );
  }

  testWidgets('a kilometre turning over is felt, once each', (
    WidgetTester tester,
  ) async {
    final List<String> fired = recordHaptics(tester);
    final FakeRunRecorder recorder = recorderAt();
    await pumpRun(tester, recorder);

    // The canned loop covers ~5.2 m a fix, so 440 fixes is a little over two
    // kilometres — two milestones, and not one per fix inside them.
    await advance(tester, 440);

    expect(
      fired.where((String h) => h == kCommit).length,
      2,
      reason: 'one per whole kilometre, not one per fix',
    );

    await recorder.stop();
  });

  testWidgets('the signal going is felt on the edge, not every second', (
    WidgetTester tester,
  ) async {
    final FakeRunRecorder recorder = recorderAt(traceLength: 60);
    await pumpRun(tester, recorder);
    // Recorded only from here, so the milestone haptics do not muddy the count.
    final List<String> fired = recordHaptics(tester);

    await advance(tester, 60);
    expect(fired.where((String h) => h == kProblem), isEmpty);

    // The trace is spent and the clock keeps running: fixes have stopped while
    // the run is still recording.
    await advance(tester, 40);

    expect(
      fired.where((String h) => h == kProblem).length,
      1,
      reason: 'announced as it goes, not for every second it stays gone',
    );

    await recorder.stop();
  });

  testWidgets('a lap confirms itself, and a mistap does not', (
    WidgetTester tester,
  ) async {
    final FakeRunRecorder recorder = recorderAt();
    await pumpRun(tester, recorder);

    // Before any distance, Lap is a mistap: nothing to mark.
    final List<String> fired = recordHaptics(tester);
    await tester.tap(find.text('Lap'));
    await tester.pump();
    expect(
      fired.where((String h) => h == kCommit),
      isEmpty,
      reason: 'confirming a lap that did not happen is worse than silence',
    );

    await advance(tester, 60);
    fired.clear();
    await tester.tap(find.text('Lap'));
    await tester.pump();
    expect(fired.where((String h) => h == kCommit).length, 1);

    await recorder.stop();
  });

  testWidgets('pausing ticks, because it is often done without looking', (
    WidgetTester tester,
  ) async {
    final FakeRunRecorder recorder = recorderAt();
    await pumpRun(tester, recorder);
    await advance(tester, 10);

    final List<String> fired = recordHaptics(tester);
    await tester.tap(find.text('Pause'));
    await tester.pump();

    expect(fired.where((String h) => h == kTick).length, 1);

    await recorder.stop();
  });
}
