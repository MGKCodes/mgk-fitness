import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/preview/fake_coach_service.dart';
import 'package:mgk_run/src/features/auth/presentation/auth_gate.dart';
import 'package:mgk_run/src/features/auth/presentation/sign_in_screen.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_store.dart';
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
