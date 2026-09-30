import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/auth/data/fake_auth.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_lift/src/features/auth/domain/account.dart';
import 'package:mgk_lift/src/features/auth/presentation/sign_in_screen.dart';

/// The screen, opened on the email form unless [emailFirst] is false: most of
/// these are about the form, which is one tap behind Apple and Google.
Future<void> pump(
  WidgetTester tester,
  AuthService auth, {
  int pending = 0,
  bool emailFirst = true,
}) async {
  tester.view.physicalSize = const Size(1080, 4200);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: SignInScreen(
        auth: auth,
        pendingWorkouts: pending,
        emailFirst: emailFirst,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The screen pushed over a page, so what it pops with can be read.
Future<List<bool?>> open(WidgetTester tester, AuthService auth) async {
  tester.view.physicalSize = const Size(1080, 4200);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  final popped = <bool?>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => popped.add(
              await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (_) => SignInScreen(auth: auth),
                ),
              ),
            ),
            child: const Text('under'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('under'));
  await tester.pumpAndSettle();
  return popped;
}

Future<void> fill(WidgetTester tester, String email, String password) async {
  await tester.enterText(find.byType(TextFormField).first, email);
  await tester.enterText(find.byType(TextFormField).last, password);
}

void main() {
  testWidgets('signing in is never presented as required', (
    WidgetTester tester,
  ) async {
    // The whole product decision. An app that demands an account before it
    // will let you write down a set is one people close.
    await pump(tester, FakeAuth());
    expect(
      find.textContaining('do not need an account to track'),
      findsOneWidget,
    );
  });

  testWidgets('says what is on one phone only, and nothing more', (
    WidgetTester tester,
  ) async {
    await pump(tester, FakeAuth(), pending: 9);
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();

    expect(find.text('9 sessions are on this phone only.'), findsOneWidget);

    // State, not an argument. The screen does not explain what an account is
    // or what signing in would get them; both are things people already know.
    for (final pitch in <String>['new phone', 'follows you', 'back up']) {
      expect(
        find.textContaining(pitch),
        findsNothing,
        reason: 'the sign-up screen is selling: "$pitch"',
      );
    }
  });

  testWidgets('and says nothing at all when there is nothing to say', (
    WidgetTester tester,
  ) async {
    // No pending sessions, so there is no state worth reporting. A paragraph
    // here to fill the space is how the screen started arguing in the first
    // place.
    await pump(tester, FakeAuth());
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();

    expect(find.textContaining('on this phone only'), findsNothing);
  });

  testWidgets('one screen toggles between signing in and signing up', (
    WidgetTester tester,
  ) async {
    await pump(tester, FakeAuth());
    expect(find.text('Welcome back'), findsOneWidget);

    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    // Two of them now: the headline and the toggle that got us here.
    expect(find.text('Create an account'), findsWidgets);
    expect(find.text('Welcome back'), findsNothing);

    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
  });

  group('validation', () {
    testWidgets('an empty form does not reach the server', (
      WidgetTester tester,
    ) async {
      final auth = FakeAuth(failWith: AuthFailure.unavailable);
      await pump(tester, auth);

      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('Enter your email.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
      // The failure the fake would have thrown never appears, because the
      // request was never made.
      expect(find.text(AuthFailure.unavailable.message), findsNothing);
    });

    testWidgets('a short password is only rejected when creating', (
      WidgetTester tester,
    ) async {
      // Enforcing it at sign-in would lock out anybody whose password predates
      // the rule. The auth fails so the screen stays put after the first
      // attempt - a successful sign-in pops it.
      await pump(tester, FakeAuth(failWith: AuthFailure.wrongCredentials));
      await fill(tester, 'a@b.com', 'short');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Use at least 8 characters.'), findsNothing);

      await tester.tap(find.text('Create an account'));
      await tester.pumpAndSettle();
      await fill(tester, 'a@b.com', 'short');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();
      expect(find.text('Use at least 8 characters.'), findsOneWidget);
    });
  });

  group('failures', () {
    testWidgets('wrong credentials do not say which half was wrong', (
      WidgetTester tester,
    ) async {
      // Distinguishing them tells anybody with an email address whether that
      // address has an account here.
      await pump(tester, FakeAuth(failWith: AuthFailure.wrongCredentials));
      await fill(tester, 'a@b.com', 'wrongpassword');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(
        find.text('That email and password do not match.'),
        findsOneWidget,
      );
    });

    testWidgets('needing confirmation reads as a next step, not an error', (
      WidgetTester tester,
    ) async {
      // The account was created. Colouring this red would read as "it was not".
      await pump(tester, FakeAuth(failWith: AuthFailure.needsConfirmation));
      await tester.tap(find.text('Create an account'));
      await tester.pumpAndSettle();
      await fill(tester, 'a@b.com', 'longenough1');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(
        find.text('Check your email and follow the link, then sign in.'),
      );
      expect(text.style?.color, isNot(const Color(0xFFDC2626)));
    });

    testWidgets('an unreachable server says the training is still safe', (
      WidgetTester tester,
    ) async {
      await pump(tester, FakeAuth(failWith: AuthFailure.unavailable));
      await fill(tester, 'a@b.com', 'longenough1');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.textContaining('safe on this device'), findsOneWidget);
    });
  });

  testWidgets('a password reset says the same thing either way', (
    WidgetTester tester,
  ) async {
    // Anything else is a way to find out who has an account here.
    await pump(tester, FakeAuth());
    await tester.enterText(find.byType(TextFormField).first, 'a@b.com');
    await tester.tap(find.text('Forgot your password?'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('If that address has an account'),
      findsOneWidget,
    );
  });

  testWidgets('signing in successfully closes the screen', (
    WidgetTester tester,
  ) async {
    final auth = FakeAuth();
    addTearDown(auth.dispose);
    await pump(tester, auth);
    await fill(tester, 'a@b.com', 'longenough1');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(auth.current?.email, 'a@b.com');
  });

  group('Apple and Google', () {
    testWidgets('come first, with email one tap behind them', (
      WidgetTester tester,
    ) async {
      await pump(tester, FakeAuth(), emailFirst: false);

      expect(find.byType(ProviderSignInButton), findsNWidgets(2));
      expect(find.text('Continue with email'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);

      await tester.tap(find.text('Continue with email'));
      await tester.pumpAndSettle();
      expect(find.byType(TextFormField), findsNWidgets(2));

      // And back, without losing the way to the other two.
      await tester.tap(find.text('Other ways to sign in'));
      await tester.pumpAndSettle();
      expect(find.byType(ProviderSignInButton), findsNWidgets(2));
    });

    testWidgets('say that they make an account too', (
      WidgetTester tester,
    ) async {
      // "Sign in" alone reads as a door for people who already have one.
      await pump(tester, FakeAuth(), emailFirst: false);
      expect(find.textContaining('make your account too'), findsOneWidget);
    });

    testWidgets('say that hiding the email is a separate account (O2)', (
      WidgetTester tester,
    ) async {
      await pump(tester, FakeAuth(), emailFirst: false);
      expect(find.textContaining('Hide My Email'), findsOneWidget);
    });

    testWidgets('Apple signs in and closes the screen', (
      WidgetTester tester,
    ) async {
      final auth = FakeAuth();
      addTearDown(auth.dispose);
      final popped = await open(tester, auth);

      await tester.tap(find.text('Continue with Apple'));
      await tester.pumpAndSettle();

      expect(auth.lastProvider, 'apple');
      expect(auth.current, isNotNull);
      // Once: the call and the stream both report the sign-in, and a second
      // pop would close the page under the screen.
      expect(popped, <bool?>[true]);
      expect(find.text('under'), findsOneWidget);
    });

    testWidgets('Google signs in and closes the screen', (
      WidgetTester tester,
    ) async {
      final auth = FakeAuth();
      addTearDown(auth.dispose);
      final popped = await open(tester, auth);

      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();

      expect(auth.lastProvider, 'google');
      expect(popped, <bool?>[true]);
    });

    testWidgets('closing the provider\'s sheet says nothing', (
      WidgetTester tester,
    ) async {
      // A choice, not a failure: a message would read as one.
      final auth = FakeAuth(providerOutcome: ProviderOutcome.cancelled);
      await pump(tester, auth, emailFirst: false);

      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();

      expect(auth.current, isNull);
      expect(find.text('Sign in'), findsOneWidget);
      for (final failure in AuthFailure.values) {
        expect(find.text(failure.message), findsNothing);
      }
      // And the buttons are usable again.
      final apple = tester.widget<ProviderSignInButton>(
        find.byType(ProviderSignInButton).first,
      );
      expect(apple.onPressed, isNotNull);
    });

    testWidgets('Apple in the browser says so, and closes when it lands', (
      WidgetTester tester,
    ) async {
      // Android: Apple's sign-in finishes in the browser and the account
      // arrives afterwards, through the link back into the app.
      final auth = FakeAuth(providerOutcome: ProviderOutcome.continuing);
      addTearDown(auth.dispose);
      final popped = await open(tester, auth);

      await tester.tap(find.text('Continue with Apple'));
      await tester.pumpAndSettle();
      expect(
        find.text('Finish signing in with Apple in your browser.'),
        findsOneWidget,
      );
      expect(popped, isEmpty);

      auth.arrive('you@privaterelay.appleid.com');
      await tester.pumpAndSettle();
      expect(popped, <bool?>[true]);
    });

    testWidgets('a refused sign-in says so, and points at email', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        FakeAuth(failWith: AuthFailure.providerRefused),
        emailFirst: false,
      );

      await tester.tap(find.text('Continue with Apple'));
      await tester.pumpAndSettle();

      expect(find.text(AuthFailure.providerRefused.message), findsOneWidget);
    });

    testWidgets('no signal says the training is still safe', (
      WidgetTester tester,
    ) async {
      await pump(
        tester,
        FakeAuth(failWith: AuthFailure.unavailable),
        emailFirst: false,
      );

      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();

      expect(find.textContaining('safe on this device'), findsOneWidget);
    });
  });
}
