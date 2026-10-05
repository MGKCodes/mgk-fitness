/// **The half of the app that happens before there is an app.**
///
/// Everything on the rest of the board belongs to a runner who already has an
/// account, and most of it to one who already has a plan. Neither is true of
/// anybody opening this for the first time, and the screens they *do* meet —
/// the welcome, the coach's first conversation and each permission asked one at
/// a time — had never been drawn anywhere.
///
/// **Walked, not assembled.** Every plate here comes out of the real
/// [AuthGate] or the real [CoachFlow], driven by tapping the control a runner
/// taps. Nothing is pushed onto a navigator by hand. That matters more here
/// than anywhere else on the board: this is a *sequence*, and a sequence
/// rebuilt screen by screen would show each step correctly while proving
/// nothing about whether one leads to the next.
///
/// **It no longer ends in an account.** The intro used to ask for an address
/// and a password as two more turns; the app now opens on a working tracker and
/// asks for an account only where one buys something. So this act ends on Home,
/// signed out, with everything living on the phone.
///
/// The two acts are two moments, and deliberately not one (ADR-0019): this one
/// ends with a working run tracker and nothing signed in. A plan is somewhere a
/// runner goes afterwards, not the toll for finishing sign-up.
///
/// Regenerate with:
///
///     flutter test test/plates/arrival.dart
library;

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/preview/fake_coach_service.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/auth/presentation/auth_gate.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/coaching/domain/intake_conversation.dart';
import 'package:mgk_run/src/features/coaching/domain/intake_slots.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_flow.dart';
import 'package:mgk_run/src/features/coaching/presentation/plan_reveal_screen.dart';
import 'package:mgk_run/src/features/history/data/run_editor.dart';
import 'package:mgk_run/src/features/legal/domain/disclaimer_store.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_permission.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_store.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';
import 'package:mgk_run/src/features/settings/domain/backup_consent.dart';

import 'fixture.dart';
import 'plate.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// The app as it opens on a phone that has never run it.
  ///
  /// [requestPermission] answers yes without a system dialog, which is the only
  /// part of this that is faked. The consent store is in memory so the plate
  /// does not write a file into the repository every time the board is built.
  Widget cold() => AuthGate(
    auth: FakeAuthRepository(),
    // In memory, not the real marker file. The gate reads this before it draws
    // anything, and a plate that waits on a filesystem the test framework does
    // not have would render a blank frame and call it the welcome screen.
    introStore: InMemoryIntroStore(),
    coach: FakeCoachService(),
    consentStore: InMemoryBackupConsent(),
    historySource: () async => const [],
    // Somewhere to write a run, as the app has: Home's today card offers a
    // treadmill run only when there is.
    runEditor: RunEditor(db: db),
    requestPermission: (_) async => true,
  );

  /// Taps [label], scrolling it into view first when the fold is in the way.
  ///
  /// The intro is a conversation that grows downwards, so on a 393×852 surface
  /// its control is sometimes below the last thing said. The tests this is
  /// modelled on all set a 1400pt-tall phone to sidestep that; a plate cannot,
  /// because the fold is the thing it is drawn to show.
  Future<void> tapText(WidgetTester tester, String label) async {
    final target = find.text(label).last;
    await tester.ensureVisible(target);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> tapTip(WidgetTester tester, String tooltip) async {
    await tester.tap(find.byTooltip(tooltip));
    await tester.pumpAndSettle();
  }

  /// Answers the step on screen and moves to the next one.
  Future<void> say(WidgetTester tester, String text, String tooltip) async {
    await tester.enterText(find.byType(TextField).last, text);
    await tester.pumpAndSettle();
    await tapTip(tester, tooltip);
  }

  /// Answers the coach until the intake is complete.
  ///
  /// The preview coach asks four questions, not one. The flow's own tests get
  /// away with a single answer because the fake they inject finishes
  /// immediately; this uses the same scripted coach the web preview does, so
  /// the plate has to hold the conversation the runner would. Bounded rather
  /// than `while (true)`: a script that stops completing should fail the plate
  /// rather than hang it.
  Future<void> untilReviewed(WidgetTester tester) async {
    const answers = <String>[
      'A marathon in November',
      'About 40 km a week, longest was 18',
      'Most days, five or six',
      '5k in 22',
    ];
    for (final answer in answers) {
      if (find.text('Review details').evaluate().isNotEmpty) return;
      await tester.enterText(find.byType(TextField).first, answer);
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pumpAndSettle();
    }
  }

  /// Every permission in the script, answered yes.
  ///
  /// Driven off [introPermissions] rather than a fixed list of taps, for the
  /// reason the flow tests give: adding one should not silently strand this on
  /// a screen it does not know how to leave.
  Future<void> throughPermissions(WidgetTester tester) async {
    for (final permission in introPermissionsFor(defaultTargetPlatform)) {
      await tapText(tester, permission.cta);
      await tapText(tester, 'Continue');
    }
  }

  // --- Act one: arriving -----------------------------------------------------

  testWidgets('the first thing anybody sees', (tester) async {
    await plate(
      tester,
      'arrive-welcome',
      cold(),
      pixelRatio: 2,
      // **Settled, not pumped once.** The gate reads the intro store before it
      // draws anything, and then the welcome staggers in over a second and a
      // half. The September board took this plate at 0.7 s — a blank frame —
      // and published it as `B1`, captioned "two doors and a wordmark".
      drive: (tester) async {
        await settle(tester);
        await settle(tester);
      },
    );
  });

  testWidgets('the coach introduces itself', (tester) async {
    await plate(
      tester,
      'arrive-greeting',
      cold(),
      pixelRatio: 2,
      drive: (tester) async {
        await tester.pumpAndSettle();
        await tapText(tester, 'Get started');
      },
    );
  });

  testWidgets('and asks what to call them', (tester) async {
    await plate(
      tester,
      'arrive-name',
      cold(),
      pixelRatio: 2,
      drive: (tester) async {
        await tester.pumpAndSettle();
        await tapText(tester, 'Get started');
        await tapText(tester, 'Sounds good');
      },
    );
  });

  testWidgets('one permission at a time, with a reason attached', (
    tester,
  ) async {
    await plate(
      tester,
      'arrive-permission',
      cold(),
      pixelRatio: 2,
      drive: (tester) async {
        await tester.pumpAndSettle();
        await tapText(tester, 'Get started');
        await tapText(tester, 'Sounds good');
        await say(tester, 'Sam', 'Continue');
      },
    );
  });

  testWidgets('an answer is acknowledged rather than just accepted', (
    tester,
  ) async {
    await plate(
      tester,
      'arrive-permission-allowed',
      cold(),
      pixelRatio: 2,
      drive: (tester) async {
        await tester.pumpAndSettle();
        await tapText(tester, 'Get started');
        await tapText(tester, 'Sounds good');
        await say(tester, 'Sam', 'Continue');
        await tapText(tester, introPermissions.first.cta);
      },
    );
  });

  testWidgets('then Health, asked for steps and nothing else', (tester) async {
    // iPhone only: Android has no Health step at all (`introPermissionsFor`).
    // New wording in build 26 — it used to promise runs imported from a watch,
    // which nothing ever did.
    await plate(
      tester,
      'arrive-health',
      cold(),
      pixelRatio: 2,
      drive: (tester) async {
        await tester.pumpAndSettle();
        await tapText(tester, 'Get started');
        await tapText(tester, 'Sounds good');
        await say(tester, 'Sam', 'Continue');
        await tapText(tester, introPermissions.first.cta);
        await tapText(tester, 'Continue');
      },
    );
  });

  testWidgets('and it ends on a working app, with no account at all', (
    tester,
  ) async {
    await plate(
      tester,
      'arrive-home',
      cold(),
      pixelRatio: 2,
      drive: (tester) async {
        await tester.pumpAndSettle();
        await tapText(tester, 'Get started');
        await tapText(tester, 'Sounds good');
        await say(tester, 'Sam', 'Continue');
        await throughPermissions(tester);
        // Fixed pumps from here: the shell it lands on plays the coach mark's
        // reveal on a timer, and `pumpAndSettle` would never come back.
        await settle(tester);
      },
    );
  });

  testWidgets('signing back in, which is a different act', (tester) async {
    await plate(
      tester,
      'arrive-sign-in',
      cold(),
      pixelRatio: 2,
      drive: (tester) async {
        await tester.pumpAndSettle();
        await tapText(tester, 'I already have an account');
      },
    );
  });

  testWidgets('and its email form, which starts on signing in', (tester) async {
    await plate(
      tester,
      'arrive-sign-in-email',
      cold(),
      pixelRatio: 2,
      drive: (tester) async {
        await tester.pumpAndSettle();
        await tapText(tester, 'I already have an account');
        await tapText(tester, 'Continue with email');
      },
    );
  });

  // --- Act two: asking for a plan --------------------------------------------
  //
  // A separate moment, reached from the Plan tab rather than from sign-up. The
  // flow is opened directly here because the tab's empty state is already on
  // the board as `shell-plan-empty` — what is missing is what happens after it.

  Widget planFlow({bool acknowledged = true, CoachClient? coach}) => CoachFlow(
    coach: coach ?? FakeCoachService(),
    // The repository builds it, so the plan on the reveal is a real one.
    buildPlan: (profile) =>
        PlanRepository(store: DriftPlanStore(db)).create(profile),
    disclaimer: InMemoryDisclaimerStore(acknowledged: acknowledged),
    name: 'Sam',
  );

  testWidgets('the notice that comes before any plan', (tester) async {
    await plate(
      tester,
      'plan-disclaimer',
      planFlow(acknowledged: false),
      pixelRatio: 2,
      drive: (tester) async => tester.pumpAndSettle(),
    );
  });

  testWidgets('what are you training for', (tester) async {
    await plate(
      tester,
      'plan-shape',
      planFlow(),
      pixelRatio: 2,
      drive: (tester) async => tester.pumpAndSettle(),
    );
  });

  testWidgets('the intake conversation, part way through', (tester) async {
    await plate(
      tester,
      'plan-intake',
      planFlow(),
      pixelRatio: 2,
      drive: (tester) async {
        await tester.pumpAndSettle();
        await tapText(tester, 'I have a race coming up');
        await tester.enterText(
          find.byType(TextField).first,
          'A marathon in January',
        );
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await tester.pumpAndSettle();
      },
    );
  });

  testWidgets('what it heard, handed back to be corrected', (tester) async {
    await plate(
      tester,
      'plan-confirm',
      planFlow(),
      pixelRatio: 2,
      drive: (tester) async {
        await tester.pumpAndSettle();
        await tapText(tester, 'I have a race coming up');
        await untilReviewed(tester);
        await tapText(tester, 'Review details');
      },
    );
  });

  testWidgets('and the plan it built', (tester) async {
    await plate(
      tester,
      'plan-reveal',
      planFlow(),
      pixelRatio: 2,
      drive: (tester) async {
        await tester.pumpAndSettle();
        await tapText(tester, 'I have a race coming up');
        await untilReviewed(tester);
        await tapText(tester, 'Review details');
        await tapText(tester, 'Build my plan');
      },
    );
  });

  // --- A race too close for a block ------------------------------------------
  //
  // New in build 26 (EDGE-18, test sheet D18): a race less than six weeks
  // after the coming Monday is refused, because the block would have to put
  // race day inside base training. The sheet expects the refusal *before*
  // anything is built, and since build 27 the confirmation screen gives it,
  // with Build my plan held until the date moves or the race comes out. The
  // second plate is the builder's own refusal, for anything that reaches it
  // another way: it can no longer be reached from the first, so it is built.

  testWidgets('a race three weeks out, as the confirmation hears it', (
    tester,
  ) async {
    await plate(
      tester,
      'plan-near-race-confirm',
      planFlow(coach: _NearRaceCoach()),
      pixelRatio: 2,
      drive: (tester) async {
        await tester.pumpAndSettle();
        await tapText(tester, 'I have a race coming up');
        await untilReviewed(tester);
        await tapText(tester, 'Review details');
      },
    );
  });

  testWidgets('and what the builder says if one reaches it', (tester) async {
    // The real repository and the real validator, so the words on the plate
    // are the ones a refusal actually produces rather than a fake's.
    final nearRace = RunnerProfile(
      goalDistanceMeters: 10000,
      eventDate: DateTime.now().add(const Duration(days: 21)),
      currentWeeklyMeters: 30000,
      longestRecentMeters: 12000,
      daysPerWeek: 4,
      availableWeekdays: const <int>{1, 3, 5, 6},
      timeTrialDistanceMeters: 5000,
      timeTrialDuration: const Duration(minutes: 25),
    );
    await plate(
      tester,
      'plan-near-race',
      PlanRevealScreen(
        build: () => PlanRepository(store: DriftPlanStore(db)).create(nearRace),
        onDone: (_) {},
        onChangeDetails: () {},
      ),
      pixelRatio: 2,
      drive: (tester) async {
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 700));
      },
    );
  });

  // --- Act three: where an account earns itself ------------------------------
  //
  // The third moment, and the last one that had never been drawn. Act one ends
  // with a working tracker and nothing signed in; act two is a plan, which the
  // runner goes and asks for. This is the other half of the bargain — the app
  // asking *them* for something, once, at the point where it can say what the
  // account is for and point at the thing it would protect.
  //
  // It belongs on this board rather than beside Settings because it is a
  // sequence, like act one: a dialog, a sign-up, and a return to where they
  // were. A plate of the dialog alone would show the ask without the cost.

  /// A month-old install: introduced, signed out, and with runs on it.
  ///
  /// The consent store is unanswered, which is what makes the prompt due. Two
  /// runs rather than the full fixture log, because the number is *in the copy*
  /// — this is the moment it fires, not a picture of a runner who has been at
  /// it for a year.
  Widget settledIn() => AuthGate(
    auth: FakeAuthRepository(),
    introStore: InMemoryIntroStore(done: true, name: 'Sam'),
    coach: FakeCoachService(),
    consentStore: InMemoryBackupConsent(),
    historySource: () async => <RunSummary>[
      for (var i = 1; i <= 2; i++)
        RunSummary(
          id: 'run-$i',
          startedAt: DateTime.now().subtract(Duration(days: i * 2)),
          duration: const Duration(minutes: 31),
          distanceMeters: 5400,
          avgPaceSecondsPerKm: 344,
          points: plateRoute(i),
        ),
    ],
    runEditor: RunEditor(db: db),
    requestPermission: (_) async => true,
  );

  testWidgets('the ask, once there is something worth keeping', (tester) async {
    await plate(
      tester,
      'keep-runs-safe',
      settledIn(),
      pixelRatio: 2,
      // Fixed pumps: the shell underneath plays the coach mark's reveal on a
      // timer, so `pumpAndSettle` would never return even with a dialog up.
      drive: (tester) async {
        await settle(tester);
        await settle(tester);
      },
    );
  });

  testWidgets('and the sign-up it raises, which already knows the name', (
    tester,
  ) async {
    await plate(
      tester,
      'account-gate',
      settledIn(),
      pixelRatio: 2,
      drive: (tester) async {
        await settle(tester);
        await settle(tester);
        await tester.tap(find.text('Back them up'));
        await settle(tester);
      },
    );
  });

  testWidgets('and the email form behind its third button', (tester) async {
    await plate(
      tester,
      'account-gate-email',
      settledIn(),
      pixelRatio: 2,
      drive: (tester) async {
        await settle(tester);
        await settle(tester);
        await tester.tap(find.text('Back them up'));
        await settle(tester);
        await tester.tap(find.text('Continue with email'));
        await settle(tester);
      },
    );
  });
}

/// The preview's scripted coach, hearing a race three weeks away rather than
/// sixteen. Only the date differs; every line it says is the script's own.
class _NearRaceCoach extends FakeCoachService {
  @override
  Future<IntakeTurn> intake({
    required IntakeSlots slots,
    required List<IntakeMessage> history,
  }) async {
    final turn = await super.intake(slots: slots, history: history);
    if (turn.extracted.eventDate == null) return turn;
    return IntakeTurn(
      reply: turn.reply,
      extracted: IntakeSlots(
        goalDistanceMeters: turn.extracted.goalDistanceMeters,
        eventDate: DateTime.now().add(const Duration(days: 21)),
      ),
    );
  }
}
