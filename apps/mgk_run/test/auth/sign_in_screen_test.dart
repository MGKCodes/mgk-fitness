import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/core/config/app_config.dart';
import 'package:mgk_run/src/features/auth/data/auth_repository.dart';
import 'package:mgk_run/src/features/auth/presentation/sign_in_screen.dart';
import 'package:mgk_auth/mgk_auth.dart';
import 'package:mgk_ui/mgk_ui.dart';

import '../plates/plate.dart' show loadInter;
import 'email_path.dart';

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

  /// The screen as a pushed gate raises it, counting the times it is told
  /// there is a session.
  Future<int Function()> pumpScreen(
    WidgetTester tester,
    AuthRepository auth, {
    DateTime Function()? clock,
  }) async {
    var authenticated = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: SignInScreen(
          auth: auth,
          clock: clock,
          onAuthenticated: () => authenticated++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return () => authenticated;
  }

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

  testWidgets('says which app this is, and whose account', (tester) async {
    // Run's icon and name first, so nobody wonders where they are signing in;
    // then the account, which is the suite's, in the head Lift's sign-in draws
    // too, so the two cannot drift.
    await tester.pumpWidget(
      MaterialApp(home: SignInScreen(auth: FakeAuthRepository())),
    );
    await tester.pumpAndSettle();

    expect(
      find.image(const AssetImage('assets/images/brand/app_icon.png')),
      findsOneWidget,
    );
    expect(find.text('Run'), findsOneWidget);
    expect(find.text('MGKFitness Account'), findsOneWidget);
    expect(find.textContaining('One account for every'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Run')).dy,
      lessThan(tester.getTopLeft(find.text('MGKFitness Account')).dy),
    );
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
        find.byType(TextField),
        findsNothing,
        reason: 'the email path is a step, not a second half of this one',
      );

      await openEmail(tester);
      // The address, alone: no password until the address says there is one.
      expect(find.byKey(EmailSignInSteps.emailFieldKey), findsOneWidget);
      expect(find.byKey(EmailSignInSteps.passwordFieldKey), findsNothing);
      expect(find.text('Continue with Apple'), findsNothing);

      await tapVisible(tester, find.text('Other ways to sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Continue with Apple'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a pushed gate is told when Google signs in', (tester) async {
      final auth = FakeAuthRepository();
      final authenticated = await pumpScreen(tester, auth);

      await tapVisible(tester, find.text('Continue with Google'));
      await tester.pumpAndSettle();

      expect(auth.lastProvider, 'google');
      expect(auth.isSignedIn, isTrue);
      expect(authenticated(), 1);
    });

    testWidgets("closing Apple's sheet is not a failure", (tester) async {
      final auth = FakeAuthRepository()
        ..providerOutcome = ProviderOutcome.cancelled;
      final authenticated = await pumpScreen(tester, auth);

      await tester.tap(find.text('Continue with Apple'));
      await tester.pumpAndSettle();

      expect(auth.isSignedIn, isFalse);
      expect(authenticated(), 0);
      expect(find.textContaining('did not go through'), findsNothing);
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

    testWidgets("Apple's browser on Android finishes the sign-in later", (
      tester,
    ) async {
      final auth = FakeAuthRepository()
        ..providerOutcome = ProviderOutcome.continuing;
      final authenticated = await pumpScreen(tester, auth);

      await tester.tap(find.text('Continue with Apple'));
      await tester.pumpAndSettle();
      expect(
        find.text('Finish signing in with Apple in your browser.'),
        findsOneWidget,
      );
      expect(authenticated(), 0);

      // The session arrives on the auth stream once the browser hands back.
      auth.emit(AuthChange.signedIn);
      await tester.pumpAndSettle();
      expect(authenticated(), 1);
    });
  });

  group('the email path', () {
    testWidgets('each answer the lookup gives leads to its own step', (
      tester,
    ) async {
      final auth = FakeAuthRepository();
      await pumpScreen(tester, auth);
      await openEmail(tester);
      expect(find.text('Sign in or create your account'), findsOneWidget);

      // A password: Welcome back.
      await submitAddress(tester, FakeAuthRepository.passwordAddress);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(find.byKey(EmailSignInSteps.passwordFieldKey), findsOneWidget);
      expect(find.widgetWithText(PrimaryButton, 'Sign in'), findsOneWidget);
      expect(find.text('Forgot your password?'), findsOneWidget);
      // The address stays, with Change, on every later step.
      expect(find.text(FakeAuthRepository.passwordAddress), findsOneWidget);

      // Apple and Google: that provider, and a way to set a password instead.
      for (final (address, provider) in <(String, String)>[
        (FakeAuthRepository.appleAddress, 'Apple'),
        (FakeAuthRepository.googleAddress, 'Google'),
      ]) {
        await tapVisible(tester, find.text('Change'));
        await submitAddress(tester, address);
        expect(find.text('Welcome back'), findsOneWidget);
        expect(
          find.text('This address signs in with $provider.'),
          findsOneWidget,
        );
        expect(find.text('Continue with $provider'), findsOneWidget);
        expect(find.text('Set a password instead'), findsOneWidget);
        expect(find.byKey(EmailSignInSteps.passwordFieldKey), findsNothing);
      }

      // New, and unconfirmed, which reads exactly the same.
      for (final address in <String>[
        newAddress,
        FakeAuthRepository.unconfirmedAddress,
      ]) {
        await tapVisible(tester, find.text('Change'));
        await submitAddress(tester, address);
        expect(find.text('Create your account'), findsOneWidget);
        expect(find.text('Choose a password'), findsOneWidget);
        expect(
          find.widgetWithText(PrimaryButton, 'Create account'),
          findsOneWidget,
        );
        expect(find.text('Forgot your password?'), findsNothing);
      }
      expect(auth.lookups, 5);
    });

    testWidgets('Change goes back to the address, still typed', (tester) async {
      await pumpScreen(tester, FakeAuthRepository());
      await openEmail(tester);
      await submitAddress(tester, FakeAuthRepository.passwordAddress);

      await tapVisible(tester, find.text('Change'));

      final field = tester.widget<TextField>(
        find.byKey(EmailSignInSteps.emailFieldKey),
      );
      expect(field.controller?.text, FakeAuthRepository.passwordAddress);
      expect(find.byKey(EmailSignInSteps.passwordFieldKey), findsNothing);
    });

    testWidgets('a likely typo is offered a fix, and only offered', (
      tester,
    ) async {
      final auth = FakeAuthRepository();
      await pumpScreen(tester, auth);
      await openEmail(tester);

      await tester.enterText(
        find.byKey(EmailSignInSteps.emailFieldKey),
        'sam@gmial.com',
      );
      await tester.pump();
      expect(find.text('Did you mean sam@gmail.com?'), findsOneWidget);
      expect(auth.lookups, 0, reason: 'nothing is sent while typing');

      await tapVisible(tester, find.text('Did you mean sam@gmail.com?'));
      final field = tester.widget<TextField>(
        find.byKey(EmailSignInSteps.emailFieldKey),
      );
      expect(field.controller?.text, 'sam@gmail.com');
      expect(find.textContaining('Did you mean'), findsNothing);
    });

    testWidgets('something that is not an address is not looked up', (
      tester,
    ) async {
      final auth = FakeAuthRepository();
      await pumpScreen(tester, auth);
      await openEmail(tester);

      await submitAddress(tester, 'sam at example');

      expect(
        find.text('That does not look like an email address.'),
        findsOneWidget,
      );
      expect(auth.lookups, 0);
    });

    testWidgets('no connection at the lookup keeps what was typed', (
      tester,
    ) async {
      // Never a guess at new or returning (the ADR's edge cases): the step
      // after the address is only ever the one the server named.
      final auth = FakeAuthRepository()
        ..emailFailure = EmailFailure.unavailable;
      await pumpScreen(tester, auth);
      await openEmail(tester);

      await submitAddress(tester, FakeAuthRepository.passwordAddress);

      expect(
        find.text('No connection. Try again when you have a signal.'),
        findsOneWidget,
      );
      final field = tester.widget<TextField>(
        find.byKey(EmailSignInSteps.emailFieldKey),
      );
      expect(field.controller?.text, FakeAuthRepository.passwordAddress);
      expect(find.byKey(EmailSignInSteps.passwordFieldKey), findsNothing);
      expect(find.text('Create your account'), findsNothing);
      expect(
        tester.widget<PrimaryButton>(find.byType(PrimaryButton)).busy,
        isFalse,
        reason: 'ready to try again the moment the signal is back',
      );

      // The signal comes back, and the same Continue goes through.
      auth.emailFailure = null;
      await tapVisible(tester, find.widgetWithText(PrimaryButton, 'Continue'));
      expect(find.text('Welcome back'), findsOneWidget);
    });

    group('welcome back', () {
      testWidgets('the right password signs in, once', (tester) async {
        final auth = FakeAuthRepository();
        final authenticated = await pumpScreen(tester, auth);

        await signInByEmail(tester);

        expect(auth.isSignedIn, isTrue);
        expect(auth.accountIsNew, isFalse);
        expect(authenticated(), 1);
        expect(auth.profileWrites, 1, reason: 'the profile row, as ever');
      });

      testWidgets('a wrong password says so and keeps the address', (
        tester,
      ) async {
        final auth = FakeAuthRepository();
        final authenticated = await pumpScreen(tester, auth);
        await openEmail(tester);
        await submitAddress(tester, FakeAuthRepository.passwordAddress);

        await submitPassword(tester, 'not-it-1');

        final error = tester.widget<Text>(
          find.text('Wrong password. Try again, or set a new one.'),
        );
        expect(error.style?.color, AppColors.danger);
        expect(find.text('Welcome back'), findsOneWidget);
        expect(find.text(FakeAuthRepository.passwordAddress), findsOneWidget);
        expect(auth.isSignedIn, isFalse);
        expect(authenticated(), 0);

        // And the right one still goes through from where they are.
        await submitPassword(tester, FakeAuthRepository.rightPassword);
        expect(auth.isSignedIn, isTrue);
      });

      testWidgets('signing in never checks the rule for a new password', (
        tester,
      ) async {
        // An account keeps whatever password it was made with. Somebody who
        // chose six characters while Run allowed it must not be locked out.
        final auth = FakeAuthRepository();
        await pumpScreen(tester, auth);
        await openEmail(tester);
        await submitAddress(tester, FakeAuthRepository.passwordAddress);

        await submitPassword(tester, 'six666');

        expect(auth.lastPassword, 'six666', reason: 'it was sent');
        expect(find.textContaining('at least 8'), findsNothing);
        expect(find.text('8 characters'), findsNothing);
      });

      testWidgets('Forgot your password? sends to the address and says where', (
        tester,
      ) async {
        final auth = FakeAuthRepository();
        await pumpScreen(tester, auth);
        await openEmail(tester);
        await submitAddress(tester, ' ${FakeAuthRepository.passwordAddress} ');

        await tapVisible(tester, find.text('Forgot your password?'));

        expect(auth.passwordEmails, <String>[
          FakeAuthRepository.passwordAddress,
        ]);
        // The lookup has already said the address has an account, so there
        // is nothing left to hide, and "if that address has an account" would
        // only add doubt.
        final notice = tester.widget<Text>(
          find.text(
            'A link to set a new password is on its way to '
            '${FakeAuthRepository.passwordAddress}.',
          ),
        );
        expect(notice.style?.color, isNot(AppColors.danger));
        expect(find.textContaining('If that address'), findsNothing);
      });
    });

    group('an address that signs in with Apple or Google', () {
      testWidgets('is offered Apple, and Apple signs it in', (tester) async {
        final auth = FakeAuthRepository();
        final authenticated = await pumpScreen(tester, auth);
        await openEmail(tester);
        await submitAddress(tester, FakeAuthRepository.appleAddress);

        await tapVisible(tester, find.text('Continue with Apple'));
        await tester.pumpAndSettle();

        expect(auth.lastProvider, 'apple');
        expect(auth.isSignedIn, isTrue);
        expect(authenticated(), 1);
      });

      testWidgets('or Google, for one made with Google', (tester) async {
        final auth = FakeAuthRepository();
        await pumpScreen(tester, auth);
        await openEmail(tester);
        await submitAddress(tester, FakeAuthRepository.googleAddress);

        await tapVisible(tester, find.text('Continue with Google'));
        await tester.pumpAndSettle();

        expect(auth.lastProvider, 'google');
      });

      testWidgets('and can set a password instead', (tester) async {
        final auth = FakeAuthRepository();
        await pumpScreen(tester, auth);
        await openEmail(tester);
        await submitAddress(tester, FakeAuthRepository.appleAddress);

        await tapVisible(tester, find.text('Set a password instead'));

        expect(auth.passwordEmails, <String>[FakeAuthRepository.appleAddress]);
        expect(find.textContaining('A link to set a password'), findsOneWidget);
        expect(auth.lastProvider, isNull, reason: 'Apple was not asked');
      });
    });

    group('a new address', () {
      testWidgets('shows the rule as it is typed, part by part', (
        tester,
      ) async {
        await pumpScreen(tester, FakeAuthRepository());
        await openEmail(tester);
        await submitAddress(tester, newAddress);

        for (final label in <String>['8 characters', 'a number', 'a symbol']) {
          expect(find.text(label), findsOneWidget);
        }
        bool met(String label) =>
            tester.widget<Text>(find.text(label)).style?.color ==
            AppColors.textPrimary;

        await tester.enterText(
          find.byKey(EmailSignInSteps.passwordFieldKey),
          'hunter22',
        );
        await tester.pump();
        expect(met('8 characters'), isTrue);
        expect(met('a number'), isTrue);
        expect(met('a symbol'), isFalse);
      });

      testWidgets('is refused a password that misses the rule, before '
          'anything is sent', (tester) async {
        final auth = FakeAuthRepository();
        await pumpScreen(tester, auth);
        await openEmail(tester);
        await submitAddress(tester, newAddress);

        await submitPassword(tester, 'hunter22', label: 'Create account');

        expect(
          find.text('Use at least 8 characters, with a number and a symbol.'),
          findsOneWidget,
        );
        expect(auth.codesSent, isEmpty);
        expect(find.byKey(EmailSignInSteps.codeFieldKey), findsNothing);
      });

      testWidgets('is made, sent a code, and signed in by the code', (
        tester,
      ) async {
        final auth = FakeAuthRepository();
        final authenticated = await pumpScreen(tester, auth);
        await openEmail(tester);
        await submitAddress(tester, newAddress);
        await submitPassword(tester, goodNewPassword, label: 'Create account');

        expect(auth.codesSent, <String>[newAddress]);
        expect(find.text('Enter the 6-digit code we sent to'), findsOneWidget);
        expect(find.text(newAddress), findsOneWidget);
        expect(find.text('Create your account'), findsOneWidget);
        expect(auth.isSignedIn, isFalse, reason: 'not until the code');
        expect(authenticated(), 0);

        await enterCode(tester, FakeAuthRepository.rightCode);

        expect(auth.isSignedIn, isTrue);
        expect(auth.accountIsNew, isTrue);
        expect(authenticated(), 1);
        expect(auth.profileWrites, 1);
        expect(
          auth.lastReplacement,
          isNull,
          reason: 'a new address has only the one password',
        );
      });

      testWidgets('signs straight in where the project confirms nothing', (
        tester,
      ) async {
        final auth = FakeAuthRepository()..confirmationOff = true;
        final authenticated = await pumpScreen(tester, auth);
        await openEmail(tester);
        await submitAddress(tester, newAddress);

        await submitPassword(tester, goodNewPassword, label: 'Create account');

        expect(auth.isSignedIn, isTrue);
        expect(authenticated(), 1);
        expect(auth.codesSent, isEmpty);
      });

      testWidgets('an unconfirmed one replaces its first password with this '
          'one, once the code proves the inbox', (tester) async {
        final auth = FakeAuthRepository();
        await pumpScreen(tester, auth);

        await createAccountByEmail(
          tester,
          address: FakeAuthRepository.unconfirmedAddress,
        );

        expect(auth.isSignedIn, isTrue);
        expect(auth.lastReplacement, goodNewPassword);
      });

      testWidgets('and is signed in by the code even when that password '
          'cannot be written', (tester) async {
        // The code proved the inbox and the session is there, so it is a
        // sign-in: only the first password still works, and Forgot your
        // password? is the way to a new one.
        final auth = FakeAuthRepository()..replacementFails = true;
        final authenticated = await pumpScreen(tester, auth);

        await createAccountByEmail(
          tester,
          address: FakeAuthRepository.unconfirmedAddress,
        );

        expect(auth.isSignedIn, isTrue);
        expect(authenticated(), 1);
        expect(find.textContaining('did not go through'), findsNothing);
      });

      testWidgets('a wrong code says so, and the code can be typed again', (
        tester,
      ) async {
        final auth = FakeAuthRepository();
        final authenticated = await pumpScreen(tester, auth);
        await openEmail(tester);
        await submitAddress(tester, newAddress);
        await submitPassword(tester, goodNewPassword, label: 'Create account');

        await enterCode(tester, '000000');

        expect(
          find.text(
            'That code is wrong or has expired. Check it, or send a new one.',
          ),
          findsOneWidget,
        );
        expect(auth.isSignedIn, isFalse);
        expect(authenticated(), 0);
        expect(find.byKey(EmailSignInSteps.codeFieldKey), findsOneWidget);

        await enterCode(tester, FakeAuthRepository.rightCode);
        expect(auth.isSignedIn, isTrue);
      });

      testWidgets('another code waits out its minute, then goes', (
        tester,
      ) async {
        var now = DateTime(2026, 10, 20, 9);
        final auth = FakeAuthRepository();
        await pumpScreen(tester, auth, clock: () => now);
        await openEmail(tester);
        await submitAddress(tester, newAddress);
        await submitPassword(tester, goodNewPassword, label: 'Create account');

        expect(find.text('Send a new code in 1:00'), findsOneWidget);
        await tester.tap(find.text('Send a new code in 1:00'));
        await tester.pump();
        expect(auth.codesSent, hasLength(1), reason: 'not yet');

        now = now.add(const Duration(seconds: 42));
        await tester.pump(const Duration(seconds: 1));
        expect(find.text('Send a new code in 0:18'), findsOneWidget);

        now = now.add(const Duration(seconds: 18));
        await tester.pump(const Duration(seconds: 1));
        await tapVisible(tester, find.text('Send a new code'));

        expect(auth.codesSent, <String>[newAddress, newAddress]);
        expect(
          find.text('A new code is on its way to $newAddress.'),
          findsOneWidget,
        );
        expect(find.text('Send a new code in 1:00'), findsOneWidget);
      });
    });

    testWidgets('and nothing a step needs is below a 393pt screen', (
      tester,
    ) async {
      // Board C14 and K2, 1 October 2026: with the choices and the form on one
      // screen, Password and Sign up were below the bottom of the phone. 818 is
      // the screen less the home indicator. Real Inter, because the test font
      // is wider and taller and would measure a layout no phone draws. The
      // tallest steps are making an account, with its checklist and its note
      // about the code, and the code itself.
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
            child: SignInScreen(auth: FakeAuthRepository()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      double bottomOf(Finder f) => tester.getRect(f).bottom;
      expect(
        bottomOf(find.textContaining('By continuing you agree')),
        lessThanOrEqualTo(818),
      );

      await tester.tap(find.text('Continue with email'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(EmailSignInSteps.emailFieldKey),
        newAddress,
      );
      await tester.tap(find.widgetWithText(PrimaryButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(find.text('a symbol'), findsOneWidget);
      expect(
        bottomOf(find.widgetWithText(PrimaryButton, 'Create account')),
        lessThanOrEqualTo(818),
      );
      expect(
        bottomOf(find.textContaining('By continuing you agree')),
        lessThanOrEqualTo(818),
      );

      await tester.enterText(
        find.byKey(EmailSignInSteps.passwordFieldKey),
        goodNewPassword,
      );
      await tester.tap(find.widgetWithText(PrimaryButton, 'Create account'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        bottomOf(find.textContaining('Send a new code')),
        lessThanOrEqualTo(818),
      );
      expect(
        bottomOf(find.textContaining('By continuing you agree')),
        lessThanOrEqualTo(818),
      );
    });
  });
}
