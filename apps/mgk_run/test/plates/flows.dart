/// **The rooms behind a tap.**
///
/// `shell.dart` plates where a runner *stands*; this plates where they *go*.
/// Half the app is behind a control on one of the three tabs — the coach's
/// conversation, Settings and everything under it, a week opened, the block,
/// the form for a run the phone never saw — and none of it had ever been drawn
/// on a board. The gap was not an oversight so much as a cost: each of these
/// needs a fixture with more in it than one pump, which is exactly the note the
/// first board closed on.
///
/// **Two ways in, and the choice is not stylistic.**
///
/// A screen reached by a *labelled* control is driven: the plate taps the
/// control the runner taps, so the picture is evidence the route exists as
/// well as evidence of what it looks like. Twice already a screen on this board
/// has been rebuilt from arguments and drawn something the app never shows.
///
/// A screen reached by an *unlabelled* gesture target — the goal strip, a week
/// row — is built instead, from the plan the repository derived. That is still
/// the app's own object rather than a hand-made one: `create`, `weekFor` and
/// `pacesFor` do the deriving. What is lost is only the proof of the tap, and
/// the route is written on the board beside the plate instead.
///
/// Regenerate with:
///
///     flutter test test/plates/flows.dart
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/preview/fake_coach_service.dart';
import 'package:mgk_run/preview/fake_purchases.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_access.dart';
import 'package:mgk_run/src/features/coaching/domain/pace_model.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/readiness.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_button.dart';
import 'package:mgk_run/src/features/coaching/presentation/plan_block_screen.dart';
import 'package:mgk_run/src/features/coaching/presentation/plan_calendar_screen.dart';
import 'package:mgk_run/src/features/coaching/presentation/week_detail_screen.dart';
import 'package:mgk_run/src/features/history/data/run_editor.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_store.dart';
import 'package:mgk_run/src/features/profile/presentation/profile_screen.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';
import 'package:mgk_run/src/features/settings/domain/unit_settings.dart';

import 'fixture.dart';
import 'plate.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// The seeded app, with every seam a destination needs actually plugged in.
  ///
  /// The shell hides a control it cannot honour — no `runEditor` and there is
  /// no "Add a run", no chat client and the coach mark is absent rather than
  /// inert. So a board built on a half-wired shell would show a smaller app
  /// than the one that ships, and would do it silently.
  HomeShell app(
    DriftPlanStore store,
    List<RunSummary> runs, {
    int initialTab = 0,
    // **Pinned, never inferred.** Since ADR-0030 the coach mark is a door for
    // an unsubscribed runner: tapping it opens the gate sheet rather than the
    // conversation. The shell defaults to `free`, so the two conversation
    // plates below silently became plates of the gate the day that landed —
    // a valid PNG of the wrong screen, wearing the right caption, which is the
    // one failure a board cannot notice about itself.
    CoachAccess access = CoachAccess.subscribed,
  }) => HomeShell(
    // **With a name on it.** The fake defaults to none, so Settings correctly
    // drew "Nothing in particular" against the one row on the page that is
    // supposed to hold what the coach was told — the board reporting an empty
    // state as the design, which is the exact failure `shell.dart`'s header
    // catalogues four instances of.
    auth: FakeAuthRepository(
      signedIn: true,
      email: 'runner@example.com',
      name: 'Sam',
    ),
    planStore: store,
    historySource: () async => runs,
    coach: FakeCoachService(),
    runEditor: RunEditor(db: db),
    unitSettings: InMemoryUnitSettings(),
    initialTab: initialTab,
    access: access,
    // A shop, so the gate draws the state that ships rather than the state a
    // build with no RevenueCat key falls back to. Both are real; only one of
    // them is what a runner will meet.
    purchases: FakePurchases(),
    entitlements: FakeEntitlements(access),
  );

  /// Taps the coach's mark.
  ///
  /// [CoachButton] rather than [CoachReveal]: the reveal is a full-width
  /// `Positioned` that the mark sits at one end of, so its *centre* — where a
  /// tap by type lands — is out over the tab's scrolling content. The tap
  /// reported a miss and the plate drew an unopened sheet, which is the failure
  /// this board is least able to notice: nothing is wrong with the picture
  /// except that it is of the wrong thing.
  Future<void> tapCoach(WidgetTester tester) async {
    await tester.tap(find.byType(CoachButton));
    // Up, then the fake's 650ms think, then the reply painting.
    await settle(tester);
    await settle(tester);
  }

  /// Scrolls [label] into view and taps it.
  ///
  /// `ensureVisible` is not enough on Profile: the log header lives in a lazy
  /// sliver, so before the page is scrolled the row does not exist to be made
  /// visible and the finder throws rather than scrolling. This drags until the
  /// widget is built, which is the difference between off-screen and not-there.
  Future<void> reach(
    WidgetTester tester,
    String label, {
    Finder? within,
  }) async {
    final target = find.text(label);
    if (target.evaluate().isEmpty && within != null) {
      await tester.scrollUntilVisible(
        target,
        280,
        scrollable: find
            .descendant(of: within, matching: find.byType(Scrollable))
            .first,
      );
    }
    await tester.ensureVisible(target.last);
    await settle(tester);
    await tester.tap(target.last);
    await settle(tester);
  }

  /// A store with the marathon plan already in it, built by the repository.
  Future<DriftPlanStore> seeded() async {
    final store = DriftPlanStore(db);
    await PlanRepository(store: store).create(plateProfile());
    return store;
  }

  // --- The coach -------------------------------------------------------------
  //
  // The mark floats over all three tabs, and until now the board could only
  // show the mark. What opens when it is tapped is the paid product.

  testWidgets('the conversation, opened from the mark', (tester) async {
    final store = await seeded();
    final runs = plateLog();

    await plate(
      tester,
      'coach-conversation',
      app(store, runs),
      pixelRatio: 2,
      drive: (tester) async {
        await settle(tester);
        await tapCoach(tester);
      },
    );
  });

  testWidgets('and the coach answering a question a runner actually has', (
    tester,
  ) async {
    final store = await seeded();
    final runs = plateLog();

    await plate(
      tester,
      'coach-answering',
      app(store, runs),
      pixelRatio: 2,
      drive: (tester) async {
        await settle(tester);
        await tapCoach(tester);
        // A suggestion chip rather than typed text: the chips are the empty
        // conversation's whole affordance, and a plate of somebody typing
        // would show a keyboard the harness does not have.
        await tester.tap(find.textContaining('half marathon').last);
        await settle(tester);
        await settle(tester);
      },
    );
  });

  /// **The door a free runner meets instead** — the same mark, the other tier.
  ///
  /// New with ADR-0030 and never on a board: before it, the app offered the
  /// coach to everybody and let the Edge Function refuse, which surfaced as
  /// "The coach hit a problem. Please try again." A working paywall reading as
  /// broken software is the kind of thing only a picture catches.
  testWidgets('and the door, for a runner without a subscription', (
    tester,
  ) async {
    final store = await seeded();
    final runs = plateLog();

    await plate(
      tester,
      'coach-gate',
      app(store, runs, access: CoachAccess.free),
      pixelRatio: 2,
      drive: (tester) async {
        await settle(tester);
        await tapCoach(tester);
      },
    );
  });

  /// **The paywall**, reached the way a runner reaches it.
  ///
  /// Driven rather than built, and driven all the way from the coach mark,
  /// because the route is half the claim: this screen is only ever arrived at
  /// through the gate, and a plate constructed from arguments would prove the
  /// screen renders without proving anybody can get to it.
  ///
  /// Every figure on it comes from the fake storefront. Nothing here reads a
  /// price out of the binary, which is the property the screen exists to hold.
  testWidgets('and the paywall behind it', (tester) async {
    final store = await seeded();
    final runs = plateLog();

    await plate(
      tester,
      'paywall',
      app(store, runs, access: CoachAccess.free),
      pixelRatio: 2,
      drive: (tester) async {
        await settle(tester);
        await tapCoach(tester);
        await tester.tap(find.text('See the plans'));
        await settle(tester);
        await settle(tester);
      },
    );
  });

  // --- Settings --------------------------------------------------------------

  testWidgets('settings, from the icon on Profile', (tester) async {
    final store = await seeded();
    final runs = plateLog();

    await plate(
      tester,
      'settings',
      app(store, runs, initialTab: 2),
      pixelRatio: 2,
      drive: (tester) async {
        await settle(tester);
        await tester.tap(find.byTooltip('Settings'));
        await settle(tester);
      },
    );
  });

  testWidgets('and its foot, where the account and the law are', (
    tester,
  ) async {
    final store = await seeded();
    final runs = plateLog();

    await plate(
      tester,
      'settings-foot',
      app(store, runs, initialTab: 2),
      pixelRatio: 2,
      drive: (tester) async {
        await settle(tester);
        await tester.tap(find.byTooltip('Settings'));
        await settle(tester);
        // Scrolled to a row rather than dragged by a distance: the fold hides
        // permissions, backup and the account, and a fixed drag would land
        // somewhere different the next time a section is added above it.
        await tester.ensureVisible(find.text('Delete account').last);
        await settle(tester);
      },
    );
  });

  /// **The same screen for the runner who has no account — which is now most of
  /// them — and the reason this pair belongs on a board rather than in a test.**
  ///
  /// Settings was written while everybody was signed in, and after the sign-in
  /// wall came down it went on assuming one. The plate above could not show
  /// that, because its fixture is signed in like every other fixture here: the
  /// board was drawing the minority case and calling it the screen.
  ///
  /// Seen beside `settings`, three differences are the whole design question.
  /// The name the coach was given is now under a heading about the runner
  /// rather than under one about an account they do not have; the account
  /// section states the position instead of printing an address that is not
  /// there; and Sign out and Delete account are gone, replaced by the one row
  /// that does something — both of the others could only have failed.
  ///
  /// No `consentStore` passed, deliberately. With one, this fixture's twenty
  /// runs would trip the backup prompt and the plate would be a picture of a
  /// dialog. That prompt has its own plate on the arrival board, where the
  /// sequence it belongs to is.
  testWidgets('and the same screen with no account behind it', (tester) async {
    final store = await seeded();
    final runs = plateLog();

    await plate(
      tester,
      'settings-no-account',
      HomeShell(
        // Signed out, and introduced — the ordinary state of a runner who has
        // been using the app for a month without ever making an account.
        auth: FakeAuthRepository(),
        introStore: InMemoryIntroStore(done: true, name: 'Sam'),
        runnerName: 'Sam',
        planStore: store,
        historySource: () async => runs,
        coach: FakeCoachService(),
        runEditor: RunEditor(db: db),
        unitSettings: InMemoryUnitSettings(),
        initialTab: 2,
      ),
      pixelRatio: 2,
      drive: (tester) async {
        await settle(tester);
        await tester.tap(find.byTooltip('Settings'));
        await settle(tester);
      },
    );
  });

  // --- A run the phone did not see -------------------------------------------

  testWidgets('the form for a treadmill session or a race', (tester) async {
    final store = await seeded();
    final runs = plateLog();

    await plate(
      tester,
      'add-run',
      // Profile holds the log, so Profile is where a missing run is added.
      app(store, runs, initialTab: 2),
      pixelRatio: 2,
      drive: (tester) async {
        await settle(tester);
        await reach(tester, 'Add a run', within: find.byType(ProfileScreen));
      },
    );
  });

  testWidgets('the log, where a run is told apart by its shape', (
    tester,
  ) async {
    final store = await seeded();
    final runs = plateLog();

    await plate(
      tester,
      'run-list',
      app(store, runs, initialTab: 2),
      pixelRatio: 2,
      drive: (tester) async {
        await settle(tester);
        // Scrolled to the log rather than plated at the fold, because the log
        // is the bottom third of Profile and this board had never shown it —
        // which is how a shipped feature came to be reported as missing.
        await tester.scrollUntilVisible(
          find.text('Add a run'),
          280,
          scrollable: find
              .descendant(
                of: find.byType(ProfileScreen),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await settle(tester);
      },
    );
  });

  // --- The plan, deeper than the tab -----------------------------------------
  //
  // Built rather than driven: the week row and the goal strip are opaque
  // gesture targets with no label to find them by. Everything below still comes
  // out of the repository — `create` derived the block, `weekFor` derived the
  // week and `pacesFor` derived the paces, so a session's target pace on this
  // plate is the number the app would print.

  Future<(StoredPlan, PlanRepository)> plan() async {
    final repo = PlanRepository(store: DriftPlanStore(db));
    return (await repo.create(plateProfile()), repo);
  }

  testWidgets('a week opened, with the day the runner came from focused', (
    tester,
  ) async {
    final (stored, repo) = await plan();
    // Week four: far enough in to be a build week with real volume, rather
    // than week one, which is the gentlest week of the block and reads as a
    // plan that asks for nothing.
    final slot = stored.skeleton.weeks[3];
    final week = await repo.weekFor(stored, slot);

    await plate(
      tester,
      'week-detail',
      WeekDetailScreen(
        week: week,
        slot: slot,
        paces: pacesFor(stored.profile)!,
        profile: stored.profile,
        focusedWeekday: DateTime.wednesday,
      ),
      pixelRatio: 2,
    );
  });

  testWidgets('the whole block, which is the only place its shape is drawn', (
    tester,
  ) async {
    final (stored, _) = await plan();

    await plate(
      tester,
      'plan-block',
      PlanBlockScreen(
        plan: stored,
        // Read off the log rather than the profile, exactly as the shell reads
        // it: readiness is a fact about what the runner has done lately, and a
        // screen handed only a plan would have to fall back on a profile that
        // ages.
        readiness: assessReadiness(
          stored.profile,
          plateLog(),
          now: DateTime.now(),
        ),
      ),
      pixelRatio: 2,
    );
  });

  testWidgets('and the calendar, week by week', (tester) async {
    final (stored, _) = await plan();
    final weeks = <int, TrainingWeek>{
      for (var i = 0; i < 3; i++)
        i + 1: buildFallbackWeek(stored.skeleton.weeks[i], stored.profile),
    };

    await plate(
      tester,
      'plan-calendar',
      PlanCalendarScreen(plan: stored, weeks: weeks),
      pixelRatio: 2,
    );
  });
}
