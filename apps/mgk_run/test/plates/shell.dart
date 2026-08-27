import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/preview/fake_coach_service.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_access.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

import 'fixture.dart';
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

  testWidgets('home, as a runner on a plan actually sees it', (tester) async {
    final store = DriftPlanStore(db);
    await PlanRepository(store: store).create(plateProfile());
    final runs = plateLog();

    await plate(
      tester,
      'home-with-plan',
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
    await PlanRepository(store: store).create(plateProfile());
    final runs = plateLog();

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
    await PlanRepository(store: store).create(plateProfile());
    final runs = plateLog();

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

  /// **The same three tabs with the plan taken away** — which is the free
  /// product, not the paid one with its contents removed (ADR-0019).
  ///
  /// The pair only means anything seen together, and until now only half of it
  /// had chrome: `H2` and `H3` are tabs on a bare surface, so the nav bar and
  /// the coach mark were missing from exactly the plates the bet is judged on.
  /// A runner with no plan still has a coach and still has three tabs, and a
  /// board that dropped both was quietly arguing the opposite case.
  Future<void> freeShell(
    WidgetTester tester,
    String name, {
    required bool hasRuns,
    int initialTab = 0,
  }) async {
    // No `create` call: the store is empty, so the app decides for itself what
    // a runner with no plan is shown. Nothing here says "empty state" — the
    // screens work that out, which is the only way the plate can be evidence.
    final store = DriftPlanStore(db);
    final runs = hasRuns ? plateLog() : const <RunSummary>[];

    await plate(
      tester,
      name,
      HomeShell(
        auth: FakeAuthRepository(signedIn: true, email: 'runner@example.com'),
        planStore: store,
        historySource: () async => runs,
        coach: FakeCoachService(),
        initialTab: initialTab,
      ),
      pixelRatio: 2,
      drive: settle,
    );
  }

  testWidgets('home with no plan, which is the whole free product', (
    tester,
  ) async {
    await freeShell(tester, 'home-no-plan', hasRuns: true);
  });

  testWidgets('home on the first launch, before anything has happened', (
    tester,
  ) async {
    await freeShell(tester, 'home-first-launch', hasRuns: false);
  });

  testWidgets('the Plan tab with no plan — where a plan is asked for', (
    tester,
  ) async {
    await freeShell(tester, 'shell-plan-empty', hasRuns: true, initialTab: 1);
  });

  testWidgets('and a profile with nothing in it yet', (tester) async {
    await freeShell(
      tester,
      'shell-profile-empty',
      hasRuns: false,
      initialTab: 2,
    );
  });

  /// **The paywall line, in the screen it actually falls on.**
  ///
  /// These were card crops on a bare 393×420 surface, which is the one place
  /// the line cannot be judged: what matters is whether a free runner reads
  /// Home as a coherent app or as the paid one with a hole in it (ADR-0019),
  /// and a cropped card cannot answer that. Scrolled to the card rather than
  /// plated at the fold, because on a phone the card is the third thing down.
  ///
  /// [CoachAccess.subscribed] reaches the tab through the shell's new `access`
  /// seam. Before it, nothing in `lib/` ever constructed the subscribed value,
  /// so this state was unreachable in the running app and the plate that showed
  /// it was drawing something no runner could get to.
  Future<void> lastRunPlate(
    WidgetTester tester,
    String name, {
    required CoachAccess access,
  }) async {
    final store = DriftPlanStore(db);
    await PlanRepository(store: store).create(plateProfile());
    final runs = plateLog();

    await plate(
      tester,
      name,
      HomeShell(
        auth: FakeAuthRepository(signedIn: true, email: 'runner@example.com'),
        planStore: store,
        historySource: () async => runs,
        coach: FakeCoachService(),
        access: access,
      ),
      pixelRatio: 2,
      drive: (tester) async {
        await settle(tester);
        await tester.scrollUntilVisible(
          find.text('AGAINST THE PLAN'),
          220,
          scrollable: find.byType(Scrollable).first,
        );
        await settle(tester);
      },
    );
  }

  testWidgets('the last run, read against the session it answered', (
    tester,
  ) async {
    await lastRunPlate(
      tester,
      'last-run-subscribed',
      access: CoachAccess.subscribed,
    );
  });

  testWidgets('and the same run without a coach behind it', (tester) async {
    await lastRunPlate(tester, 'last-run-free', access: CoachAccess.free);
  });

  /// Home for a runner whose race is [racingIn] days away, with [extra] runs on
  /// top of the ordinary log.
  ///
  /// One helper for four plates, because the *only* thing that differs between
  /// them is the date on the plan — which is the claim ADR-0027's design rests
  /// on, and a board built four separate ways could not make it.
  Future<void> raceDayPlate(
    WidgetTester tester,
    String name, {
    required int racingIn,
    List<RunSummary> extra = const <RunSummary>[],
    Future<void> Function(WidgetTester tester)? drive,
  }) async {
    final store = DriftPlanStore(db);
    // **Built as though the runner started twelve weeks ago**, by winding the
    // repository's clock back — otherwise `create` anchors week 1 to this
    // Monday and the finish screen totals a block three days long. That is
    // exactly the thin-fixture failure this file's header is about: the screen
    // would be correct and the plate would still misrepresent it.
    final startedOn = dateOnly(
      DateTime.now().add(Duration(days: racingIn - 7 * 12)),
    );
    await PlanRepository(
      store: store,
      now: () => startedOn,
    ).create(plateProfile(racingIn: racingIn));
    // The ordinary log is pushed back behind the race, so the marathon is the
    // newest run rather than sharing a day with a routine 7 km — the plate
    // would otherwise show a runner who did a marathon and then went out again
    // that afternoon, which is a picture of nothing that happens.
    final runs = <RunSummary>[
      ...extra,
      for (final run in plateLog())
        if (extra.isEmpty ||
            DateTime.now().difference(run.startedAt).inDays >= 3)
          run,
    ];

    await plate(
      tester,
      name,
      HomeShell(
        auth: FakeAuthRepository(signedIn: true, email: 'runner@example.com'),
        planStore: store,
        historySource: () async => runs,
        coach: FakeCoachService(),
      ),
      pixelRatio: 2,
      drive: drive ?? settle,
    );
  }

  testWidgets('the taper week, three days out', (tester) async {
    await raceDayPlate(tester, 'shell-race-run-up', racingIn: 3);
  });

  testWidgets('race day itself', (tester) async {
    await raceDayPlate(tester, 'shell-race-day', racingIn: 0);
  });

  testWidgets('the morning after, with the result still untold', (
    tester,
  ) async {
    await raceDayPlate(
      tester,
      'shell-race-after',
      racingIn: -1,
      extra: <RunSummary>[_theRace()],
    );
  });

  testWidgets('the sheet that reads the result off the log', (tester) async {
    await raceDayPlate(
      tester,
      'shell-race-result-sheet',
      racingIn: -1,
      extra: <RunSummary>[_theRace()],
      drive: (tester) async {
        await settle(tester);
        await tester.tap(find.text('Add your result'));
        await settle(tester);
      },
    );
  });

  testWidgets('and the end of sixteen weeks', (tester) async {
    await raceDayPlate(
      tester,
      'shell-plan-finish',
      racingIn: -1,
      extra: <RunSummary>[_theRace()],
      // Driven all the way through rather than pushed directly. The finish
      // screen is only ever reached by confirming a result, and a plate that
      // constructed one by hand would be the thin-fixture mistake this file
      // exists to avoid — it would not prove the plan had actually closed.
      drive: (tester) async {
        await settle(tester);
        await tester.tap(find.text('Add your result'));
        await settle(tester);
        await tester.tap(find.textContaining('That was my time'));
        await settle(tester);
      },
    );
  });
}

/// The marathon, as the phone recorded it: 42.61 km, because a marathon on a
/// GPS is always a little long.
RunSummary _theRace() {
  final yesterday = DateTime.now().subtract(const Duration(days: 1));
  return RunSummary(
    id: 'the-race',
    startedAt: DateTime(yesterday.year, yesterday.month, yesterday.day, 9),
    duration: const Duration(hours: 3, minutes: 42, seconds: 18),
    distanceMeters: 42610,
    avgPaceSecondsPerKm: 313,
  );
}
