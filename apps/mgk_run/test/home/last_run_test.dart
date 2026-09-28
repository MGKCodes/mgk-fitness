import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_access.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/home/presentation/home_last_run.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

/// **Where the paid line is drawn, and what it must never cross.**
///
/// The subscription buys a coach, not a tracker. So a runner's own distance,
/// pace and time are never behind it — an app that hides your own pace until
/// you pay is not a running app — and what is bought is the coach's *reading*
/// of them, which only exists at all when there is a session to read them
/// against.
///
/// The tests below are mostly about the free side, because that is the side
/// that can be got wrong in a way nobody notices: a gate that leaks is caught
/// immediately, and a gate that quietly swallows a runner's own numbers looks
/// like a design decision.
void main() {
  final ran = RunSummary(
    startedAt: DateTime(2026, 8, 24, 6, 40),
    duration: const Duration(minutes: 46, seconds: 12),
    distanceMeters: 8600,
    avgPaceSecondsPerKm: 322,
  );

  final against = PlannedAgainst(
    session: const PlannedSession(
      weekday: DateTime.monday,
      kind: SessionKind.threshold,
      distanceMeters: 8900,
    ),
    targetPace: Pace.secondsPerKilometer(310),
  );

  Future<void> pump(
    WidgetTester tester, {
    RunSummary? run,
    PlannedAgainst? plan,
    CoachAccess access = CoachAccess.free,
    VoidCallback? onUpgrade,
  }) async {
    await tester.binding.setSurfaceSize(const Size(393, 620));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: LastRunCard(
            run: run,
            unit: UnitSystem.metric,
            against: plan,
            access: access,
            onUpgrade: onUpgrade,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('free', () {
    testWidgets('keeps the runner’s own numbers whole', (tester) async {
      await pump(tester, run: ran, plan: against);

      // Never gated. These are facts about what somebody did, and they are the
      // free product rather than a preview of it.
      expect(find.text('8.6 km'), findsOneWidget);
      expect(find.text('5:22 /km'), findsOneWidget);
      expect(find.text('46:12'), findsOneWidget);
    });

    testWidgets('withholds the comparison, and says what it is', (
      tester,
    ) async {
      await pump(tester, run: ran, plan: against);

      expect(find.text('Upgrade to see this stat'), findsOneWidget);
      // The heading stays, so the offer is a proposition rather than a mystery
      // — a blurred rectangle says you are missing something without saying
      // what of, which is a worse offer and a ruder one.
      expect(find.text('AGAINST THE PLAN'), findsOneWidget);
      // But nothing the coach asked for leaks through it.
      expect(find.textContaining('Threshold'), findsNothing);
      expect(find.text('9 km'), findsNothing);
      expect(find.text('5:10 /km'), findsNothing);
      expect(find.textContaining('Session done'), findsNothing);
    });

    testWidgets('does not nag a runner with no plan', (tester) async {
      // No session means no comparison to sell. An upgrade prompt here would be
      // an advert on a screen with nothing to advertise against, which is the
      // "plan-shaped hole on a free screen" ADR-0019 names as its own
      // counter-signal.
      await pump(tester, run: ran);

      expect(find.text('Upgrade to see this stat'), findsNothing);
      expect(find.text('AGAINST THE PLAN'), findsNothing);
      expect(find.text('8.6 km'), findsOneWidget);
    });

    testWidgets('offers the explanation only when there is one to open', (
      tester,
    ) async {
      await pump(tester, run: ran, plan: against);
      expect(find.text('See what a coach adds'), findsNothing);

      await pump(tester, run: ran, plan: against, onUpgrade: () {});
      expect(find.text('See what a coach adds'), findsOneWidget);
    });
  });

  group('subscribed', () {
    testWidgets('reads the run against what was asked', (tester) async {
      await pump(
        tester,
        run: ran,
        plan: against,
        access: CoachAccess.subscribed,
      );

      expect(find.text('Asked'), findsOneWidget);
      expect(find.text('Ran'), findsOneWidget);
      // The ask is a prescription and rounds; the run is an achievement and
      // does not.
      expect(find.textContaining('9 km'), findsOneWidget);
      expect(find.textContaining('8.6 km'), findsWidgets);
      expect(find.text('Upgrade to see this stat'), findsNothing);
    });

    testWidgets('says whether the session was answered, not how well', (
      tester,
    ) async {
      await pump(
        tester,
        run: ran,
        plan: against,
        access: CoachAccess.subscribed,
      );

      // 8.6 against 8.9 is inside `fulfils`' band, so it counts. The wording is
      // about the session rather than about the runner — the interpretation is
      // the coach's job, and it has a conversation to do it in.
      expect(find.text('Session done'), findsOneWidget);
      for (final judgement in const <String>[
        'Well done',
        'Good',
        'Poor',
        'Failed',
        'Missed',
      ]) {
        expect(find.textContaining(judgement), findsNothing);
      }
    });

    testWidgets('drops the pace row rather than guessing one', (tester) async {
      // A profile with no time trial has no derived paces, and inventing a
      // target is the thing this codebase refuses to do elsewhere.
      await pump(
        tester,
        run: ran,
        plan: PlannedAgainst(session: against.session),
        access: CoachAccess.subscribed,
      );

      expect(find.text('Asked'), findsOneWidget);
      expect(find.textContaining('5:10 /km'), findsNothing);
    });
  });

  testWidgets('before the first run it says what will land here', (
    tester,
  ) async {
    await pump(tester);

    expect(find.textContaining('lands here'), findsOneWidget);
    expect(find.textContaining('0.0'), findsNothing);
  });
}
