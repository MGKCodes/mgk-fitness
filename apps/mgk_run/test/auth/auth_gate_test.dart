import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/core/config/app_config.dart';
import 'package:mgk_run/src/features/auth/presentation/auth_gate.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_permission.dart';

void main() {
  const devAccounts = <DevAccount>[
    DevAccount(label: 'Runner A', email: 'a@runio.app', password: 'password'),
  ];

  testWidgets('signed-out shows the welcome screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: AuthGate(auth: FakeAuthRepository())),
    );

    expect(find.text('RUNIO'), findsOneWidget);
    expect(find.text('Get started'), findsOneWidget);
  });

  testWidgets('welcome → dev quick sign-in routes through to home', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(auth: FakeAuthRepository(), devAccounts: devAccounts),
      ),
    );

    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();
    expect(find.text('Developer sign-in'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Runner A'));
    await tester.pumpAndSettle();

    // The fake flipped to signed-in and emitted; the real AuthGate swapped in
    // the shell — no re-wired preview page in between.
    expect(find.text('Record a run'), findsOneWidget);
  });

  /// Sign-in is a *state* of the signed-out flow rather than a pushed route, so
  /// there was nothing on the navigator for the system back gesture to pop and
  /// it fell through to the platform — quitting Runio from the second screen a
  /// new runner ever sees.
  testWidgets('system back on sign-in returns to the conversation, not out of '
      'the app', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          auth: FakeAuthRepository(),
          devAccounts: devAccounts,
          // There is no platform here to grant anything, and the intro now
          // waits on a real dialog before it will move on.
          requestPermission: (_) async => true,
        ),
      ),
    );

    // "Get started" now opens the coach's conversation, and the form is the
    // last step of it rather than the first thing after the welcome screen.
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sounds good'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Sam');
    await tester.tap(find.byTooltip('Continue'));
    await tester.pumpAndSettle();
    for (final permission in introPermissions) {
      await tester.tap(find.text(permission.cta));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Create my account'));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);

    // What the hardware back button / back gesture does.
    final popped = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(
      popped,
      isTrue,
      reason: 'the app must handle the pop rather than let it exit',
    );
    // Back into the conversation, with the answers still there — not past it.
    expect(find.text('Create your account'), findsNothing);
    expect(
      find.text('Sam'),
      findsOneWidget,
      reason: 'the name they gave is still in the transcript behind them',
    );
  });

  testWidgets(
    'and again from sign-in reached via "I already have an account"',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AuthGate(auth: FakeAuthRepository(), devAccounts: devAccounts),
        ),
      );

      await tester.tap(find.text('I already have an account'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);

      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();

      expect(find.text('Get started'), findsOneWidget);
    },
  );

  testWidgets('starts on home when already signed in', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AuthGate(
          auth: FakeAuthRepository(signedIn: true, email: 'dev@runio.app'),
        ),
      ),
    );
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
          auth: FakeAuthRepository(signedIn: true, email: 'dev@runio.app'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('dev@runio.app'), findsOneWidget);

    final signOutRow = find.widgetWithText(ListTile, 'Sign out');
    await tester.scrollUntilVisible(signOutRow, 200, scrollable: scrollable);
    await tester.tap(signOutRow);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(find.text('Get started'), findsOneWidget);
    expect(
      find.text('dev@runio.app'),
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
          home: AuthGate(auth: FakeAuthRepository(), devAccounts: devAccounts),
        ),
      );

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
