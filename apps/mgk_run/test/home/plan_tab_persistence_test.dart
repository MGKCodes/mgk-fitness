import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/preview/fake_coach_service.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/data/plan_store.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/session_status.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_history.dart';
import 'package:mgk_run/src/features/coaching/domain/race_day.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';

/// A store whose reads always fail, standing in for a corrupt row or a schema
/// mismatch. The tab must say so rather than showing the empty state, which
/// would invite the runner to build a second plan over a block that is still
/// there.
class _UnreadableStore implements PlanStore {
  @override
  Future<StoredPlan?> loadActivePlan() async =>
      throw const PlanStoreException('stored plan is unreadable');

  @override
  Future<void> savePlan(StoredPlan plan) async {}

  /// Refuses, like the reads. A store that cannot open the plan cannot say
  /// what became of it either, and reporting a block closed on the strength of
  /// a row nothing could decode would be worse than leaving it alone.
  @override
  Future<void> closePlan(
    StoredPlan plan, {
    required PlanClosure closure,
    Duration? raceTime,
  }) async => throw const PlanStoreException('stored plan is unreadable');

  /// Fails like every other read here: a store that cannot open the active plan
  /// has no business claiming the runner never had one.
  @override
  Future<List<PlanRecord>> loadHistory() async =>
      throw const PlanStoreException('stored plan is unreadable');

  @override
  Future<TrainingWeek?> loadWeek(StoredPlan plan, int weekNumber) async => null;

  @override
  Future<void> saveWeek(StoredPlan plan, TrainingWeek week) async {}

  @override
  Future<SessionStatus?> statusOn(StoredPlan plan, DateTime date) async => null;

  @override
  Future<bool> setStatusOn(
    StoredPlan plan,
    DateTime date,
    SessionStatus status,
  ) async => false;
}

void main() {
  late AppDatabase db;

  RunnerProfile aProfile() => RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: DateTime.now().add(const Duration(days: 112)),
    currentWeeklyMeters: 40000,
    longestRecentMeters: 18000,
    daysPerWeek: 7, // train every day, so "today" always has a session
    availableWeekdays: const <int>{1, 2, 3, 4, 5, 6, 7},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );

  Widget shell(
    PlanStore store, {
    bool withCoach = false,
    Future<List<RunSummary>> Function()? history,
  }) => MaterialApp(
    theme: AppTheme.dark,
    home: HomeShell(
      auth: FakeAuthRepository(signedIn: true, email: 'dev@runio.app'),
      planStore: store,
      historySource: history,
      coach: withCoach ? FakeCoachService() : null,
    ),
  );

  /// Mounts the shell and opens the Plan tab.
  Future<void> openPlan(
    WidgetTester tester,
    PlanStore store, {
    bool withCoach = false,
    bool openPlanTab = false,
    Future<List<RunSummary>> Function()? history,
  }) async {
    await tester.pumpWidget(
      shell(store, withCoach: withCoach, history: history),
    );
    await tester.pumpAndSettle();
    if (openPlanTab) await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
  }

  /// A run today, which is what makes today's session complete now that
  /// completion is observed rather than asserted (ADR-0017).
  List<RunSummary> ranToday() => <RunSummary>[
    RunSummary(
      startedAt: DateTime.now(),
      duration: const Duration(minutes: 41),
      distanceMeters: 8000,
      avgPaceSecondsPerKm: 308,
    ),
  ];

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  testWidgets('with no stored plan the coach still offers itself', (
    tester,
  ) async {
    await openPlan(
      tester,
      DriftPlanStore(db),
      withCoach: true,
      openPlanTab: true,
    );

    expect(find.text('No plan — that’s fine'), findsOneWidget);
    expect(find.text('Build a plan'), findsOneWidget);
    expect(find.byType(CoachButton), findsOneWidget);
  });

  testWidgets('a stored plan is shown on launch, with no coach and no network', (
    tester,
  ) async {
    // Seed storage the way a previous session would have left it, then start the
    // app cold: no coach injected, so nothing could regenerate this.
    final store = DriftPlanStore(db);
    await PlanRepository(store: store).create(aProfile());

    await openPlan(tester, store);

    expect(find.text('No plan yet'), findsNothing);
    // Today's card came back with the plan, carrying its own action.
    expect(find.textContaining('TODAY'), findsWidgets);
    expect(find.text('Start'), findsOneWidget);
  });

  /// The three tests this replaces drove "Mark done", "Skip" and "Undo" and
  /// checked the assertion came back off disk. There is no assertion any more:
  /// a session is done when a run exists on the day (ADR-0017), so the property
  /// worth pinning is that the *observation* survives a cold start — and that
  /// without a run, the card still offers to start one.
  testWidgets('a run today reads as done, on this launch and the next', (
    tester,
  ) async {
    final store = DriftPlanStore(db);
    await PlanRepository(store: store).create(aProfile());

    await openPlan(tester, store, history: () async => ranToday());

    expect(find.text('Run recorded today.'), findsOneWidget);
    expect(
      find.text('Start'),
      findsNothing,
      reason: 'a session already run is not still an instruction',
    );

    // Tear the whole app down and build it again over the same database — the
    // widget state is gone, so anything still on screen came off disk.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    await openPlan(tester, DriftPlanStore(db), history: () async => ranToday());

    expect(find.text('Run recorded today.'), findsOneWidget);
  });

  testWidgets('with no run today the card still offers to start one', (
    tester,
  ) async {
    final store = DriftPlanStore(db);
    await PlanRepository(store: store).create(aProfile());

    await openPlan(tester, store);

    expect(find.text('Start'), findsOneWidget);
    expect(find.text('Run recorded today.'), findsNothing);
    // And nothing anywhere that writes completion by hand.
    expect(find.text('Mark done'), findsNothing);
    expect(find.text('Skip'), findsNothing);
  });

  testWidgets('an unreadable plan is reported, not shown as an empty state', (
    tester,
  ) async {
    await openPlan(tester, _UnreadableStore(), openPlanTab: true);

    expect(find.text("Couldn't open your plan"), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // Crucially NOT the empty state — the plan may still be recoverable.
    expect(find.text('No plan — that’s fine'), findsNothing);
  });

  testWidgets('the plan tab does not disturb Home', (tester) async {
    final store = DriftPlanStore(db);
    await PlanRepository(store: store).create(aProfile());

    await tester.pumpWidget(shell(store));
    await tester.pumpAndSettle();

    // The shell still opens on Home, with the plan quietly loaded behind it —
    // and Home shows today's session from that plan rather than a coach prompt.
    expect(find.text('Start'), findsOneWidget);
    expect(find.textContaining('TODAY'), findsWidgets);
  });

  testWidgets('with no store injected the tab still works, in memory', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          auth: FakeAuthRepository(signedIn: true, email: 'dev@runio.app'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();

    // No coach and no store: the empty state, and no mark at all — a mark
    // that cannot open anything is worse than no mark.
    expect(find.byType(CoachButton), findsNothing);
  });
}
