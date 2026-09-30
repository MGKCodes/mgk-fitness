import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/presentation/plan_calendar_screen.dart';

/// The calendar opens on the week today is in (screen board P4). It jumped to
/// "(week - 1) × 208pt", and panes are not all 208pt, so a runner a few weeks
/// in found "This week" and its dates tucked under the app bar.
void main() {
  final start = DateTime(2026, 9, 7); // a Monday
  final profile = RunnerProfile(
    goalDistanceMeters: 21097.5,
    eventDate: DateTime(2027, 1, 10),
    currentWeeklyMeters: 30000,
    longestRecentMeters: 12000,
    daysPerWeek: 4,
    availableWeekdays: const <int>{1, 3, 5, 6},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 25),
  );
  final skeleton = buildSkeleton(profile, now: start);
  final plan = StoredPlan(
    id: 'p',
    profile: profile,
    skeleton: skeleton,
    startDate: start,
  );
  final weeks = <int, TrainingWeek>{
    for (var i = 0; i < 6; i++)
      i + 1: buildFallbackWeek(skeleton.weeks[i], profile),
  };

  for (final weeksIn in <int>[1, 3, 5]) {
    testWidgets('in week $weeksIn, its title is whole under the bar', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 852);
      addTearDown(tester.view.reset);
      final today = start.add(Duration(days: (weeksIn - 1) * 7 + 2));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: PlanCalendarScreen(plan: plan, weeks: weeks, now: today),
        ),
      );
      await tester.pumpAndSettle();

      final title = find.textContaining('THIS WEEK');
      expect(title, findsOneWidget);
      final bar = tester.getBottomLeft(find.byType(AppBar)).dy;
      final top = tester.getTopLeft(title).dy;
      expect(top, greaterThanOrEqualTo(bar), reason: 'not under the bar');
      // And the week starts at the top rather than somewhere below it.
      expect(top - bar, lessThan(80), reason: '${top - bar}pt below the bar');
    });
  }
}
