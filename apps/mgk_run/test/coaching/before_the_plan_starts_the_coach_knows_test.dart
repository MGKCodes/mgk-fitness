import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/data/plan_store.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_brief.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_headline.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_shape.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/presentation/plan_screen.dart';

/// Before a plan's first Monday (ADR-0034) the coach was told the runner was
/// "in week 1 of 16", and the Plan tab's header said "112 days · week 1 of
/// 16" over a week headed "Starts Monday 5 Oct". Week 1 had not begun.
void main() {
  final wednesday = DateTime(2026, 9, 30);
  final monday = DateTime(2026, 10, 5);

  RunnerProfile block() => RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: DateTime(2027, 1, 20),
    currentWeeklyMeters: 40000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 3, 5, 6},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );

  RunnerProfile horizon() => const RunnerProfile(
    goalDistanceMeters: 21097.5,
    currentWeeklyMeters: 30000,
    longestRecentMeters: 12000,
    daysPerWeek: 4,
    availableWeekdays: <int>{1, 3, 5, 6},
  );

  RunnerProfile rhythm() => const RunnerProfile(
    currentWeeklyMeters: 20000,
    longestRecentMeters: 8000,
    daysPerWeek: 3,
    availableWeekdays: <int>{2, 4, 6},
    commitments: <PlanCommitment>[
      PlanCommitment(weekday: DateTime.saturday, label: 'parkrun'),
    ],
  );

  Future<StoredPlan> built(RunnerProfile p) => PlanRepository(
    store: InMemoryPlanStore(),
    now: () => wednesday,
  ).create(p);

  String brief(StoredPlan plan, DateTime today) => CoachBrief.write(
    recentRuns: const [],
    plan: plan,
    now: today,
    unit: UnitSystem.metric,
  ).text;

  group('the coach is told the plan has not started', () {
    for (final (name, profile) in <(String, RunnerProfile Function())>[
      ('a block', block),
      ('a horizon', horizon),
      ('a rhythm', rhythm),
    ]) {
      test(name, () async {
        final plan = await built(profile());
        final text = brief(plan, wednesday);
        expect(
          text,
          contains(
            'Their plan has not started. It starts on Monday 5 October, in '
            '5 days, and nothing is set for the days before it.',
          ),
        );
        expect(text, isNot(contains('week 1 of')));
        expect(text, isNot(contains('weeks in')));
      });
    }

    test('and from the Monday, where they are in it', () async {
      final plan = await built(block());
      final text = brief(plan, monday);
      expect(text, contains('They are in week 1 of'));
      expect(text, isNot(contains('has not started')));
    });

    test('the day before, it starts tomorrow', () async {
      final plan = await built(block());
      final text = brief(plan, DateTime(2026, 10, 4));
      expect(text, contains('It starts on Monday 5 October, tomorrow'));
    });
  });

  group("the Plan tab's header", () {
    test('a block counts down, and says when it starts', () async {
      final plan = await built(block());
      final days = daysBetweenDates(wednesday, plan.profile.eventDate!);
      expect(
        planHeadline(plan, wednesday).position,
        '$days days · starts Monday 5 Oct',
      );
      expect(
        planHeadline(plan, monday).position,
        '${days - 5} days · week 1 of ${plan.skeleton.weeks.length}',
      );
    });

    test('a horizon says when it starts instead of its week', () async {
      final plan = await built(horizon());
      expect(
        planHeadline(plan, wednesday).position,
        'starts Monday 5 Oct · no date set',
      );
      expect(planHeadline(plan, monday).position, 'week 1 · no date set');
    });

    testWidgets('and the header fits beside the goal on a phone', (
      tester,
    ) async {
      final repo = PlanRepository(
        store: InMemoryPlanStore(),
        now: () => wednesday,
      );
      final plan = await repo.create(block());
      await tester.binding.setSurfaceSize(const Size(393, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: PlanScreen(
            plan: plan,
            now: wednesday,
            weeks: <int, TrainingWeek>{
              1: await repo.weekFor(plan, plan.skeleton.weeks[0]),
            },
            onOpenBlock: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('starts Monday 5 Oct'), findsOneWidget);
      expect(find.textContaining('week 1 of'), findsNothing);
    });
  });
}
