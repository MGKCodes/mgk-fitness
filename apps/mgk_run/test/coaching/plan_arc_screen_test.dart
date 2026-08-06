import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/units/distance.dart';
import 'package:mgk_run/src/features/coaching/domain/pace_model.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/presentation/plan_arc_screen.dart';
import 'package:mgk_run/src/features/coaching/presentation/week_detail_screen.dart';

void main() {
  final now = DateTime(2026, 7, 25);

  RunnerProfile profile() => RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: DateTime(2026, 11, 1),
    currentWeeklyMeters: 40000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 4, 6, 7},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );

  TrainingPaces paces() => TrainingPaces.fromRace(
    Distance.meters(5000),
    const Duration(minutes: 22),
  );

  testWidgets('PlanArcScreen shows the goal, projected time, and every week', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final p = profile();
    final skeleton = buildSkeleton(p, now: now);
    SkeletonWeekTapped? tapped;
    await tester.pumpWidget(
      MaterialApp(
        home: PlanArcScreen(
          skeleton: skeleton,
          profile: p,
          onOpenWeek: (w) => tapped = SkeletonWeekTapped(w.index),
        ),
      ),
    );

    expect(find.text('Your plan'), findsOneWidget);
    expect(find.text('42 km goal'), findsOneWidget);
    expect(find.textContaining('projected'), findsOneWidget);
    // A row per week — check the first and last labels exist.
    expect(find.text('W1'), findsOneWidget);
    expect(find.text('W${skeleton.weeks.length}'), findsOneWidget);
    expect(find.text('Taper'), findsWidgets);

    await tester.tap(find.text('W1'));
    await tester.pump();
    expect(tapped?.index, 1);
  });

  testWidgets('WeekDetailScreen shows sessions, paces, rest, and provisional', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final p = profile();
    final slot = buildSkeleton(p, now: now).weeks[5]; // a build week
    final week = buildFallbackWeek(slot, p);

    await tester.pumpWidget(
      MaterialApp(
        home: WeekDetailScreen(week: week, slot: slot, paces: paces()),
      ),
    );

    expect(find.textContaining('Provisional'), findsOneWidget);
    expect(find.text('Long run'), findsOneWidget);
    expect(find.text('Threshold'), findsOneWidget);
    expect(find.textContaining('target'), findsWidgets);
    // Wednesday and Friday aren't in the available set -> rest.
    expect(find.text('Rest'), findsWidgets);
  });

  // The supersede path was implemented and unit-tested but unreachable: with a
  // plan in place the only build-a-plan action lived on the empty state.
  testWidgets('the arc offers a way to start a new plan', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final p = profile();
    var asked = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PlanArcScreen(
          skeleton: buildSkeleton(p, now: now),
          profile: p,
          onReplacePlan: () => asked++,
        ),
      ),
    );

    await tester.tap(find.byTooltip('Start a new plan'));
    await tester.pump();
    expect(asked, 1);
  });

  testWidgets('with no coach there is no start-a-new-plan action', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final p = profile();
    await tester.pumpWidget(
      MaterialApp(
        home: PlanArcScreen(
          skeleton: buildSkeleton(p, now: now),
          profile: p,
        ),
      ),
    );

    expect(find.byTooltip('Start a new plan'), findsNothing);
  });
}

/// Tiny record of a tapped week, to assert onOpenWeek fired.
class SkeletonWeekTapped {
  const SkeletonWeekTapped(this.index);
  final int index;
}
