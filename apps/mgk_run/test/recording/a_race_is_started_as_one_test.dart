import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_run_recorder.dart';
import 'package:mgk_run/src/features/recording/presentation/recording_screen.dart';
import 'package:mgk_run/src/features/recording/presentation/run_start_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// **A race is started as one** (ADR-0049, phase 2): chosen on the start
/// screen, counted down to on the run, and marked when it ends.
void main() {
  const half = 21097.5;

  Future<StartFix> nowhere() async => const StartFix.searching();

  Widget start({double? initial, ValueChanged<double?>? onRace}) => MaterialApp(
    theme: AppTheme.dark,
    home: RunStartScreen(
      onStart: () {},
      locate: nowhere,
      focus: null,
      initialRaceMeters: initial,
      onRaceChanged: onRace,
    ),
  );

  group('the start screen', () {
    testWidgets('offers Run or Race where a race can be recorded', (
      tester,
    ) async {
      final chosen = <double?>[];
      await tester.pumpWidget(start(onRace: chosen.add));
      await tester.pump();

      expect(find.text('Run'), findsOneWidget);
      expect(find.text('Race'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);

      await tester.tap(find.text('Race'));
      await tester.pump();
      expect(chosen.last, half);
      expect(find.text('Start the race'), findsOneWidget);
      expect(find.text('Half marathon'), findsOneWidget);
      expect(find.textContaining('reads a little long'), findsOneWidget);

      await tester.tap(find.text('10K'));
      await tester.pump();
      expect(chosen.last, 10000);

      await tester.tap(find.text('Run'));
      await tester.pump();
      expect(chosen.last, isNull);
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('opens on the race on race day', (tester) async {
      await tester.pumpWidget(start(initial: half, onRace: (_) {}));
      await tester.pump();

      expect(find.text('Start the race'), findsOneWidget);
      final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Half marathon'),
      );
      expect(chip.selected, isTrue);
    });

    testWidgets('has no choice where nothing could record a race', (
      tester,
    ) async {
      await tester.pumpWidget(start(initial: half));
      await tester.pump();

      expect(find.text('Race'), findsNothing);
      expect(find.text('Start the race'), findsNothing);
    });
  });

  group('the run', () {
    late DateTime clock;

    FakeRunRecorder recorderAt() {
      clock = DateTime(2026, 10, 11, 9, 31);
      return FakeRunRecorder(
        interval: const Duration(milliseconds: 20),
        now: () => clock,
      );
    }

    Future<void> advance(WidgetTester tester, int points) async {
      await tester.pump();
      for (var i = 0; i < points; i++) {
        clock = clock.add(const Duration(seconds: 3));
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    Widget racing(FakeRunRecorder recorder) => MaterialApp(
      theme: AppTheme.dark,
      home: RecordingScreen(recorder: recorder, raceMeters: half),
    );

    String column(WidgetTester tester, String prefix) => tester
        .widgetList<StatBlock>(find.byType(StatBlock))
        .firstWhere((s) => s.label.startsWith(prefix))
        .value;

    testWidgets('counts down to the course and projects a finish', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final recorder = recorderAt();
      await tester.pumpWidget(racing(recorder));

      // Before 400 m there is a countdown and no projection: the first
      // hundred metres are a start pen, not a pace.
      await advance(tester, 5);
      expect(double.parse(column(tester, 'TO GO')), closeTo(21.07, 0.05));
      expect(find.text('AVG /KM'), findsNothing);
      expect(column(tester, 'FINISH AT THIS PACE'), '--:--');

      await advance(tester, 100);
      final projected = column(tester, 'FINISH AT THIS PACE');
      expect(projected, matches(RegExp(r'^\d+:\d{2}:\d{2}$')));

      await recorder.stop();
    });

    testWidgets('keeps the controls on a small phone', (tester) async {
      const small = Size(320, 568);
      await tester.binding.setSurfaceSize(small);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final recorder = recorderAt();
      await tester.pumpWidget(racing(recorder));
      await advance(tester, 100);

      // The projection is the band block's height, and the detent reserved
      // that height: the control row is still on screen.
      final pause = find.text('Pause');
      expect(pause, findsOneWidget);
      expect(tester.getRect(pause).bottom, lessThanOrEqualTo(small.height));
      expect(
        tester.getRect(find.text('FINISH AT THIS PACE')).bottom,
        lessThan(tester.getRect(pause).top),
      );

      await recorder.stop();
    });
  });
}
