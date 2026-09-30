import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_shape.dart';
import 'package:mgk_run/src/features/coaching/domain/race_day.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/presentation/plan_finish_screen.dart';
import 'package:mgk_run/src/features/coaching/presentation/race_result_sheet.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

/// Race day as the runner meets it, through the shell that assembles it.
///
/// **Driven through [HomeShell] over a seeded database rather than by handing
/// a card its arguments.** Four times in this lane a screen has been judged
/// from a fixture that left the optional arguments null, and this is exactly
/// the sort of surface that would fall to it: the whole point of race day is
/// that it is derived from the plan, and a card told about a race directly
/// proves nothing about whether the plan would have told it.
void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// A block whose race is [daysAway] from today, available every day so there
  /// is always a session and the test never lands on a rest day by accident.
  RunnerProfile blockRacingIn(int daysAway) => RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: _dateOnly(DateTime.now().add(Duration(days: daysAway))),
    currentWeeklyMeters: 40000,
    longestRecentMeters: 22000,
    daysPerWeek: 7,
    availableWeekdays: const <int>{1, 2, 3, 4, 5, 6, 7},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );

  /// A goal with no race entered — ADR-0011's horizon.
  RunnerProfile horizon() => const RunnerProfile(
    goalDistanceMeters: 42195,
    currentWeeklyMeters: 40000,
    longestRecentMeters: 22000,
    daysPerWeek: 7,
    availableWeekdays: <int>{1, 2, 3, 4, 5, 6, 7},
  );

  /// parkrun every Saturday: no goal, no date, nothing to arrive at.
  RunnerProfile rhythm() => const RunnerProfile(
    currentWeeklyMeters: 20000,
    longestRecentMeters: 8000,
    daysPerWeek: 7,
    availableWeekdays: <int>{1, 2, 3, 4, 5, 6, 7},
    commitments: <PlanCommitment>[
      PlanCommitment(
        weekday: DateTime.saturday,
        distanceMeters: 5000,
        label: 'parkrun',
        timed: true,
      ),
    ],
  );

  RunSummary raceRun(DateTime day) => RunSummary(
    id: 'race',
    startedAt: DateTime(day.year, day.month, day.day, 9),
    duration: const Duration(hours: 3, minutes: 42, seconds: 18),
    distanceMeters: 42610,
  );

  Future<void> open(
    WidgetTester tester,
    RunnerProfile profile, {
    List<RunSummary> runs = const <RunSummary>[],
  }) async {
    final store = DriftPlanStore(db);
    // Built ten weeks ago, so the plan is under way whatever day the suite
    // runs on, and a race a few days either side of today falls in its final
    // week. Built today, it would start on the coming Monday (ADR-0034) and
    // ask nothing of today at all; and a block's race has to sit in its last
    // week or the validator refuses it.
    await PlanRepository(
      store: store,
      now: () => DateTime.now().subtract(const Duration(days: 70)),
    ).create(profile);

    await tester.binding.setSurfaceSize(const Size(430, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          auth: FakeAuthRepository(signedIn: true, email: 'runner@example.com'),
          planStore: store,
          historySource: () async => runs,
        ),
      ),
    );
    // Pumped rather than settled: the coach mark plays a 3.4-second reveal and
    // `pumpAndSettle` would hang on it.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  group('the run-up', () {
    testWidgets('a taper week knows the race is coming', (tester) async {
      await open(tester, blockRacingIn(3));

      expect(find.text('Marathon in 3 days'), findsOneWidget);
      // And the day still has a session on it — three days out is not race day,
      // and taking the instruction off the card would be worse than saying
      // nothing about the race at all.
      expect(find.text('Race day'), findsNothing);
      expect(find.textContaining('Start'), findsWidgets);
    });

    testWidgets('a month out it says nothing', (tester) async {
      // Comfortably past kRaceHorizonDays (10) either way, but also past the
      // six-week block minimum (EDGE-18) a fresh block is now held to — 30
      // days used to satisfy the first without knowing about the second.
      await open(tester, blockRacingIn(60));

      expect(find.textContaining('Marathon in'), findsNothing);
      expect(find.text('Race day'), findsNothing);
    });
  });

  group('the day', () {
    testWidgets('race day is not a Tuesday', (tester) async {
      await open(tester, blockRacingIn(0));

      expect(find.text('Race day'), findsOneWidget);
      expect(find.textContaining('Marathon · '), findsOneWidget);
      expect(find.text('Start the race'), findsOneWidget);
      // Nothing left to bend. The week being adjusted would be the one they
      // have already run.
      expect(find.text('Adjust this week'), findsNothing);
    });

    testWidgets('the morning after asks how it went', (tester) async {
      await open(tester, blockRacingIn(-1));

      expect(find.text('How did the marathon go?'), findsOneWidget);
      expect(find.text('Add your result'), findsOneWidget);
      // Recording is still one tap away — a runner who raced on Sunday and
      // jogged on Wednesday must not find the app's core action missing.
      expect(find.text('Record a run'), findsOneWidget);
    });

    testWidgets('nobody is chased about the taper they skipped', (
      tester,
    ) async {
      // The runner has run nothing all week except the race, so every other
      // day of it is "missed". Opening the morning after a marathon with
      // "3 sessions missed this week" is true and is the worst sentence in the
      // product at that moment.
      final raceDay = _dateOnly(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      await open(
        tester,
        blockRacingIn(-1),
        runs: <RunSummary>[raceRun(raceDay)],
      );

      expect(find.textContaining('missed this week'), findsNothing);
    });

    testWidgets('and not in the run-up either', (tester) async {
      await open(tester, blockRacingIn(3));

      expect(find.textContaining('missed this week'), findsNothing);
    });
  });

  group('a plan with no race is untouched', () {
    testWidgets('a horizon runner sees an ordinary day', (tester) async {
      await open(tester, horizon());

      expect(find.text('Race day'), findsNothing);
      expect(find.textContaining('How did the'), findsNothing);
      expect(find.textContaining('in 3 days'), findsNothing);
    });

    testWidgets('and so does a parkrun regular', (tester) async {
      await open(tester, rhythm());

      expect(find.text('Race day'), findsNothing);
      expect(find.textContaining('How did the'), findsNothing);
      expect(find.text('Add your result'), findsNothing);
    });
  });

  group('closing the plan out', () {
    testWidgets('the sheet opens on what the log already says', (tester) async {
      final raceDay = _dateOnly(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      await open(
        tester,
        blockRacingIn(-1),
        runs: <RunSummary>[raceRun(raceDay)],
      );

      await tester.tap(find.text('Add your result'));
      await tester.pumpAndSettle();

      expect(find.byType(RaceResultSheet), findsOneWidget);
      // Pre-filled from the run, not an empty form (ADR-0017 — completion is
      // observed), and the confirm carries the figure being agreed to.
      expect(find.textContaining('That was my time · 3:42:18'), findsOneWidget);
      // And it says the disagreement is normal before the runner finds one.
      expect(find.textContaining('chip time'), findsOneWidget);
    });

    testWidgets('confirming ends the plan and shows the finish', (
      tester,
    ) async {
      final raceDay = _dateOnly(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      await open(
        tester,
        blockRacingIn(-1),
        runs: <RunSummary>[raceRun(raceDay)],
      );

      await tester.tap(find.text('Add your result'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('That was my time'));
      await tester.pumpAndSettle();

      expect(find.byType(PlanFinishScreen), findsOneWidget);
      expect(find.text('3:42:18'), findsOneWidget);

      final row = (await db.select(db.plans).get()).single;
      expect(row.status, planStatusCompleted);
      expect(row.raceTimeS, 13338);
    });

    testWidgets('a runner who did not race still gets an ending', (
      tester,
    ) async {
      await open(tester, blockRacingIn(-2));

      await tester.tap(find.text('Add your result'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('I did not race in the end'));
      await tester.pumpAndSettle();

      expect(find.byType(PlanFinishScreen), findsOneWidget);
      // The block is still counted. A screen that went quiet on them would be
      // the app agreeing that only the race mattered.
      expect(find.textContaining('do not stop counting'), findsOneWidget);

      final row = (await db.select(db.plans).get()).single;
      expect(row.status, planStatusAbandoned);
      expect(row.raceTimeS, isNull);
    });

    testWidgets('backing out changes nothing at all', (tester) async {
      await open(tester, blockRacingIn(-1));

      await tester.tap(find.text('Add your result'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();

      expect(find.byType(PlanFinishScreen), findsNothing);
      expect((await db.select(db.plans).get()).single.status, planStatusActive);
      // And the card is still asking, which is the point of it asking for
      // fourteen days rather than once.
      expect(find.text('How did the marathon go?'), findsOneWidget);
    });
  });

  group('the runner who never races', () {
    testWidgets('finds the plan closed rather than counting down forever', (
      tester,
    ) async {
      await open(tester, blockRacingIn(-(kRaceGraceDays + 3)));

      // Closed on the way in, from the log, so Home is not still describing a
      // marathon that happened last month.
      expect(
        (await db.select(db.plans).get()).single.status,
        planStatusAbandoned,
      );
      expect(find.textContaining('How did the'), findsNothing);
      expect(find.text('Race day'), findsNothing);
    });
  });
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
