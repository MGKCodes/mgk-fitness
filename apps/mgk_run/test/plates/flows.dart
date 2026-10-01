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
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_access.dart';
import 'package:mgk_run/src/features/coaching/domain/pace_model.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/race_day.dart';
import 'package:mgk_run/src/features/coaching/domain/readiness.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/presentation/plan_block_screen.dart';
import 'package:mgk_run/src/features/coaching/presentation/plan_calendar_screen.dart';
import 'package:mgk_run/src/features/coaching/presentation/week_detail_screen.dart';
import 'package:mgk_run/src/features/history/data/run_editor.dart';
import 'package:mgk_run/src/features/history/domain/run_draft.dart';
import 'package:mgk_run/src/features/history/presentation/run_form_screen.dart';
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

  /// The seeded app — see [plateApp], which this used to be.
  HomeShell app(
    DriftPlanStore store,
    List<RunSummary> runs, {
    int initialTab = 0,
    CoachAccess access = CoachAccess.subscribed,
  }) => plateApp(db, store, runs, initialTab: initialTab, access: access);

  /// Taps the coach's mark.
  ///
  /// [CoachMarkGlyph] rather than [CoachReveal]: the reveal is a full-width
  /// `Positioned` that the mark sits at one end of, so its *centre* — where a
  /// tap by type lands — is out over the tab's scrolling content. The tap
  /// reported a miss and the plate drew an unopened sheet, which is the failure
  /// this board is least able to notice: nothing is wrong with the picture
  /// except that it is of the wrong thing.
  ///
  /// **And [CoachMarkGlyph] rather than [CoachButton], which is what this was
  /// until the locked coach bar landed on 2026-09-10.** A free runner now meets
  /// a line of locked copy that plays and retracts, and while it is playing the
  /// reveal renders the open bar — `CoachMarkSurface` and `CoachMarkGlyph` —
  /// with no `CoachButton` in the tree at all. Every free-tier plate here
  /// failed on a finder that matched nothing, which is the loud version of this
  /// failure and the lucky one.
  ///
  /// The glyph is the right target on its own merits: it is the mark itself in
  /// both states, so it is present whether the bar is open or resting, and its
  /// centre is the mark's centre either way. That is the property the paragraph
  /// above actually wanted.
  Future<void> tapCoach(WidgetTester tester) async {
    await tester.tap(find.byType(CoachMarkGlyph));
    // Up, then the fake's 650ms think, then the reply painting.
    await settle(tester);
    await settle(tester);
  }

  /// A store with the marathon plan already in it, built by the repository.
  Future<DriftPlanStore> seeded() async {
    final store = DriftPlanStore(db);
    await seedPlan(store);
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

  /// The same screen at a size App Store Connect will actually accept.
  ///
  /// **Not a board plate.** `paywall` above is 393x852 at 2x like every other
  /// plate, which is right for reading a board and wrong for uploading: App
  /// Store Connect wants a review screenshot at a real iPhone screenshot size,
  /// and refuses arbitrary dimensions. `kMaxPhone` at 3x is 1290x2796, which is
  /// the 6.7-inch size Apple accepts, so this renders once rather than being
  /// upscaled from something smaller.
  ///
  /// `tool/export_store_assets.py` flattens it and checks the result.
  testWidgets('and the paywall at App Store screenshot size', (tester) async {
    final store = await seeded();
    final runs = plateLog();

    await plate(
      tester,
      'paywall-store',
      app(store, runs, access: CoachAccess.free),
      size: kMaxPhone,
      pixelRatio: 3,
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
  //
  // Settings with an account moved to `account.dart`, built rather than driven:
  // the shell hands Settings no entitlement source of its own, so a driven plate
  // always printed "Free" on a subscriber's card. Its foot went with the long
  // page it was the bottom of (the index fits one screen since 2026-09-11).

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
        await rest(tester);
        // **Scrolled clear of the header, then tapped.** `reach` scrolled the
        // row to the top edge, where Profile's pinned header sits over it, so
        // the tap landed on the header and the plate drew the log instead of
        // the form. The September board published that picture as `S6`: a
        // byte-for-byte copy of `S7`, captioned as a form nobody could see.
        final scrollable = find
            .descendant(
              of: find.byType(ProfileScreen),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.text('Add a run'),
          280,
          scrollable: scrollable,
        );
        await tester.drag(scrollable, const Offset(0, 240));
        await settle(tester);
        await tester.tap(find.text('Add a run'));
        await settle(tester);
        expect(find.text('Add a run'), findsWidgets);
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
    // Three weeks in, like every other plate of a runner on a plan: a block
    // built today has not started (ADR-0034), and its calendar calls next week
    // "this week" — which is `H6`'s subject, not these plates'.
    final store = DriftPlanStore(db);
    await seedPlan(store);
    final repo = PlanRepository(store: store);
    return ((await repo.load())!, repo);
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
      pushed(
        WeekDetailScreen(
          week: week,
          slot: slot,
          paces: pacesFor(stored.profile)!,
          profile: stored.profile,
          focusedWeekday: DateTime.wednesday,
        ),
      ),
      pixelRatio: 2,
      // Past the push: the screen slides in over the page it was opened from.
      drive: settle,
    );
  });

  /// **Race week opened** (ADR-0044): titled for what it is, with race day as
  /// the race and the runs before it short and easy.
  testWidgets('race week opened, with race day as the race', (tester) async {
    final store = DriftPlanStore(db);
    await seedPlan(store, racingIn: daysToSunday(), weeksIn: 10);
    final repo = PlanRepository(store: store);
    final stored = (await repo.load())!;
    final slot = stored.skeleton.weeks.last;
    final week = await repo.weekFor(stored, slot);

    await plate(
      tester,
      'week-race-week',
      pushed(
        WeekDetailScreen(
          week: week,
          slot: slot,
          paces: pacesFor(stored.profile)!,
          profile: stored.profile,
          raceDay: raceDayIn(stored, slot),
        ),
      ),
      pixelRatio: 2,
      drive: settle,
    );
  });

  // --- Correcting a run, and deleting one ------------------------------------

  /// A run as it was stored, for the edit form to open on.
  RunDraft storedRun() => RunDraft(
    startedAt: DateTime.now().subtract(const Duration(days: 2, hours: 3)),
    duration: const Duration(minutes: 41, seconds: 12),
    distanceMeters: 8050,
    type: kTypeOutdoor,
    rpe: 5,
  );

  testWidgets('a run being corrected, with Delete in the bar', (tester) async {
    await plate(
      tester,
      'run-edit',
      pushed(
        RunFormScreen(
          editor: RunEditor(db: db),
          runId: 'run-1',
          initial: storedRun(),
        ),
      ),
      pixelRatio: 2,
      drive: settle,
    );
  });

  testWidgets('and the question it asks before it deletes', (tester) async {
    await plate(
      tester,
      'run-delete',
      pushed(
        RunFormScreen(
          editor: RunEditor(db: db),
          runId: 'run-1',
          initial: storedRun(),
        ),
      ),
      pixelRatio: 2,
      drive: (tester) async {
        await settle(tester);
        await tester.tap(find.byTooltip('Delete this run'));
        await settle(tester);
        expect(find.text('Delete this run?'), findsOneWidget);
      },
    );
  });

  testWidgets('the whole block, which is the only place its shape is drawn', (
    tester,
  ) async {
    final (stored, _) = await plan();

    await plate(
      tester,
      'plan-block',
      pushed(
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
      ),
      pixelRatio: 2,
      // Past the push: the screen slides in over the page it was opened from.
      drive: settle,
    );
  });

  testWidgets('and the calendar, week by week', (tester) async {
    final (stored, _) = await plan();
    final weeks = <int, TrainingWeek>{
      for (var i = 0; i < 6; i++)
        i + 1: buildFallbackWeek(stored.skeleton.weeks[i], stored.profile),
    };

    await plate(
      tester,
      'plan-calendar',
      pushed(PlanCalendarScreen(plan: stored, weeks: weeks)),
      pixelRatio: 2,
      // Past the push: the screen slides in over the page it was opened from.
      drive: settle,
    );
  });
}
