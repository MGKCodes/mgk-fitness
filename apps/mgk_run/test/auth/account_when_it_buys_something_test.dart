import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/preview/fake_coach_service.dart';
import 'package:mgk_run/src/features/auth/presentation/auth_gate.dart';
import 'package:mgk_run/src/features/auth/presentation/sign_in_screen.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_store.dart';
import 'package:mgk_run/src/features/settings/domain/backup_consent.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// **An account is not the price of using this app.**
///
/// Everything used to sit behind one: `AuthGate` returned the signed-out flow
/// whenever there was no session, so recording a run, reading the log and
/// opening Profile all required an email and a password first. Nothing about
/// that was load-bearing. The on-device database has been the source of truth
/// since the scaffold (CLAUDE.md rule 1) and Supabase has always been a backup
/// rather than the store — the gate asked for an account because the only door
/// in happened to be built out of one.
///
/// So the app opens on a working tracker, and the ask moves to the two moments
/// it buys the runner something:
///
///   * **a plan**, because the coach is a model behind an Edge Function and
///     every request costs money, so there has to be somebody to attribute it
///     to;
///   * **backup**, because that is the entire thing an account does for a
///     database that already works offline.
///
/// This file holds both halves: that the app runs without one, and that the
/// gate still stands where it earns itself.
void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    required FakeAuthRepository auth,
    IntroStore? intro,
    BackupConsentStore? consent,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: AuthGate(
          auth: auth,
          // Already introduced, so the gate goes straight to the shell. The
          // conversation itself is covered by `onboarding_flow_test.dart`.
          introStore: intro ?? InMemoryIntroStore(done: true, name: 'Sam'),
          coach: FakeCoachService(),
          historySource: () async => const [],
          consentStore: consent,
          requestPermission: (_) async => true,
        ),
      ),
    );
    // The gate reads its intro marker asynchronously, so frame one is blank.
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('a runner with no account lands on a working tracker', (
    tester,
  ) async {
    await pumpApp(tester, auth: FakeAuthRepository());

    // The tracker, not a form. This is the assertion the whole change exists
    // for: nothing here asked who they are.
    expect(find.text('Record a run'), findsOneWidget);
    expect(find.byType(SignInScreen), findsNothing);
    expect(find.text('Get started'), findsNothing);
  });

  testWidgets('the name survives the intro even with no account to hold it', (
    tester,
  ) async {
    // `currentName` reads auth user metadata, so it answers null for everybody
    // signed out. Without the local copy the runner tells the coach their name
    // and the coach forgets it on the way to the first screen.
    final auth = FakeAuthRepository();
    await pumpApp(
      tester,
      auth: auth,
      intro: InMemoryIntroStore(done: true, name: 'Sam'),
    );

    expect(auth.currentName, isNull);
    expect(find.text('Record a run'), findsOneWidget);
  });

  /// **The wire both ends of which were built, and which nothing joined.**
  ///
  /// `IntroStore` gained a name and `HomeShell` gained a `runnerName` to take
  /// one, and then no caller passed it: `AuthGate._localName` was written three
  /// times and read nowhere. Every assertion about the name up to here was
  /// about the *store*, so the suite was entirely satisfied while the app still
  /// forgot the name on the way to the first screen it is used on.
  ///
  /// Asserted where a runner would actually notice. Sign-up hides its name
  /// field when the coach has already asked, so a name that arrived is a form
  /// with no name on it — and one that got lost is a runner being asked their
  /// name twice in five minutes.
  testWidgets('and reaches the screens that use it', (tester) async {
    final auth = FakeAuthRepository();
    await pumpApp(
      tester,
      auth: auth,
      intro: InMemoryIntroStore(done: true, name: 'Sam'),
    );

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Build a plan'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, 'First name (optional)'),
      findsNothing,
      reason:
          'the coach asked in the intro; asking again loses the point of '
          'having asked in a conversation at all',
    );

    // And it travels onto the account being made, rather than being dropped at
    // the door of the one screen that could still have carried it.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'sam@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'hunter2222',
    );
    await tester.tap(find.widgetWithText(PrimaryButton, 'Sign up'));
    // Fixed pumps, not `pumpAndSettle`: a submitting `PrimaryButton` draws an
    // indeterminate spinner, and settle never returns on a screen showing one.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(auth.lastName, 'Sam');
  });

  /// **The second gate, which the change that built the first left owing.**
  ///
  /// Backup is the entire thing an account does for a database that already
  /// works offline, and the switch was ungated: it would have flipped to On,
  /// written a consent, and mirrored nothing — every push failing on a
  /// row-level policy with no user to attribute a row to. This is the gate seen
  /// through the whole app rather than through the screen, because the defect
  /// that is easy to reintroduce is not the check itself but the shell
  /// forgetting to hand Settings the thing that raises it.
  testWidgets('and turning on backup is the other place it is asked', (
    tester,
  ) async {
    final consent = InMemoryBackupConsent();
    await pumpApp(tester, auth: FakeAuthRepository(), consent: consent);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    // The row opens the backup screen; the switch on it is what asks. Two
    // taps since the 2026-09-11 rewrite, where it used to be one — the switch
    // moved to sit beside the paragraph that makes its consent informed.
    await tester.tap(find.text('Back up my data'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(await consent.read(), BackupConsent.unknown);
  });

  testWidgets('asking for a plan is where the account is asked for', (
    tester,
  ) async {
    await pumpApp(tester, auth: FakeAuthRepository());

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Build a plan'));
    await tester.pumpAndSettle();

    // Sign-up, raised at the moment they asked for the thing it pays for -
    // rather than ninety seconds after install, when they had not.
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('and backing out of it leaves the app working', (tester) async {
    await pumpApp(tester, auth: FakeAuthRepository());

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Build a plan'));
    await tester.pumpAndSettle();

    // A refused sign-up is not a dead end. It is pushed as a route rather than
    // swapping the shell out underneath them precisely so that backing out
    // returns them to the tab they were on, still working.
    final popped = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(popped, isTrue);
    expect(find.byType(SignInScreen), findsNothing);
    expect(find.text('Build a plan'), findsOneWidget);
  });

  /// **A gate that opens has to get out of the way.**
  ///
  /// The sign-in screen was written as a state of the signed-out flow, where a
  /// session swaps the whole subtree for the shell and there is nothing left to
  /// dismiss. Raised from inside the running app it is a route over a shell
  /// that stays exactly where it is, and nothing popped it: the runner
  /// completed the sign-up they were asked for and sat on the finished form,
  /// with the thing they had asked for waiting behind a back gesture nobody had
  /// told them to make.
  testWidgets('and a completed sign-up returns them to what they asked for', (
    tester,
  ) async {
    final auth = FakeAuthRepository();
    await pumpApp(tester, auth: auth);

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Build a plan'));
    await tester.pumpAndSettle();
    expect(find.byType(SignInScreen), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'sam@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'hunter2222',
    );
    await tester.tap(find.widgetWithText(PrimaryButton, 'Sign up'));
    // Fixed pumps: a submitting `PrimaryButton` draws an indeterminate spinner,
    // and settle never returns on a screen showing one.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(auth.isSignedIn, isTrue);
    expect(
      find.byType(SignInScreen),
      findsNothing,
      reason:
          'the gate has been satisfied, so it has no business still being '
          'the screen the runner is looking at',
    );
  });

  testWidgets('a runner who already has an account is not asked again', (
    tester,
  ) async {
    await pumpApp(
      tester,
      auth: FakeAuthRepository(signedIn: true, email: 'sam@example.com'),
    );

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Build a plan'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsNothing);
  });
}
