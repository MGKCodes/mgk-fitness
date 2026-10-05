import 'package:mgk_run/src/core/brand.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/core/config/app_config.dart';
import 'package:mgk_run/src/features/auth/presentation/auth_gate.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_permission.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_store.dart';

void main() {
  const devAccounts = <DevAccount>[
    DevAccount(
      label: 'Runner A',
      email: 'a@mgkfitness.mgkcodes.com',
      password: 'password',
    ),
  ];

  testWidgets('signed-out shows the welcome screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          introStore: InMemoryIntroStore(),
          auth: FakeAuthRepository(),
        ),
      ),
    );
    // The gate reads its intro marker asynchronously, so frame one is blank.
    await tester.pump();

    expect(find.text(kAppName.toUpperCase()), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
  });

  testWidgets('welcome → dev quick sign-in routes through to home', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          introStore: InMemoryIntroStore(),
          auth: FakeAuthRepository(),
          devAccounts: devAccounts,
        ),
      ),
    );
    // The gate reads its intro marker asynchronously, so frame one is blank.
    await tester.pump();

    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();
    expect(find.text('Developer sign-in'), findsOneWidget);

    // Scroll it into view first. The screen gained the shared-profile
    // explainer under its heading, which is enough to push the developer
    // buttons below an 800x600 test viewport - they are reachable in the app,
    // which scrolls, and a tap on an off-screen widget is a warning rather
    // than a failure, so without this the failure surfaces two lines later as
    // a missing Home.
    final quickSignIn = find.widgetWithText(OutlinedButton, 'Runner A');
    await tester.ensureVisible(quickSignIn);
    await tester.pumpAndSettle();
    await tester.tap(quickSignIn);
    await tester.pumpAndSettle();

    // The fake flipped to signed-in and emitted; the real AuthGate swapped in
    // the shell — no re-wired preview page in between.
    expect(find.text('Record a run'), findsOneWidget);
  });

  /// Sign-in is a *state* of the signed-out flow rather than a pushed route, so
  /// there was nothing on the navigator for the system back gesture to pop and
  /// it fell through to the platform — quitting Runio from the second screen a
  /// new runner ever sees.
  testWidgets('system back inside the conversation does not leave the app', (
    tester,
  ) async {
    // Every step of the signed-out flow is a *state* of one widget rather than
    // a pushed route, so a back gesture finds nothing on the navigator to pop
    // and goes straight past the app to the launcher.
    //
    // The conversation is shorter than it was - it ends at the last permission
    // now rather than by creating a profile - so this stops part way through
    // rather than at the end. Running it to the end would land on Home, where
    // there is no conversation left to back out of and the guard would be
    // asserting nothing.
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          introStore: InMemoryIntroStore(),
          auth: FakeAuthRepository(),
          devAccounts: devAccounts,
          // There is no platform here to grant anything, and the intro waits on
          // a real dialog before it will move on.
          requestPermission: (_) async => true,
        ),
      ),
    );
    // The gate reads its intro marker asynchronously, so frame one is blank.
    await tester.pump();

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sounds good'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Sam');
    await tester.tap(find.byTooltip('Continue'));
    await tester.pumpAndSettle();
    // Answered, and deliberately not continued past: the next Continue is what
    // ends the intro.
    await tester.tap(find.text(introPermissions.first.cta));
    await tester.pumpAndSettle();

    // Deep in it, and no form was pushed to get here - which is the whole
    // point of the change this guards.
    expect(find.text('Sam'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);

    // What the hardware back button / back gesture does.
    final popped = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(
      popped,
      isTrue,
      reason: 'the app must handle the pop rather than let it exit',
    );
    expect(
      find.text('Get started'),
      findsOneWidget,
      reason: 'back out of the conversation lands on the welcome screen',
    );
  });

  testWidgets(
    'and again from sign-in reached via "I already have an account"',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(
            introStore: InMemoryIntroStore(),
            auth: FakeAuthRepository(),
            devAccounts: devAccounts,
          ),
        ),
      );
      // The gate reads its intro marker asynchronously, so frame one is blank.
      await tester.pump();

      await tester.tap(find.text('I already have an account'));
      await tester.pumpAndSettle();
      // The choices say both since 1.0.1, as Lift's do.
      expect(find.text('Sign in or create your account'), findsOneWidget);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();

      expect(find.text('Get started'), findsOneWidget);
    },
  );

  testWidgets('starts on home when already signed in', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          introStore: InMemoryIntroStore(),
          auth: FakeAuthRepository(
            signedIn: true,
            email: 'dev@mgkfitness.mgkcodes.com',
          ),
        ),
      ),
    );
    // The gate reads its intro marker asynchronously, so frame one is blank.
    await tester.pump();
    await tester.pump();

    expect(find.text('Record a run'), findsOneWidget);
  });

  /// Settings is pushed *over* the gate, so signing out swapped the tree
  /// underneath it and left the route on top: the dialog closed, the account
  /// line still read the same address, and sign out looked like a dead button.
  testWidgets('signing out from Settings lands on the welcome screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          introStore: InMemoryIntroStore(),
          auth: FakeAuthRepository(
            signedIn: true,
            email: 'dev@mgkfitness.mgkcodes.com',
          ),
        ),
      ),
    );
    // The gate reads its intro marker asynchronously, so frame one is blank.
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('dev@mgkfitness.mgkcodes.com'), findsOneWidget);

    // On the account screen, one tap from the card at the top of Settings.
    // It was a ListTile below the fold until Settings was rewritten on
    // 2026-09-11, then briefly a button on the index.
    await tester.tap(find.text('dev@mgkfitness.mgkcodes.com'));
    await tester.pumpAndSettle();
    final signOutRow = find.widgetWithText(OutlinedButton, 'Sign out');
    await tester.tap(signOutRow);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Get started'), findsOneWidget);
    expect(
      find.text('dev@mgkfitness.mgkcodes.com'),
      findsNothing,
      reason: 'the signed-out runner must not still be looking at Settings',
    );
  });

  testWidgets(
    'system back on the intro returns to welcome, not out of the app',
    (tester) async {
      // The form has had this guard since the original bug. Adding a step in
      // front of it and not its guard is how that bug came back wearing a new
      // screen, and the intro is now the first thing a new runner answers.
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(
            introStore: InMemoryIntroStore(),
            auth: FakeAuthRepository(),
            devAccounts: devAccounts,
          ),
        ),
      );
      // The gate reads its intro marker asynchronously, so frame one is blank.
      await tester.pump();

      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      // The intro opens on a greeting now, not on the name (ADR-0019): the
      // coach says hello, says what it is, and says what the app does before
      // it asks for anything.
      expect(find.textContaining('Thanks for downloading'), findsOneWidget);

      final popped = await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(
        popped,
        isTrue,
        reason: 'the app must handle the pop rather than let it exit',
      );
      expect(find.text('Get started'), findsOneWidget);
    },
  );
}

/// The settings list, for scrolling a row into view.
final Finder scrollable = find.byType(Scrollable).last;
