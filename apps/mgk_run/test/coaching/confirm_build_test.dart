import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/domain/intake_slots.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_shape.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/presentation/profile_confirmation_screen.dart';

/// "Build my plan" threw a null check and the framework swallowed it, so the
/// button read as dead. Found by building a real plan, not by reading the code.
void main() {
  final now = DateTime(2026, 7, 30);

  Future<RunnerProfile?> tapBuild(
    WidgetTester tester,
    IntakeSlots slots,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    RunnerProfile? built;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: ProfileConfirmationScreen(
          slots: slots,
          now: () => now,
          onConfirm: (p) => built = p,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Build my plan'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'the button must not throw');
    return built;
  }

  testWidgets('a block with no weekdays given still builds', (tester) async {
    // The exact state a real onboarding produced: the coach was never told to
    // ask which days, so `availableWeekdays` arrived null and the force-unwrap
    // threw on every tap.
    final built = await tapBuild(
      tester,
      IntakeSlots(
        shape: PlanShape.block,
        goalDistanceMeters: 21097.5,
        eventDate: DateTime(2026, 11, 15),
        currentWeeklyMeters: 40000,
        longestRecentMeters: 18000,
        daysPerWeek: 5,
        timeTrialDistanceMeters: 5000,
        timeTrialDuration: const Duration(minutes: 22),
      ),
    );

    expect(built, isNotNull);
    expect(
      built!.availableWeekdays,
      <int>{1, 2, 3, 4, 5, 6, 7},
      reason: 'saying nothing about which days is not a constraint',
    );
  });

  testWidgets('a runner who only wants their runs logged still builds', (
    tester,
  ) async {
    // A log shape requires nothing, so `isComplete` is true immediately and the
    // three volume unwraps were all null.
    final built = await tapBuild(
      tester,
      const IntakeSlots(shape: PlanShape.log),
    );

    expect(built, isNotNull);
    expect(built!.currentWeeklyMeters, 0);
    expect(built.longestRecentMeters, 0);
    expect(built.daysPerWeek, 0);
  });

  testWidgets('the blank weekday row says blank is allowed', (tester) async {
    await tapBuild(tester, const IntakeSlots(shape: PlanShape.log));
    expect(find.text('Leave blank if any day works.'), findsOneWidget);
  });
}
