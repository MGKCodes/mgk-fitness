import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_units/mgk_units.dart';
import 'package:mgk_run/src/features/coaching/domain/pace_model.dart';
import 'package:mgk_run/src/features/coaching/domain/session_status.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/presentation/today_card.dart';

void main() {
  TrainingPaces paces() => TrainingPaces.fromRace(
    Distance.meters(5000),
    const Duration(minutes: 22),
  );

  const session = PlannedSession(
    weekday: DateTime.monday,
    kind: SessionKind.threshold,
    distanceMeters: 8000,
  );

  Future<void> pump(WidgetTester tester, Widget card) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: card)));

  testWidgets('a planned session shows details and fires actions', (
    tester,
  ) async {
    var done = false;
    var skipped = false;
    await pump(
      tester,
      TodayCard(
        session: session,
        phase: Phase.build,
        status: SessionStatus.planned,
        paces: paces(),
        onComplete: () => done = true,
        onSkip: () => skipped = true,
      ),
    );

    expect(find.text('Threshold'), findsOneWidget);
    expect(find.text('8.0 km'), findsOneWidget);
    expect(find.textContaining('target'), findsOneWidget);

    await tester.tap(find.text('Mark done'));
    expect(done, isTrue);
    await tester.tap(find.text('Skip'));
    expect(skipped, isTrue);
  });

  testWidgets('completed shows Done and hides the actions', (tester) async {
    var reset = false;
    await pump(
      tester,
      TodayCard(
        session: session,
        phase: Phase.build,
        status: SessionStatus.completed,
        paces: paces(),
        onReset: () => reset = true,
      ),
    );

    expect(find.text('Done'), findsOneWidget);
    expect(find.text('Mark done'), findsNothing);
    await tester.tap(find.text('Undo'));
    expect(reset, isTrue);
  });

  testWidgets('skipped shows Skipped', (tester) async {
    await pump(
      tester,
      TodayCard(
        session: session,
        phase: Phase.build,
        status: SessionStatus.skipped,
        paces: paces(),
      ),
    );
    expect(find.text('Skipped'), findsOneWidget);
  });

  testWidgets('a rest day shows no session actions', (tester) async {
    await pump(
      tester,
      const TodayCard(
        session: null,
        phase: Phase.base,
        status: SessionStatus.planned,
      ),
    );
    expect(find.text('Rest day'), findsOneWidget);
    expect(find.text('Mark done'), findsNothing);
  });
}
