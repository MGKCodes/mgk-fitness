import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/intake_slots.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_shape.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/presentation/profile_confirmation_screen.dart';

void main() {
  final now = DateTime(2026, 7, 25);
  final future = DateTime(2026, 11, 1);

  IntakeSlots complete() => IntakeSlots(
    goalDistanceMeters: 42000,
    eventDate: future,
    currentWeeklyMeters: 40000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 4, 6, 7},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );

  Future<RunnerProfile?> pump(WidgetTester tester, IntakeSlots slots) async {
    RunnerProfile? confirmed;
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileConfirmationScreen(
          slots: slots,
          now: () => now,
          onConfirm: (p) => confirmed = p,
        ),
      ),
    );
    await tester.pump();
    return confirmed;
  }

  testWidgets('a complete profile shows metric-as-km and enables the button', (
    tester,
  ) async {
    await pump(tester, complete());

    expect(find.text('Build my plan'), findsOneWidget);
    expect(find.text('42.0'), findsOneWidget); // 42000 m shown as km
    expect(find.text('1 Nov 2026'), findsOneWidget); // future event date
    expect(find.text('22:00'), findsOneWidget);

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
  });

  testWidgets('onConfirm fires with the metric profile on tap', (tester) async {
    RunnerProfile? confirmed;
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileConfirmationScreen(
          slots: complete(),
          now: () => now,
          onConfirm: (p) => confirmed = p,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Build my plan'));
    await tester.pump();

    expect(confirmed, isNotNull);
    expect(confirmed!.goalDistanceMeters, 42000);
    expect(confirmed!.currentWeeklyMeters, 40000);
    expect(confirmed!.daysPerWeek, 5);
    expect(confirmed!.availableWeekdays, <int>{1, 2, 4, 6, 7});
    expect(confirmed!.timeTrialDuration, const Duration(minutes: 22));
  });

  testWidgets('an incomplete profile disables the button', (tester) async {
    const incomplete = IntakeSlots(
      goalDistanceMeters: 42000,
      daysPerWeek: 5,
    ); // missing event, volume, longest, time trial
    await pump(tester, incomplete);

    expect(find.text('Fill in the details above'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets(
    'editing a value to something implausible re-disables the button',
    (tester) async {
      await pump(tester, complete());
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );

      // 2 km/week is below the plausible floor — the same Dart sanity check that
      // guarded the conversation now guards the form.
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.controller?.text == '40.0',
        ),
        '2',
      );
      await tester.pump();

      expect(find.textContaining('plausible range'), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
    },
  );

  // ---- shapes other than a block -------------------------------------------
  //
  // ADR-0011 gave plans four shapes, but this screen was written for one. It
  // rebuilt IntakeSlots from its own fields (dropping shape and commitments)
  // and force-unwrapped goal and event date, so "Build my plan" threw
  // "Unexpected null value" for a rhythm or a horizon — found by walking
  // onboarding against the live coach, which is the only way it could be.

  IntakeSlots rhythm() => const IntakeSlots(
    shape: PlanShape.rhythm,
    commitments: <PlanCommitment>[
      PlanCommitment(
        weekday: DateTime.saturday,
        distanceMeters: 5000,
        label: 'parkrun',
        timed: true,
      ),
    ],
    currentWeeklyMeters: 20000,
    longestRecentMeters: 8000,
    daysPerWeek: 3,
    availableWeekdays: <int>{2, 4, 6},
  );

  IntakeSlots horizon() => const IntakeSlots(
    shape: PlanShape.horizon,
    goalDistanceMeters: 42195,
    currentWeeklyMeters: 25000,
    longestRecentMeters: 12000,
    daysPerWeek: 4,
    availableWeekdays: <int>{1, 3, 5, 7},
    // A horizon `progresses`, so the validator wants a time trial to derive
    // pace bands from — unlike a rhythm, which is not blocked on being
    // assessed. Omitting it here leaves the button correctly disabled.
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: Duration(minutes: 26),
  );

  testWidgets('a rhythm confirms without a goal or a date', (tester) async {
    RunnerProfile? confirmed;
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileConfirmationScreen(
          slots: rhythm(),
          now: () => now,
          onConfirm: (p) => confirmed = p,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Build my plan'));
    await tester.pump();

    expect(confirmed, isNotNull, reason: 'tapping used to throw');
    expect(confirmed!.goalDistanceMeters, isNull);
    expect(confirmed!.eventDate, isNull);
    // The substance of the rhythm has to survive the screen it is checked on.
    expect(confirmed!.commitments, hasLength(1));
    expect(confirmed!.commitments.single.label, 'parkrun');
    expect(confirmed!.commitments.single.weekday, DateTime.saturday);
  });

  testWidgets('a rhythm is never asked when their race is', (tester) async {
    await pump(tester, rhythm());

    // The question ADR-0011 exists to stop, and the one the intake prompt goes
    // out of its way never to ask.
    expect(find.text('Event date'), findsNothing);
    expect(find.text('Pick a date'), findsNothing);
    // Nor for a goal distance they said they do not have.
    expect(find.text('Goal distance'), findsNothing);
    // What they DO have is shown back to them, in their own word for it.
    expect(find.textContaining('parkrun'), findsOneWidget);
    expect(find.textContaining('Saturdays'), findsOneWidget);
  });

  testWidgets('a horizon keeps its goal and is asked for no date', (
    tester,
  ) async {
    RunnerProfile? confirmed;
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileConfirmationScreen(
          slots: horizon(),
          now: () => now,
          onConfirm: (p) => confirmed = p,
        ),
      ),
    );
    await tester.pump();

    // A distance to reach, with no race entered — that is the distinction.
    expect(find.text('Goal distance'), findsOneWidget);
    expect(find.text('Event date'), findsNothing);

    await tester.tap(find.text('Build my plan'));
    await tester.pump();

    expect(confirmed, isNotNull, reason: 'tapping used to throw');
    // Not exactly 42195: the field edits in km to one decimal, so the goal
    // round-trips as 42200. Deliberately within `raceName`'s 50 m tolerance,
    // so it is still called a Marathon.
    expect(confirmed!.goalDistanceMeters, closeTo(42195, 50));
    expect(confirmed!.eventDate, isNull);
  });

  testWidgets('a block still gets both, unchanged', (tester) async {
    await pump(tester, complete());

    expect(find.text('Goal distance'), findsOneWidget);
    expect(find.text('Event date'), findsOneWidget);
  });
}
