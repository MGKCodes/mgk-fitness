import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/data/plan_store.dart';
import 'package:mgk_run/src/features/coaching/domain/goal_draft.dart';
import 'package:mgk_run/src/features/coaching/domain/intake_slots.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_shape.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_validator.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/coaching/presentation/plan_reveal_screen.dart';
import 'package:mgk_run/src/features/coaching/presentation/profile_confirmation_screen.dart';

/// A race too close to build a block for (test sheet D18, screen board G6 and
/// G7).
///
/// The confirmation screen lit "Build my plan" for a race three weeks out, and
/// building it failed on the skeleton validator, which the reveal then printed
/// word for word — "[race_day_outside_final_week] race day falls in week 3 of
/// 6" — under an apology and over a Try again that failed identically. The
/// sheet expects the refusal before anything is built, in the coach's words.
void main() {
  // A Wednesday, so the coming Monday (ADR-0034) is five days away and the
  // difference between counting from today and from the start is visible.
  final now = DateTime(2026, 9, 30);
  final start = comingMondayFrom(now); // Mon 5 Oct

  IntakeSlots block(DateTime race) => IntakeSlots(
    shape: PlanShape.block,
    goalDistanceMeters: 10000,
    eventDate: race,
    currentWeeklyMeters: 30000,
    longestRecentMeters: 12000,
    daysPerWeek: 4,
    availableWeekdays: const <int>{1, 3, 5, 6},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 25),
  );

  group('the confirmation screen', () {
    Future<List<RunnerProfile>> pump(WidgetTester tester, DateTime race) async {
      final confirmed = <RunnerProfile>[];
      await tester.binding.setSurfaceSize(const Size(420, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: ProfileConfirmationScreen(
            slots: block(race),
            now: () => now,
            onConfirm: confirmed.add,
          ),
        ),
      );
      await tester.pump();
      return confirmed;
    }

    FilledButton build(WidgetTester tester) =>
        tester.widget<FilledButton>(find.byType(FilledButton));

    testWidgets('says so where the date is, and will not build', (
      tester,
    ) async {
      final confirmed = await pump(tester, now.add(const Duration(days: 21)));

      expect(find.text(kRaceTooCloseMessage), findsOneWidget);
      expect(find.text('Build my plan'), findsNothing);
      expect(find.text('Fix the race date above'), findsOneWidget);
      expect(build(tester).onPressed, isNull);
      expect(confirmed, isEmpty);
    });

    testWidgets('counts from the Monday the plan starts, not from today', (
      tester,
    ) async {
      // 42 days from today is only 37 from the start: too close.
      await pump(tester, now.add(const Duration(days: 42)));
      expect(find.text(kRaceTooCloseMessage), findsOneWidget);
    });

    testWidgets('six weeks from the start is enough', (tester) async {
      final confirmed = await pump(tester, addDays(start, 42));

      expect(find.text(kRaceTooCloseMessage), findsNothing);
      expect(find.text('Build without a race'), findsNothing);
      await tester.tap(find.text('Build my plan'));
      await tester.pump();
      expect(confirmed, hasLength(1));
    });

    testWidgets('building without the race keeps the plan and drops the date', (
      tester,
    ) async {
      final confirmed = await pump(tester, now.add(const Duration(days: 21)));

      await tester.tap(find.text('Build without a race'));
      await tester.pump();

      expect(find.text(kRaceTooCloseMessage), findsNothing);
      // Still on screen, so taking the race out can be undone.
      expect(find.text('No race'), findsOneWidget);
      expect(find.text('Goal distance'), findsOneWidget);

      await tester.tap(find.text('Build my plan'));
      await tester.pump();

      expect(confirmed, hasLength(1));
      expect(confirmed.single.eventDate, isNull);
      expect(confirmed.single.goalDistanceMeters, 10000);
      expect(
        shapeOf(confirmed.single),
        PlanShape.horizon,
        reason: 'a distance with no race to taper into',
      );
    });
  });

  group('the reveal, when the builder refuses anyway', () {
    Future<void> pump(
      WidgetTester tester,
      Object error, {
      VoidCallback? onChangeDetails,
      void Function(StoredPlan?)? onDone,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: PlanRevealScreen(
            build: () async => throw error,
            onDone: onDone ?? (_) {},
            onChangeDetails: onChangeDetails,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Nothing the validator wrote reaches the screen.
    void expectNoInternals() {
      expect(find.textContaining('refusing'), findsNothing);
      expect(find.textContaining('validator'), findsNothing);
      expect(find.textContaining('['), findsNothing);
      expect(find.textContaining('week 3 of 6'), findsNothing);
    }

    testWidgets('a race too close gets the same six-week message', (
      tester,
    ) async {
      var changed = 0;
      await pump(
        tester,
        PlanRejectedException(const <Violation>[
          Violation(
            'race_day_outside_final_week',
            'race day falls in week 3 of 6, not the final week',
          ),
        ]),
        onChangeDetails: () => changed++,
      );

      expect(find.text(kRaceTooCloseMessage), findsOneWidget);
      expect(find.textContaining('on me rather than on you'), findsNothing);
      expectNoInternals();
      // The same details would be refused the same way.
      expect(find.text('Try again'), findsNothing);

      await tester.tap(find.text('Change the race'));
      await tester.pump();
      expect(changed, 1);
      expect(find.text('Not now'), findsOneWidget);
    });

    testWidgets('any other refusal is a plain line, and no Try again', (
      tester,
    ) async {
      await pump(
        tester,
        PlanRejectedException(const <Violation>[
          Violation('volume_ramp', 'week 4 ramps 18% over week 3'),
        ]),
        onChangeDetails: () {},
      );

      expectNoInternals();
      expect(find.textContaining('ramps'), findsNothing);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Check the details'), findsOneWidget);
    });

    testWidgets('with nowhere to go back to, leaving is the one button', (
      tester,
    ) async {
      StoredPlan? left;
      var done = false;
      await pump(
        tester,
        PlanRejectedException(const <Violation>[
          Violation('race_day_outside_final_week', 'race day falls in week 3'),
        ]),
        onDone: (plan) {
          done = true;
          left = plan;
        },
      );

      expect(find.text('Try again'), findsNothing);
      expect(find.text('Change the race'), findsNothing);
      await tester.tap(find.text('Not now'));
      await tester.pump();
      expect(done, isTrue);
      expect(left, isNull);
    });

    testWidgets('a store that failed is worth trying again, in plain words', (
      tester,
    ) async {
      await pump(
        tester,
        const PlanStoreException('could not write plan: SqliteException(5)'),
      );

      expect(find.text('Try again'), findsOneWidget);
      expect(find.textContaining('Sqlite'), findsNothing);
      expect(find.textContaining('could not write'), findsNothing);
      expect(
        find.text('The plan could not be built. Please try again.'),
        findsOneWidget,
      );
    });
  });
}
