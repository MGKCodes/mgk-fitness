import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/data/plan_store.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/presentation/week_calendar.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';

/// A week the store cannot read, opened from the calendar. The snackbar
/// printed the exception's own message, written for a log rather than a
/// runner: the same leak the plan reveal had with the validator's text.
void main() {
  testWidgets('says so in plain words, and none of the store\'s', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = _BreakableStore();
    // Built three weeks ago, so the plan is under way whatever the weekday.
    await PlanRepository(
      store: store,
      now: () => DateTime.now().subtract(const Duration(days: 21)),
    ).create(
      RunnerProfile(
        goalDistanceMeters: 21097.5,
        eventDate: DateTime.now().add(const Duration(days: 90)),
        currentWeeklyMeters: 30000,
        longestRecentMeters: 12000,
        daysPerWeek: 4,
        availableWeekdays: const <int>{1, 3, 5, 6},
        // A time trial, so the calendar's days open a week at all.
        timeTrialDistanceMeters: 5000,
        timeTrialDuration: const Duration(minutes: 25),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          auth: FakeAuthRepository(signedIn: true, email: 'a@example.com'),
          planStore: store,
          historySource: () async => const [],
          initialTab: 1,
        ),
      ),
    );
    Future<void> rest() async {
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 120));
      }
    }

    await rest();
    await tester.tap(find.text('Calendar'));
    await rest();

    store.broken = true;
    await tester.tap(
      find
          .descendant(
            of: find.byType(WeekCalendar).first,
            matching: find.byWidgetPredicate(
              (w) => w.runtimeType.toString() == '_Day',
            ),
          )
          .first,
    );
    await rest();

    expect(find.text(kWeekUnopenedMessage), findsOneWidget);
    expect(find.textContaining('unknown kind'), findsNothing);
    expect(find.textContaining('plan-'), findsNothing);
  });
}

/// A store whose weeks stop reading on demand, after the tab has loaded.
class _BreakableStore extends InMemoryPlanStore {
  bool broken = false;

  @override
  Future<TrainingWeek?> loadWeek(StoredPlan plan, int weekNumber) {
    if (broken) {
      throw PlanStoreException(
        'plan ${plan.id} week $weekNumber day 3 has unknown kind "sprint"',
      );
    }
    return super.loadWeek(plan, weekNumber);
  }
}
