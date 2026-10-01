import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/core/config/app_config.dart';
import 'package:mgk_run/src/features/auth/presentation/sign_in_screen.dart';
import 'package:mgk_auth/mgk_auth.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../plates/plate.dart' show loadInter;

/// The email form is the second step: Apple, Google and email are offered
/// first, and the fields are behind "Continue with email".
Future<void> openEmail(WidgetTester tester) async {
  final Finder email = find.text('Continue with email');
  await tester.ensureVisible(email);
  await tester.pumpAndSettle();
  await tester.tap(email);
  await tester.pumpAndSettle();
}

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
    // One outlined button is the screen's own, "Continue with email".
    expect(find.widgetWithText(OutlinedButton, 'Runner A'), findsNothing);
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
    testWidgets('come first, with email as the third way in', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: SignInScreen(auth: FakeAuthRepository())),
      );

      expect(find.text('Continue with Apple'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Continue with email'), findsOneWidget);
      expect(find.textContaining('Hide My Email'), findsOneWidget);
      final apple = tester.getTopLeft(find.text('Continue with Apple')).dy;
      final email = tester.getTopLeft(find.text('Continue with email')).dy;
      expect(apple, lessThan(email));
      expect(
        find.byType(TextFormField),
        findsNothing,
        reason: 'the form is a step, not a second half of this one',
      );

      await openEmail(tester);
      expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Password'), findsOneWidget);
      expect(find.text('Continue with Apple'), findsNothing);

      await tester.tap(find.text('Other ways to sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Continue with Apple'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
    });

    testWidgets('and nothing an account needs is below a 393pt screen', (
      tester,
    ) async {
      // Board C14 and K2, 1 October 2026: with the choices and the form on one
      // screen, Password and Sign up were below the bottom of the phone. 818 is
      // the screen less the home indicator. Real Inter, because the test font
      // is wider and taller and would measure a layout no phone draws.
      await loadInter();
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(393, 852),
              padding: EdgeInsets.only(top: 59, bottom: 34),
            ),
            child: SignInScreen(
              auth: FakeAuthRepository(),
              initialSignUp: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.text('Have an account? Sign in')).bottom,
        lessThanOrEqualTo(818),
      );

      await tester.tap(find.text('Continue with email'));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(TextFormField, 'First name (optional)'),
        findsOneWidget,
        reason: 'the tallest form: no name from the intro',
      );
      expect(
        tester.getRect(find.widgetWithText(PrimaryButton, 'Sign up')).bottom,
        lessThanOrEqualTo(818),
      );
      expect(
        tester.getRect(find.text('Other ways to sign in')).bottom,
        lessThanOrEqualTo(818),
      );
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

    testWidgets('giving up on Apple and signing in by email is a sign-in', (
      tester,
    ) async {
      // Apple on Android carries on in the browser, so the sign-up claim is
      // left standing for the session to arrive under. Somebody who abandons
      // that and signs in with an email they already have must not then be
      // greeted as a new runner.
      final auth = FakeAuthRepository()
        ..providerOutcome = ProviderOutcome.continuing;
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
      expect(intent, isTrue);

      final toggle = find.text('Have an account? Sign in');
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await openEmail(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'sam@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'hunter2222',
      );
      final submit = find.widgetWithText(PrimaryButton, 'Sign in');
      await tester.ensureVisible(submit);
      await tester.pump();
      await tester.tap(submit);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(auth.isSignedIn, isTrue);
      expect(intent, isFalse);
    });
  });

  group('the password', () {
    Future<void> submit(
      WidgetTester tester, {
      required String password,
      required String label,
    }) async {
      await openEmail(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'sam@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        password,
      );
      final button = find.widgetWithText(PrimaryButton, label);
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('is eight characters for a new account, as in Lift', (
      tester,
    ) async {
      // One account across the suite, and the reset page already asks for
      // eight. Run asked for six until build 27.
      final auth = FakeAuthRepository();
      await tester.pumpWidget(
        MaterialApp(home: SignInScreen(auth: auth, initialSignUp: true)),
      );

      await submit(tester, password: 'seven77', label: 'Sign up');

      expect(find.text('Use at least 8 characters.'), findsOneWidget);
      expect(auth.lastEmail, isNull, reason: 'nothing was sent');
    });

    testWidgets('but a shorter one still signs in', (tester) async {
      // Somebody who made a six-character password while Run allowed it must
      // not be locked out by a rule that arrived afterwards.
      final auth = FakeAuthRepository();
      await tester.pumpWidget(MaterialApp(home: SignInScreen(auth: auth)));

      await submit(tester, password: 'six666', label: 'Sign in');

      expect(find.text('Use at least 8 characters.'), findsNothing);
      expect(auth.lastPassword, 'six666');
    });
  });

  testWidgets('signing in before confirming is the next step, not an error', (
    tester,
  ) async {
    // Confirmation is on since 30 September, so this is what a new runner
    // does first: signs up, then signs in without opening the email. The
    // server says "Email not confirmed", which in the error colour read as
    // the account not having been made. Lift's words, in the quiet colour.
    final auth = FakeAuthRepository()
      ..failure = const AuthException('Email not confirmed', statusCode: '400');
    await tester.pumpWidget(MaterialApp(home: SignInScreen(auth: auth)));
    await openEmail(tester);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'sam@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'hunter2222',
    );
    final submit = find.widgetWithText(PrimaryButton, 'Sign in');
    await tester.ensureVisible(submit);
    await tester.pump();
    await tester.tap(submit);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Email not confirmed'), findsNothing);
    final notice = tester.widget<Text>(
      find.text('Check your email and follow the link, then sign in.'),
    );
    final error = Theme.of(
      tester.element(find.byType(SignInScreen)),
    ).colorScheme.error;
    expect(notice.style?.color, isNot(error));
  });

  group('Forgot your password?', () {
    // On the email form, which is where a password is.
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
      expect(find.text('Forgot your password?'), findsNothing);
      await openEmail(tester);
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
      await openEmail(tester);
      expect(find.text('Forgot your password?'), findsNothing);
    });

    testWidgets('asks for the email first', (tester) async {
      final auth = FakeAuthRepository();
      await tester.pumpWidget(MaterialApp(home: SignInScreen(auth: auth)));
      await openEmail(tester);

      await tapForgot(tester);

      expect(find.text('Enter your email first.'), findsOneWidget);
      expect(auth.lastReset, isNull);
    });

    testWidgets('sends the reset and says the same thing for any address', (
      tester,
    ) async {
      final auth = FakeAuthRepository();
      await tester.pumpWidget(MaterialApp(home: SignInScreen(auth: auth)));
      await openEmail(tester);

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
