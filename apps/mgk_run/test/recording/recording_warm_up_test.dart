import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_run_recorder.dart';
import 'package:mgk_run/src/features/coaching/domain/pace_model.dart';
import 'package:mgk_run/src/features/coaching/domain/session_effort.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/recording/domain/run_point.dart';
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

  /// The brief, found by its prose rather than by an `RPE n` label.
  ///
  /// The label is gone — a number on a ten-point scale is a thing to convert
  /// before it is a thing to act on, and nobody mid-effort is converting — so
  /// the sentence is all the brief is. Read from [effortFor] rather than typed
  /// out, because the copy is the coaching domain's to change and this test is
  /// about where the block sits, not what it says.
  final Finder brief = find.text(effortFor(SessionKind.easy).feel);

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
    // The brief buys its height from the map, so it only rides above the fold
    // where there is map to sell. On a phone with room that is a good trade; at
    // 320x568 the panel reached 0.79 and left a strip barely taller than the
    // position marker. See [kBriefMaxCollapsedFraction].
    for (final (String name, Size size, bool expected)
        in <(String, Size, bool)>[
          ('iPhone 15', kPhone, true),
          ('iPhone 15 Pro Max', Size(430, 932), true),
          ('small phone', kSmallPhone, false),
        ]) {
      testWidgets('$name — brief above the fold: $expected', (
        WidgetTester tester,
      ) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));

        final FakeRunRecorder recorder = recorderAt();
        await tester.pumpWidget(planned(recorder));
        await advance(tester, kBeforeWarmUp);

        expect(tester.takeException(), isNull);
        expect(
          onScreen(tester, brief, size),
          expected,
          reason: expected
              ? 'the brief should be readable without opening the sheet'
              : 'a screen this short cannot afford to sell the map',
        );
        // Reachable either way — this is the whole reason the detent is summed
        // from its parts rather than guessed as a fraction. Finish is not on
        // this list: it is not on the screen at all until the runner pauses.
        for (final String label in <String>['Lap', 'Pause']) {
          expect(
            onScreen(tester, find.text(label), size),
            isTrue,
            reason: '$label is off-screen at $name',
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
        onScreen(tester, brief, kPhone),
        isFalse,
        reason: 'the map should have the height back',
      );

      await recorder.stop();
    });
  });

  group('the third column', () {
    /// The column's label and value, whichever of the two labels it is wearing.
    ///
    /// Read off the widget rather than the rendered text on purpose: the label
    /// is handed over as `TO GO km`, carrying the unit exactly as the units
    /// layer spells it, and it is [SectionLabel] that uppercases for display.
    /// Asserting against the rendered form would be asserting against the wrong
    /// string.
    (String, String) column(WidgetTester tester) {
      final block = tester
          .widgetList<StatBlock>(find.byType(StatBlock))
          .firstWhere(
            (StatBlock s) =>
                s.label.startsWith('TO GO') || s.label.startsWith('PAST'),
          );
      return (block.label.toUpperCase(), block.value);
    }

    String toGo(WidgetTester tester) => column(tester).$2;

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

    testWidgets('counts down against what the runner was told', (
      WidgetTester tester,
    ) async {
      // A 7 km session reads as "4 mi" on Plan — `prescribedValue` rounds in
      // the runner's own unit, because a number that is round in a unit they do
      // not think in is not round to them (ADR-0011). The countdown converted
      // the *stored* 7,000 m instead, so the same session opened at 4.35 under
      // a plan that said 4: two numbers for one session, and the wrong one on
      // the screen they are holding while running.
      await tester.binding.setSurfaceSize(kPhone);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final FakeRunRecorder recorder = recorderAt();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: RecordingScreen(
            recorder: recorder,
            unit: UnitSystem.imperial,
            plannedSession: const PlannedSession(
              weekday: DateTime.monday,
              kind: SessionKind.easy,
              distanceMeters: 7000,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(column(tester), ('TO GO MI', '4.00'));

      await recorder.stop();
    });

    testWidgets('goes past the prescription rather than stopping at it', (
      WidgetTester tester,
    ) async {
      // A prescription is a suggestion, never a floor and never a ceiling. The
      // column used to clamp at zero under a label still reading TO GO, so
      // running further froze it at `0.00` — a suggestion rendered as a meter
      // that fills and then reads as done-or-failed either way.
      await tester.binding.setSurfaceSize(kPhone);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // A short, quick trace, so a kilometre — the smallest prescription there
      // is — is comfortably passed inside the test.
      final DateTime traceStart = DateTime(2026, 1, 1, 8);
      final FakeRunRecorder recorder = FakeRunRecorder(
        interval: const Duration(milliseconds: 20),
        now: () => clock,
        trace: <RunPoint>[
          for (int i = 0; i <= 14; i++)
            RunPoint(
              // 0.001 degrees of latitude is ~111.19 m, so fourteen hops is
              // about 1,557 m against a 1,000 m session.
              latitude: i * 0.001,
              longitude: 0,
              accuracyMeters: 5,
              timestamp: traceStart.add(Duration(seconds: i * 3)),
            ),
        ],
      );
      clock = traceStart;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: RecordingScreen(
            recorder: recorder,
            plannedSession: const PlannedSession(
              weekday: DateTime.monday,
              kind: SessionKind.easy,
              distanceMeters: 1000,
            ),
          ),
        ),
      );

      await advance(tester, 5);
      expect(column(tester).$1, 'TO GO KM');

      await advance(tester, 12);
      final (String label, String value) = column(tester);
      expect(label, 'PAST KM', reason: 'the label carries the change');
      expect(
        double.parse(value),
        greaterThan(0),
        reason: 'and the figure counts up again rather than freezing at 0.00',
      );

      await recorder.stop();
    });
  });
}
