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
const Size kSmallPhone = Size(320, 568);

/// The demo trace lays a point every 3 seconds and covers ~5.7 m each, so 100
/// points is comfortably past both warm-up gates and 5 is comfortably inside
/// them.
const int kBeforeWarmUp = 5;
const int kAfterWarmUp = 100;

void main() {
  late DateTime clock;

  FakeRunRecorder recorderAt() {
    clock = DateTime(2026, 1, 1, 8);
    return FakeRunRecorder(
      interval: const Duration(milliseconds: 20),
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

  Widget planned(FakeRunRecorder recorder) => MaterialApp(
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
    ),
  );

  /// On screen, not merely built. The sheet's below-the-fold content is in the
  /// tree the whole time, so `findsOneWidget` cannot tell the two states apart.
  bool onScreen(WidgetTester tester, Finder finder, Size surface) {
    if (finder.evaluate().isEmpty) return false;
    return (Offset.zero & surface).contains(tester.getRect(finder).center);
  }

  group('the verdict waits until the run has earned one', () {
    testWidgets('before the warm-up it says it is still looking', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(kPhone);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final FakeRunRecorder recorder = recorderAt();
      await tester.pumpWidget(planned(recorder));
      await advance(tester, kBeforeWarmUp);

      expect(find.text('FINDING YOUR PACE'), findsOneWidget);
      // The specific failure this gates: a standstill start makes the first
      // rolling window an acceleration, so an ungated screen opens every run
      // by telling the runner they are too slow.
      expect(find.text('PICK IT UP'), findsNothing);
      expect(find.text('ON TARGET'), findsNothing);
      expect(find.text('EASE OFF'), findsNothing);

      await recorder.stop();
    });

    testWidgets('after it, the band speaks', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(kPhone);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final FakeRunRecorder recorder = recorderAt();
      await tester.pumpWidget(planned(recorder));
      await advance(tester, kAfterWarmUp);

      expect(find.text('FINDING YOUR PACE'), findsNothing);
      // Which verdict depends on the trace; that one arrives is the claim.
      final Iterable<String> verdicts = <String>[
        'PICK IT UP',
        'ON TARGET',
        'EASE OFF',
      ].where((String v) => find.text(v).evaluate().isNotEmpty);
      expect(verdicts, isNotEmpty);

      await recorder.stop();
    });
  });

  group('the brief rides above the fold only while the verdict is held', () {
    for (final MapEntry<String, Size> entry in <String, Size>{
      'iPhone 15': kPhone,
      'small phone': kSmallPhone,
    }.entries) {
      testWidgets('${entry.key} — visible early, and Finish still reachable', (
        WidgetTester tester,
      ) async {
        await tester.binding.setSurfaceSize(entry.value);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final FakeRunRecorder recorder = recorderAt();
        await tester.pumpWidget(planned(recorder));
        await advance(tester, kBeforeWarmUp);

        expect(tester.takeException(), isNull);
        expect(
          onScreen(tester, find.textContaining('RPE'), entry.value),
          isTrue,
          reason: 'the brief should be readable without opening the sheet',
        );
        // The taller panel must not cost the controls their place — this is
        // the whole reason the detent is summed from its parts.
        for (final String label in <String>['Lap', 'Pause', 'Finish']) {
          expect(
            onScreen(tester, find.text(label), entry.value),
            isTrue,
            reason: '$label is off-screen at ${entry.key} with the brief up',
          );
        }

        await recorder.stop();
      });
    }

    testWidgets('and drops below the fold once the band speaks', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(kPhone);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final FakeRunRecorder recorder = recorderAt();
      await tester.pumpWidget(planned(recorder));
      await advance(tester, kAfterWarmUp);

      expect(
        onScreen(tester, find.textContaining('RPE'), kPhone),
        isFalse,
        reason: 'the map should have the height back',
      );

      await recorder.stop();
    });
  });

  group('the third column', () {
    /// Matched case-insensitively on purpose: the label is handed over as
    /// `TO GO km`, carrying the unit exactly as the units layer spells it, and
    /// it is [SectionLabel] that uppercases for display. Asserting against the
    /// rendered form here would be asserting against the wrong string.
    String toGo(WidgetTester tester) => tester
        .widgetList<StatBlock>(find.byType(StatBlock))
        .firstWhere((StatBlock s) => s.label.toUpperCase() == 'TO GO KM')
        .value;

    testWidgets('counts down to the session target on a planned run', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(kPhone);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final FakeRunRecorder recorder = recorderAt();
      await tester.pumpWidget(planned(recorder));
      await advance(tester, kBeforeWarmUp);

      // Present from the opening metres, which is the point of the swap: the
      // average it replaced reserved a third of the row for `--:--`.
      expect(find.text('TO GO KM'), findsOneWidget);
      expect(find.text('AVG /KM'), findsNothing);

      final double early = double.parse(toGo(tester));
      expect(early, lessThan(5.00));

      await advance(tester, kAfterWarmUp);
      expect(double.parse(toGo(tester)), lessThan(early));

      await recorder.stop();
    });

    testWidgets('stays the average when there is no plan to count down to', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(kPhone);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final FakeRunRecorder recorder = recorderAt();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: RecordingScreen(recorder: recorder),
        ),
      );
      await advance(tester, kAfterWarmUp);

      expect(find.text('AVG /KM'), findsOneWidget);
      expect(find.text('TO GO KM'), findsNothing);

      await recorder.stop();
    });
  });
}
