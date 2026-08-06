import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/units/distance.dart';
import 'package:mgk_run/src/core/units/unit_system.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/session_status.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/presentation/plan_screen.dart';

void main() {
  // A Saturday, so "today" sits mid-week and the week's Monday is the 20th.
  final now = DateTime(2026, 7, 25);

  final profile = RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: DateTime(2026, 11, 1),
    currentWeeklyMeters: 40000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 4, 6, 7},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );
  final skeleton = buildSkeleton(profile, now: now);

  final plan = StoredPlan(
    id: 'test-plan',
    profile: profile,
    skeleton: skeleton,
    startDate: mondayOf(now),
  );

  /// The two weeks inside the planning horizon, filled from the skeleton.
  final weeks = <int, TrainingWeek>{
    1: buildFallbackWeek(skeleton.weeks[0], profile),
    2: buildFallbackWeek(skeleton.weeks[1], profile),
  };

  Future<void> pumpCoach(
    WidgetTester tester, {
    void Function(SkeletonWeek slot, int weekday)? onOpenWeek,
    VoidCallback? onOpenCalendar,
    SessionStatus? Function(int weekday)? statusFor,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: PlanScreen(
          onOpenCalendar: onOpenCalendar,
          plan: plan,
          weeks: weeks,
          now: now,
          statusFor: statusFor,
          onOpenWeek: onOpenWeek,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The bug this suite exists for: the calendar handed the tapped weekday to
  // its caller and the caller threw it away with `(_)`, so seven cells were one
  // button. Nothing failed — the week still opened — which is exactly why it
  // survived. It stays covered here now that a row *is* the day.
  testWidgets('a day row opens the coach on that session', (tester) async {
    // A 48px grid cell was too small to mean anything on its own, so the whole
    // pane opened the calendar. A full-width row is unambiguous, so it opens
    // the session brief — and the calendar gets its own control in the header.
    var openedCalendar = 0;
    await pumpCoach(tester, onOpenCalendar: () => openedCalendar++);

    await tester.tap(find.text('Thu')); // a session day this week
    await tester.pumpAndSettle();

    expect(find.text('HOW IT SHOULD FEEL'), findsOneWidget);
    expect(find.text('WHY IT IS HERE'), findsOneWidget);
    expect(openedCalendar, 0);
  });

  // The number was never the instruction. A runner chasing 4:39 on an easy day
  // is running their easy days too hard, which is how a block stalls.
  testWidgets('the week says the effort; the pace is one tap away', (
    tester,
  ) async {
    await pumpCoach(tester);

    expect(find.textContaining('target'), findsNothing);
    expect(find.text('conversational the whole way'), findsWidgets);

    await tester.tap(find.text('Thu'));
    await tester.pumpAndSettle();

    // And behind the tap, a band rather than a number to miss.
    expect(find.textContaining('–'), findsWidgets);
  });

  testWidgets('a rest day is explained, not left blank', (tester) async {
    await pumpCoach(tester);

    // Friday is not an available day for this profile.
    await tester.tap(find.text('Fri'));
    await tester.pumpAndSettle();

    expect(find.text('Rest'), findsWidgets);
    expect(find.text('WHY IT IS HERE'), findsOneWidget);
  });

  testWidgets('the header opens the whole calendar', (tester) async {
    var openedCalendar = 0;
    await pumpCoach(tester, onOpenCalendar: () => openedCalendar++);

    await tester.tap(find.text('Calendar'));
    await tester.pump();

    expect(openedCalendar, 1);
  });

  // P3: the volume shared an eye-line with the section label, so a horizontal
  // scan hit a heading and a number at once.
  testWidgets('the week volume sits under the label, not beside it', (
    tester,
  ) async {
    await pumpCoach(tester);

    final volume = Distance.meters(
      skeleton.weeks[0].volumeMeters,
    ).format(UnitSystem.metric, fractionDigits: 0);

    // Dates, not an index. "W1" is the plan's internal numbering leaking onto
    // the screen — a runner cannot match it against a calendar or a race entry.
    final label = find.text('THIS WEEK · 20 – 26 JUL');
    final value = find.text('Base · $volume planned · week 1');
    expect(label, findsOneWidget);
    expect(value, findsOneWidget);

    final labelBox = tester.getRect(label);
    final valueBox = tester.getRect(value);
    expect(
      valueBox.top,
      greaterThanOrEqualTo(labelBox.bottom),
      reason: 'the volume is a subtitle, not a second heading',
    );
    expect(
      valueBox.left,
      closeTo(labelBox.left, 0.5),
      reason: 'and it reads down one column rather than across the row',
    );
  });

  // A status recorded against this week must survive the trip through the
  // week block into the calendar — the marks themselves are covered in
  // week_calendar_test.dart.
  testWidgets('a recorded status reaches the calendar', (tester) async {
    await pumpCoach(
      tester,
      statusFor: (weekday) => switch (weekday) {
        1 => SessionStatus.completed,
        2 => SessionStatus.skipped,
        _ => null,
      },
    );

    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('next week carries no status — nothing has happened yet', (
    tester,
  ) async {
    // statusFor answers for the *current* week, so next week's Monday must not
    // borrow this week's tick.
    await pumpCoach(
      tester,
      statusFor: (w) => w == 1 ? SessionStatus.completed : null,
    );

    expect(find.byIcon(Icons.check), findsOneWidget);
  });
}
