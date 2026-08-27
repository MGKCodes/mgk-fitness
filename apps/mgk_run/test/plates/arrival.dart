/// **The half of the app that happens before there is an app.**
///
/// Everything on the rest of the board belongs to a runner who already has an
/// account, and most of it to one who already has a plan. Neither is true of
/// anybody opening this for the first time, and the screens they *do* meet —
/// the welcome, the coach's first conversation, each permission asked one at a
/// time, the address and the password — had never been drawn anywhere.
///
/// **Walked, not assembled.** Every plate here comes out of the real
/// [AuthGate] or the real [CoachFlow], driven by tapping the control a runner
/// taps. Nothing is pushed onto a navigator by hand. That matters more here
/// than anywhere else on the board: this is a *sequence*, and a sequence
/// rebuilt screen by screen would show each step correctly while proving
/// nothing about whether one leads to the next. Sign-up moved into the
/// conversation itself (ADR-0018), so the only honest way to picture it is to
/// have the conversation.
///
/// The two acts are two moments, and deliberately not one (ADR-0019): this ends
/// with a free account and a working run tracker. A plan is somewhere a runner
/// goes afterwards, not the toll for finishing sign-up.
///
/// Regenerate with:
///
///     flutter test test/plates/arrival.dart
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/preview/fake_coach_service.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/auth/presentation/auth_gate.dart';
import 'package:mgk_run/src/features/coaching/data/drift_plan_store.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_flow.dart';
import 'package:mgk_run/src/features/legal/domain/disclaimer_store.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_permission.dart';
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
    coach: FakeCoachService(),
    consentStore: InMemoryBackupConsent(),
    historySource: () async => const [],
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
    for (final permission in introPermissions) {
      await tapText(tester, permission.cta);
      await tapText(tester, 'Continue');
    }
  }

  // --- Act one: arriving -----------------------------------------------------

  testWidgets('the first thing anybody sees', (tester) async {
    await plate(tester, 'arrive-welcome', cold(), pixelRatio: 2);
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

  testWidgets('the account is asked for in the conversation, not on a form', (
    tester,
  ) async {
    await plate(
      tester,
      'arrive-password',
      cold(),
      pixelRatio: 2,
      drive: (tester) async {
        await tester.pumpAndSettle();
        await tapText(tester, 'Get started');
        await tapText(tester, 'Sounds good');
        await say(tester, 'Sam', 'Continue');
        await throughPermissions(tester);
        await say(tester, 'sam@example.com', 'Continue');
      },
    );
  });

  testWidgets('and it ends on a working app, not on a plan', (tester) async {
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
        await say(tester, 'sam@example.com', 'Continue');
        await tester.enterText(find.byType(TextField).last, 'password');
        await tester.pumpAndSettle();
        await tapTip(tester, 'Create my profile');
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

  // --- Act two: asking for a plan --------------------------------------------
  //
  // A separate moment, reached from the Plan tab rather than from sign-up. The
  // flow is opened directly here because the tab's empty state is already on
  // the board as `shell-plan-empty` — what is missing is what happens after it.

  Widget planFlow({bool acknowledged = true}) => CoachFlow(
    coach: FakeCoachService(),
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
        await tester.enterText(find.byType(TextField).first, '5k in 22');
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
}
