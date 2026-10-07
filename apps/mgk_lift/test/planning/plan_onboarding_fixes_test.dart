// The plan onboarding as a paying lifter met it on 2026-10-07: questions out
// of order, "No connection" while it worked, a 4-day plan for 3 days asked,
// press-ups for somebody with a gym, and answers lost on every failure. Each
// test below is one of those, pinned.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/coaching/presentation/plan_surface.dart';
import 'package:mgk_lift/src/features/planning/domain/coach_planner.dart';
import 'package:mgk_lift/src/features/planning/domain/intake_flow.dart';
import 'package:mgk_lift/src/features/planning/domain/plan_builder.dart';
import 'package:mgk_lift/src/features/planning/domain/plan_intake.dart';
import 'package:mgk_lift/src/features/planning/domain/plan_proposal.dart';
import 'package:mgk_lift/src/features/planning/domain/plan_template.dart';
import 'package:mgk_lift/src/features/planning/presentation/plan_intake_screen.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';

/// Replies with [asking] as the question asked, and extracts [extract].
class _Planner implements CoachPlanner {
  _Planner({this.extract = const PlanIntake(), this.asking});

  final PlanIntake extract;
  final String? asking;
  final List<IntakeProgress> sent = <IntakeProgress>[];

  @override
  Future<IntakeTurn> intake({
    required IntakeProgress progress,
    required List<PlannerTurn> history,
  }) async {
    sent.add(progress);
    return IntakeTurn(reply: 'Noted.', extracted: extract, asking: asking);
  }

  @override
  Future<PlanProposal> plan({
    required PlanIntake intake,
    required List<int> weekdays,
    required List<String> catalogue,
    List<String> violations = const <String>[],
  }) => throw UnimplementedError();

  @override
  Future<SwapProposal> swap({
    required String message,
    required Session session,
  }) => throw UnimplementedError();
}

void main() {
  group('the weekdays follow the count', () {
    test('"3 days" builds three days, not a fixed four', () {
      expect(const PlanIntake(daysPerWeek: 3).weekdaysOrDefault, <int>[
        1,
        3,
        5,
      ]);
      expect(const PlanIntake(daysPerWeek: 2).weekdaysOrDefault, <int>[1, 4]);
      expect(const PlanIntake(daysPerWeek: 5).weekdaysOrDefault, <int>[
        1,
        2,
        3,
        4,
        5,
      ]);
    });

    test('named days win, cleaned the way the database needs them', () {
      // `lift.plans` refuses no days or more than seven, and these come from
      // a model reading prose.
      expect(
        const PlanIntake(
          daysPerWeek: 3,
          availableWeekdays: <int>[5, 1, 1, 9, 3],
        ).weekdaysOrDefault,
        <int>[1, 3, 5],
      );
      expect(
        const PlanIntake(
          daysPerWeek: 2,
          availableWeekdays: <int>[],
        ).weekdaysOrDefault,
        <int>[1, 4],
      );
    });
  });

  group('equipment is read from what was said', () {
    test('the option labels map as they always did', () {
      expect(Equipment.fromAnswer('A full gym'), Equipment.fullGym);
      expect(Equipment.fromAnswer('Home, with weights'), Equipment.homeWeights);
      expect(Equipment.fromAnswer('Minimal kit'), Equipment.minimalKit);
      expect(Equipment.fromAnswer('Bodyweight only'), Equipment.bodyweight);
    });

    test('the coach\'s wording and typed answers are not bodyweight', () {
      // Everything but the exact labels used to fall through to bodyweight,
      // so "commercial gym" was planned from press-ups.
      expect(Equipment.fromAnswer('full gym'), Equipment.fullGym);
      expect(Equipment.fromAnswer('commercial gym'), Equipment.fullGym);
      expect(Equipment.fromAnswer('a rack and a barbell'), Equipment.fullGym);
      expect(Equipment.fromAnswer('home gym'), Equipment.homeWeights);
      expect(Equipment.fromAnswer('dumbbells and bands'), Equipment.minimalKit);
      expect(Equipment.fromAnswer('no equipment'), Equipment.bodyweight);
    });

    test('declined or unreadable is a full gym, not nothing', () {
      expect(Equipment.fromAnswer(''), Equipment.fullGym);
      expect(Equipment.fromAnswer('Prefer not to say'), Equipment.fullGym);
    });
  });

  test('a template plan\'s slots carry the plan\'s id', () async {
    // `lift.plan_slots` keys on the id alone, across every lifter. Template
    // ids were `upper-horizontal-press`, so the second template plan saved
    // anywhere collided with the first.
    Future<PlanProposal> failing({
      required PlanIntake intake,
      required List<int> weekdays,
      required List<String> catalogue,
      List<String> violations = const <String>[],
    }) => throw StateError('no network');

    final a = await PlanBuilder(propose: failing).build(
      id: 'plan-a',
      intake: const PlanIntake(),
      weekdays: const <int>[1, 2, 4, 5],
      catalogue: const <String>[],
    );
    final b = await PlanBuilder(propose: failing).build(
      id: 'plan-b',
      intake: const PlanIntake(),
      weekdays: const <int>[1, 2, 4, 5],
      catalogue: const <String>[],
    );

    expect(a.fromCoach, isFalse);
    final idsA = {for (final d in a.plan.slots.values) ...d.map((s) => s.id)};
    final idsB = {for (final d in b.plan.slots.values) ...d.map((s) => s.id)};
    expect(idsA, isNotEmpty);
    expect(idsA.every((id) => id.startsWith('plan-a-')), isTrue);
    expect(idsA.intersection(idsB), isEmpty);
  });

  group('the intake asks in one order', () {
    test('what is still open is listed in the order it is asked', () {
      const p = IntakeProgress(
        plan: PlanIntake(daysPerWeek: 3),
        declined: <IntakeField>{IntakeField.equipment},
      );
      expect(p.unsettled, <IntakeField>[
        IntakeField.injuries,
        IntakeField.goal,
      ]);
    });

    test('a coach turn names its field by the enum\'s own name', () {
      expect(IntakeField.named('equipment'), IntakeField.equipment);
      expect(IntakeField.named('done'), isNull);
      expect(IntakeField.named(null), isNull);
    });

    testWidgets('the options under a question are for that question', (
      tester,
    ) async {
      // The coach decided its question from one list and the app its options
      // from another, so the two could disagree. The options now follow what
      // the coach says it asked.
      final planner = _Planner(
        extract: const PlanIntake(daysPerWeek: 3),
        asking: 'goal',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PlanIntakeScreen(
            planner: planner,
            opener: IntakeField.days.question,
          ),
        ),
      );
      await tester.tap(find.text('3 days'));
      await tester.pumpAndSettle();

      expect(find.text('Build muscle'), findsOneWidget);
      expect(find.text('A full gym'), findsNothing);
    });

    testWidgets('and fall back to the first open field when it says nothing', (
      tester,
    ) async {
      final planner = _Planner(extract: const PlanIntake(daysPerWeek: 3));
      await tester.pumpWidget(
        MaterialApp(
          home: PlanIntakeScreen(
            planner: planner,
            opener: IntakeField.days.question,
          ),
        ),
      );
      await tester.tap(find.text('3 days'));
      await tester.pumpAndSettle();

      expect(find.text('A full gym'), findsOneWidget);
    });

    testWidgets('what was declined is sent with the next turn', (tester) async {
      final planner = _Planner(extract: const PlanIntake(daysPerWeek: 3));
      await tester.pumpWidget(
        MaterialApp(
          home: PlanIntakeScreen(
            planner: planner,
            opener: IntakeField.days.question,
            initialKnown: const IntakeProgress(
              plan: PlanIntake(daysPerWeek: 3),
            ),
          ),
        ),
      );
      // Opened on equipment, because days is known.
      await tester.tap(find.text('Prefer not to say'));
      await tester.pumpAndSettle();

      expect(planner.sent.single.declined, contains(IntakeField.equipment));
    });

    testWidgets('kept answers open the intake ready to build', (tester) async {
      // What a failed build leaves behind: the shell seeds it back in.
      await tester.pumpWidget(
        MaterialApp(
          home: PlanIntakeScreen(
            planner: _Planner(),
            opener: 'I still have your answers from last time.',
            initialKnown: const IntakeProgress(
              plan: PlanIntake(
                daysPerWeek: 3,
                equipment: 'A full gym',
                injuryNotes: 'none',
                goal: 'Build muscle',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Build my plan'), findsOneWidget);
    });
  });

  group('building is said, not blamed on the signal', () {
    testWidgets('no plan yet, building: progress, no connection note', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: PlanSurface(isEntitled: true, isBuilding: true)),
        ),
      );
      expect(find.text('Building your plan…'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.textContaining('needs a connection'), findsNothing);
    });

    testWidgets('a real missing connection still says so', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: PlanSurface(isEntitled: true))),
      );
      expect(find.textContaining('needs a connection'), findsOneWidget);
    });
  });

  test('a refused save is not called a connection problem', () {
    expect(PlanFailure.notSaved.message, isNot(contains('reach')));
    expect(PlanFailure.serverError.message, contains('our side'));
  });
}
