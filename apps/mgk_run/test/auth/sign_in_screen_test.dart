import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/core/config/app_config.dart';
import 'package:mgk_run/src/features/auth/presentation/sign_in_screen.dart';
import 'package:mgk_auth/mgk_auth.dart';

void main() {
  const devAccounts = <DevAccount>[
    DevAccount(
      label: 'Runner A',
      email: 'a@mgkfitness.mgkcodes.com',
      password: 'password',
    ),
    DevAccount(
      label: 'Runner B',
      email: 'b@mgkfitness.mgkcodes.com',
      password: 'secret6',
    ),
  ];

  testWidgets('shows developer quick sign-in buttons when accounts are given', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SignInScreen(
          auth: FakeAuthRepository(),
          devAccounts: devAccounts,
        ),
      ),
    );

    expect(find.text('Developer sign-in'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Runner A'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Runner B'), findsOneWidget);
  });

  testWidgets('hides developer quick sign-in when no accounts are given', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SignInScreen()));

    expect(find.text('Developer sign-in'), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets("tapping a dev button signs in with that account's credentials", (
    tester,
  ) async {
    final auth = FakeAuthRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: SignInScreen(auth: auth, devAccounts: devAccounts),
      ),
    );

    // Below Apple and Google now, so off the bottom of a test-sized screen.
    final runnerB = find.widgetWithText(OutlinedButton, 'Runner B');
    await tester.ensureVisible(runnerB);
    await tester.pumpAndSettle();
    await tester.tap(runnerB);
    await tester.pump();

    expect(auth.lastEmail, 'b@mgkfitness.mgkcodes.com');
    expect(auth.lastPassword, 'secret6');
  });

  group('Apple and Google', () {
    testWidgets('sit above the form, with the Hide My Email line', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: SignInScreen(auth: FakeAuthRepository())),
      );

      expect(find.text('Continue with Apple'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.textContaining('Hide My Email'), findsOneWidget);
      final apple = tester.getTopLeft(find.text('Continue with Apple')).dy;
      final email = tester.getTopLeft(find.text('Email')).dy;
      expect(apple, lessThan(email));
    });

    testWidgets('a pushed gate is told when Google signs in', (tester) async {
      final auth = FakeAuthRepository();
      var authenticated = 0;
      bool? intent;
      await tester.pumpWidget(
        MaterialApp(
          home: SignInScreen(
            auth: auth,
            initialSignUp: true,
            onAuthenticated: () => authenticated++,
            onSignUpIntent: (value) => intent = value,
          ),
        ),
      );

      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();

      expect(auth.lastProvider, 'google');
      expect(auth.isSignedIn, isTrue);
      expect(authenticated, 1);
      // Raised from the half of the screen the runner chose: the sign-up half
      // here, so the shell starts the coach's introduction.
      expect(intent, isTrue);
    });

    testWidgets("closing Apple's sheet takes the sign-up claim back", (
      tester,
    ) async {
      final auth = FakeAuthRepository()
        ..providerOutcome = ProviderOutcome.cancelled;
      bool? intent;
      await tester.pumpWidget(
        MaterialApp(
          home: SignInScreen(
            auth: auth,
            initialSignUp: true,
            onSignUpIntent: (value) => intent = value,
          ),
        ),
      );

      await tester.tap(find.text('Continue with Apple'));
      await tester.pumpAndSettle();

      expect(auth.isSignedIn, isFalse);
      expect(intent, isFalse);
    });

    testWidgets('a refused sign-in says so in words, not an exception', (
      tester,
    ) async {
      final auth = FakeAuthRepository()
        ..failure = const ProviderSignInException(ProviderFailure.refused);
      await tester.pumpWidget(MaterialApp(home: SignInScreen(auth: auth)));

      await tester.tap(find.text('Continue with Apple'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'That sign-in did not go through. Try again, or use your email.',
        ),
        findsOneWidget,
      );
    });
  });

  group('Forgot your password?', () {
    Future<void> tapForgot(WidgetTester tester) async {
      final forgot = find.text('Forgot your password?');
      await tester.ensureVisible(forgot);
      await tester.pumpAndSettle();
      await tester.tap(forgot);
      await tester.pumpAndSettle();
    }

    testWidgets('is offered when signing in, not when signing up', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(home: SignInScreen(auth: FakeAuthRepository())),
      );
      expect(find.text('Forgot your password?'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(
          home: SignInScreen(
            key: UniqueKey(),
            auth: FakeAuthRepository(),
            initialSignUp: true,
          ),
        ),
      );
      expect(find.text('Forgot your password?'), findsNothing);
    });

    testWidgets('asks for the email first', (tester) async {
      final auth = FakeAuthRepository();
      await tester.pumpWidget(MaterialApp(home: SignInScreen(auth: auth)));

      await tapForgot(tester);

      expect(find.text('Enter your email first.'), findsOneWidget);
      expect(auth.lastReset, isNull);
    });

    testWidgets('sends the reset and says the same thing for any address', (
      tester,
    ) async {
      final auth = FakeAuthRepository();
      await tester.pumpWidget(MaterialApp(home: SignInScreen(auth: auth)));

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        ' runner@example.com ',
      );
      await tapForgot(tester);

      expect(auth.lastReset, 'runner@example.com');
      final notice = tester.widget<Text>(
        find.text(
          'If that address has an account, a reset link is on its way.',
        ),
      );
      // A next step, not a failure, so not in the error colour.
      final error = Theme.of(
        tester.element(find.byType(SignInScreen)),
      ).colorScheme.error;
      expect(notice.style?.color, isNot(error));
    });
  });
}
