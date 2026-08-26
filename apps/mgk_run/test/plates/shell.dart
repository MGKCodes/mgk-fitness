import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/preview/fake_coach_service.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/recording/domain/best_effort.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

import 'plate.dart';

/// **The app assembling its own screens, instead of me assembling them.**
///
/// Every plate in `screens.dart` is a tab rendered on its own, and that turned
/// out to cost more than the missing chrome. Twice over:
///
/// **The shell draws things no tab knows about.** The nav bar and the floating
/// coach mark belong to [HomeShell], so a board made of tabs omits them from
/// every picture at once — which is how a design that has always had a coach
/// came to look like one that had lost it.
///
/// **A hand-built fixture shows the app degraded.** Four times now a plate has
/// made a screen look worse than it is, and the mechanism was the same each
/// time: a fixture built to satisfy the *required* arguments leaves the
/// optional ones null, the screen correctly renders its empty state, and the
/// board reports that as the design. The finished run had no trace, so it drew
/// no route. The profile had no records. No run had an average pace. Home was
/// never handed a plan headline, so the header fell through to the greeting and
/// two rounds of design conversation went on a problem that did not exist.
///
/// A shell fed a seeded database has neither failure mode. It is handed a
/// runner rather than a widget's arguments, and everything downstream — the
/// header, the week, the log, the coach — is derived by the app itself. What
/// the plate cannot show is then genuinely absent rather than merely unpassed.
///
/// Regenerate with:
///
///     flutter test test/plates/shell.dart
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// A runner training for a marathon, available every day so today always has
  /// a session — the plate would otherwise show a rest day about half the time
  /// it was regenerated, which is a board that changes what it claims depending
  /// on when you look at it.
  RunnerProfile profile() => RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: DateTime.now().add(const Duration(days: 112)),
    currentWeeklyMeters: 40000,
    longestRecentMeters: 18000,
    daysPerWeek: 7,
    availableWeekdays: const <int>{1, 2, 3, 4, 5, 6, 7},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );

  /// Runs behind them, so the log, the records and the year all have something
  /// real to draw rather than their empty states.
  List<RunSummary> log() {
    final now = DateTime.now();
    return <RunSummary>[
      for (var i = 1; i < 40; i++)
        if (i % 2 == 1)
          RunSummary(
            id: 'plate-$i',
            startedAt: now.subtract(Duration(days: i)),
            duration: Duration(minutes: 28 + (i % 9) * 6),
            distanceMeters: 5200 + (i % 9) * 1800,
            avgPaceSecondsPerKm:
                (28 + (i % 9) * 6) * 60 / ((5200 + (i % 9) * 1800) / 1000),
            bestEfforts: <BestEffort>[
              if (5200 + (i % 9) * 1800 >= 5000)
                BestEffort(
                  distanceMeters: 5000,
                  duration: Duration(seconds: 1500 + (i % 7) * 20),
                ),
            ],
          ),
    ];
  }

  /// Pumps rather than settles.
  ///
  /// The shell loads its plan, its log and its coach asynchronously and then
  /// the coach mark plays a 3.4-second reveal, so `pumpAndSettle` would either
  /// hang on the animation or land on whichever frame it stopped at. Fixed
  /// pumps put the picture at a chosen moment instead.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  testWidgets('home, as a runner on a plan actually sees it', (tester) async {
    final store = DriftPlanStore(db);
    await PlanRepository(store: store).create(profile());
    final runs = log();

    await plate(
      tester,
      'shell-home',
      HomeShell(
        auth: FakeAuthRepository(signedIn: true, email: 'runner@example.com'),
        planStore: store,
        historySource: () async => runs,
        coach: FakeCoachService(),
      ),
      pixelRatio: 2,
      drive: settle,
    );
  });

  testWidgets('the profile tab, under the same chrome', (tester) async {
    final store = DriftPlanStore(db);
    await PlanRepository(store: store).create(profile());
    final runs = log();

    await plate(
      tester,
      'shell-profile',
      HomeShell(
        auth: FakeAuthRepository(signedIn: true, email: 'runner@example.com'),
        planStore: store,
        historySource: () async => runs,
        coach: FakeCoachService(),
        initialTab: 2,
      ),
      pixelRatio: 2,
      drive: settle,
    );
  });

  testWidgets('and the plan tab', (tester) async {
    final store = DriftPlanStore(db);
    await PlanRepository(store: store).create(profile());
    final runs = log();

    await plate(
      tester,
      'shell-plan',
      HomeShell(
        auth: FakeAuthRepository(signedIn: true, email: 'runner@example.com'),
        planStore: store,
        historySource: () async => runs,
        coach: FakeCoachService(),
        initialTab: 1,
      ),
      pixelRatio: 2,
      drive: settle,
    );
  });
}
