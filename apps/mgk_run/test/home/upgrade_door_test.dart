import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_access.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_gate_sheet.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

/// The dead end that would have shipped: an offer with nothing to tap.
///
/// A free runner whose last run answered a prescribed session gets `_Locked` on
/// the last-run tile — a dimmed skeleton of the two rows a coach would fill,
/// the words *"Upgrade to see this stat"*, and a button offering to explain
/// what a coach adds. The button is hidden when `onUpgrade` is null, and
/// **[HomeShell] never passed one**: the only caller that ever supplied an
/// `onUpgrade` was `last_run_test.dart`, so the tile's own tests passed for a
/// month while the shipping app told runners to upgrade and gave them no door.
/// That is App Review Guideline 2.1 on its own, whatever is decided about
/// payments.
///
/// It is asserted here rather than in `last_run_test.dart` because the tile is
/// not where the bug was. A widget cannot test the argument its caller declined
/// to pass, which is the whole shape of this failure — so this drives the real
/// [HomeShell], with a real plan behind it, and reaches the door the way a
/// runner does.
/// Three weeks ago, so the plan is under way on whatever day the suite runs.
/// A plan starts on the coming Monday (ADR-0034) and asks nothing of the days
/// before it, so one built "today" is a runner with no session yet on six days
/// of the week out of seven.
DateTime _underWay() => DateTime.now().subtract(const Duration(days: 21));

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  RunnerProfile aProfile() => RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: DateTime.now().add(const Duration(days: 112)),
    currentWeeklyMeters: 40000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 3, 4, 5, 6, 7},
  );

  testWidgets('a free runner reaches the door from the locked last run', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = DriftPlanStore(db);
    final repo = PlanRepository(store: store, now: _underWay);
    final plan = await repo.create(aProfile());

    // The tile only draws `_Locked` when the run answered something, so the
    // run has to land on a day this week that the plan actually prescribes.
    // Read off the generated week rather than assumed: which weekdays a plan
    // uses is the builder's business, and a hardcoded Monday would make this
    // test fail for a reason that has nothing to do with the door.
    final now = DateTime.now();
    final TrainingWeek week = await repo.weekFor(plan, plan.weekOn(now));
    final int weekday = week.sessions.first.weekday;
    final DateTime monday = mondayOf(now);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          auth: FakeAuthRepository(signedIn: true, email: 'dev@mgkcodes.com'),
          planStore: store,
          access: CoachAccess.free,
          historySource: () async => <RunSummary>[
            RunSummary(
              startedAt: addDays(
                monday,
                weekday - 1,
              ).add(const Duration(hours: 7, minutes: 20)),
              duration: const Duration(minutes: 41, seconds: 8),
              distanceMeters: 7400,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final offer = find.text('See what a coach adds');
    expect(
      offer,
      findsOneWidget,
      reason: 'the locked tile must not tell a runner to upgrade in silence',
    );

    await tester.ensureVisible(offer);
    await tester.tap(offer);
    await tester.pumpAndSettle();

    // The same sheet the coach mark opens (ADR-0030), not a second surface
    // saying the same thing in different words.
    expect(find.byType(CoachGateSheet), findsOneWidget);
  });

  testWidgets('and a subscribed runner is shown the stat, not the door', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final store = DriftPlanStore(db);
    final repo = PlanRepository(store: store, now: _underWay);
    final plan = await repo.create(aProfile());
    final now = DateTime.now();
    final TrainingWeek week = await repo.weekFor(plan, plan.weekOn(now));
    final int weekday = week.sessions.first.weekday;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          auth: FakeAuthRepository(signedIn: true, email: 'dev@mgkcodes.com'),
          planStore: store,
          access: CoachAccess.subscribed,
          historySource: () async => <RunSummary>[
            RunSummary(
              startedAt: addDays(
                mondayOf(now),
                weekday - 1,
              ).add(const Duration(hours: 7, minutes: 20)),
              duration: const Duration(minutes: 41, seconds: 8),
              distanceMeters: 7400,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Upgrade to see this stat'), findsNothing);
    expect(
      find.text('See what a coach adds'),
      findsNothing,
      reason: 'a door is for somebody standing outside it',
    );
  });
}
