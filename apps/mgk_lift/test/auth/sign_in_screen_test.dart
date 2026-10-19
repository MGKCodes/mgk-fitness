import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_auth/mgk_auth.dart' show EmailFailure;
import 'package:mgk_lift/src/features/auth/data/fake_auth.dart';
import 'package:mgk_lift/src/features/auth/domain/account.dart';
import 'package:mgk_lift/src/features/auth/presentation/sign_in_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// A phone tall enough for the whole screen, so nothing a test taps is off
/// the bottom.
void tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4200);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
}

/// The screen on its own, opened on the address unless [emailFirst] is false.
Future<void> pump(
  WidgetTester tester,
  AuthService auth, {
  int pending = 0,
  bool emailFirst = true,
  DateTime Function()? clock,
}) async {
  tall(tester);
  await tester.pumpWidget(
    MaterialApp(
      home: SignInScreen(
        auth: auth,
        pendingWorkouts: pending,
        emailFirst: emailFirst,
        clock: clock ?? DateTime.now,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The screen pushed over a page, so what it pops with can be read.
Future<List<bool?>> open(
  WidgetTester tester,
  AuthService auth, {
  bool emailFirst = false,
}) async {
  tall(tester);
  final popped = <bool?>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async => popped.add(
              await Navigator.of(context).push<bool>(
                MaterialPageRoute<bool>(
                  builder: (_) =>
                      SignInScreen(auth: auth, emailFirst: emailFirst),
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

Future<void> address(WidgetTester tester, String email) async {
  await tester.enterText(find.byKey(EmailSignInSteps.emailFieldKey), email);
  await tester.tap(find.text('Continue'));
  await tester.pumpAndSettle();
}

Future<void> password(
  WidgetTester tester,
  String password,
  String button,
) async {
  await tester.enterText(
    find.byKey(EmailSignInSteps.passwordFieldKey),
    password,
  );
  await tester.tap(find.widgetWithText(FilledButton, button));
  await tester.pumpAndSettle();
}

/// The sixth digit is the press, as it is when Mail fills the code in.
Future<void> code(WidgetTester tester, String code) async {
  await tester.enterText(find.byKey(EmailSignInSteps.codeFieldKey), code);
  await tester.pumpAndSettle();
}

/// From the address to the name step, for an address with no account.
Future<void> makeAnAccount(WidgetTester tester) async {
  await address(tester, 'sam@example.com');
  await password(tester, 'lifting-1', 'Create account');
  await code(tester, FakeAuth.code);
}

void main() {
  testWidgets('is left in one tap, and does not argue with being opened', (
    WidgetTester tester,
  ) async {
    // Opened on purpose, to back up or to subscribe, so it does not end on a
    // line saying the account is not needed: on a screen somebody just asked
    // for, that read as a contradiction. What keeps it out of the way of the
    // free half is that leaving costs one tap and loses nothing.
    final auth = FakeAuth();
    addTearDown(auth.dispose);
    final popped = await open(tester, auth);
    expect(find.textContaining('do not need an account'), findsNothing);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(popped, <bool?>[null]);
    expect(find.text('under'), findsOneWidget);
  });

  testWidgets('says what is on one phone only, and nothing more', (
    WidgetTester tester,
  ) async {
    await pump(tester, FakeAuth(), pending: 9);

    expect(find.text('9 sessions are on this phone only.'), findsOneWidget);

    // State, not an argument. The screen does not explain what an account is
    // or what signing in would get them; both are things people already know.
    for (final pitch in <String>['new phone', 'follows you', 'back up']) {
      expect(
        find.textContaining(pitch),
        findsNothing,
        reason: 'the sign-in screen is selling: "$pitch"',
      );
    }

    // Somebody with an account knows what it does.
    await address(tester, FakeAuth.returningAddress);
    expect(find.textContaining('on this phone only'), findsNothing);
  });

  testWidgets('and says nothing at all when there is nothing to say', (
    WidgetTester tester,
  ) async {
    // No pending sessions, so there is no state worth reporting. A paragraph
    // here to fill the space is how the screen started arguing in the first
    // place.
    await pump(tester, FakeAuth());
    await address(tester, 'sam@example.com');

    expect(find.textContaining('on this phone only'), findsNothing);
  });

  testWidgets('says which app this is, and whose account', (
    WidgetTester tester,
  ) async {
    // Lift's icon and name first, so nobody wonders where they are signing
    // in; then the account, which is the suite's and not Lift's own, in the
    // head Run's sign-in draws, so the two cannot drift.
    for (final emailFirst in <bool>[false, true]) {
      // A fresh screen for each, or the second would keep the first's state.
      await tester.pumpWidget(const SizedBox());
      await pump(tester, FakeAuth(), emailFirst: emailFirst);
      expect(find.byType(ProfileHeader), findsOneWidget);
      expect(
        find.image(const AssetImage('assets/images/brand/app_icon.png')),
        findsOneWidget,
      );
      expect(find.text('Lift'), findsOneWidget);
      expect(find.text('MGKFitness Account'), findsOneWidget);
      expect(find.textContaining('One account for every'), findsOneWidget);
      expect(find.textContaining('works in Run'), findsOneWidget);
      // The app comes before the account.
      expect(
        tester.getTopLeft(find.text('Lift')).dy,
        lessThan(tester.getTopLeft(find.text('MGKFitness Account')).dy),
      );
    }
  });

  group('the address first (ADR-0047)', () {
    testWidgets('is asked for alone, under a line that says both', (
      WidgetTester tester,
    ) async {
      await pump(tester, FakeAuth());

      expect(find.byKey(EmailSignInSteps.emailFieldKey), findsOneWidget);
      expect(find.byKey(EmailSignInSteps.passwordFieldKey), findsNothing);
      expect(find.text('Sign in or create your account'), findsOneWidget);
      // The two-mode form and its switch are gone.
      expect(find.textContaining('New here?'), findsNothing);
      expect(find.textContaining('Have an account?'), findsNothing);
    });

    for (final (typed, line, what) in <(String, String, String)>[
      ('sam@example.com', 'Create your account', 'Create account'),
      (FakeAuth.unconfirmedAddress, 'Create your account', 'Create account'),
      (FakeAuth.returningAddress, 'Welcome back', 'Sign in'),
      (FakeAuth.appleAddress, 'Welcome back', 'Continue with Apple'),
      (FakeAuth.googleAddress, 'Welcome back', 'Continue with Google'),
    ]) {
      testWidgets('$typed leads to "$what"', (WidgetTester tester) async {
        await pump(tester, FakeAuth());
        await address(tester, typed);

        expect(find.text(line), findsOneWidget);
        expect(find.text(what), findsOneWidget);
        // The address stays on the step it led to, with Change.
        expect(find.text(typed), findsOneWidget);
        expect(find.text('Change'), findsOneWidget);
      });
    }

    testWidgets('an unconfirmed address reads exactly as a new one', (
      WidgetTester tester,
    ) async {
      // The difference is kept only for what happens once the code checks
      // out, never shown.
      Future<List<String>> words(String typed) async {
        // A fresh screen each time, not the last one's state.
        await tester.pumpWidget(const SizedBox());
        await pump(tester, FakeAuth());
        await address(tester, typed);
        return tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data ?? '')
            .where((t) => t != typed)
            .toList();
      }

      expect(
        await words(FakeAuth.unconfirmedAddress),
        await words('sam@example.com'),
      );
    });

    testWidgets('a likely typo is offered, and taken only on a tap', (
      WidgetTester tester,
    ) async {
      await pump(tester, FakeAuth());
      await tester.enterText(
        find.byKey(EmailSignInSteps.emailFieldKey),
        'sam@gmial.com',
      );
      await tester.pump();

      expect(find.text('Did you mean sam@gmail.com?'), findsOneWidget);
      await tester.tap(find.text('Did you mean sam@gmail.com?'));
      await tester.pump();
      expect(find.text('sam@gmail.com'), findsOneWidget);
    });

    testWidgets('something that is not an address never reaches the lookup', (
      WidgetTester tester,
    ) async {
      final auth = FakeAuth(emailFailure: EmailFailure.unavailable);
      await pump(tester, auth);
      await address(tester, 'sam');

      expect(
        find.text('That does not look like an email address.'),
        findsOneWidget,
      );
      // The failure the fake would have thrown never appears, because the
      // lookup was never asked.
      expect(find.textContaining('No connection'), findsNothing);
    });

    testWidgets('no connection keeps what was typed, and guesses nothing', (
      WidgetTester tester,
    ) async {
      final auth = FakeAuth(emailFailure: EmailFailure.unavailable);
      await pump(tester, auth);
      await address(tester, FakeAuth.returningAddress);

      expect(
        find.text('No connection. Try again when you have a signal.'),
        findsOneWidget,
      );
      // Still the address, with what was typed in it: not a password, and not
      // a new account.
      final field = tester.widget<TextField>(
        find.byKey(EmailSignInSteps.emailFieldKey),
      );
      expect(field.controller?.text, FakeAuth.returningAddress);
      expect(find.byKey(EmailSignInSteps.passwordFieldKey), findsNothing);

      // And the same press works once there is a signal.
      auth.emailFailure = null;
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome back'), findsOneWidget);
    });

    testWidgets('Change goes back to the address, filled in', (
      WidgetTester tester,
    ) async {
      await pump(tester, FakeAuth());
      await address(tester, FakeAuth.returningAddress);
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.byKey(EmailSignInSteps.emailFieldKey),
      );
      expect(field.controller?.text, FakeAuth.returningAddress);
      expect(find.text('Sign in or create your account'), findsOneWidget);
    });

    testWidgets('Other ways to sign in goes back to Apple and Google', (
      WidgetTester tester,
    ) async {
      await pump(tester, FakeAuth());
      await tester.tap(find.text('Other ways to sign in'));
      await tester.pumpAndSettle();
      expect(find.byType(ProviderSignInButton), findsNWidgets(2));
    });
  });

  group('Welcome back', () {
    testWidgets('a wrong password is called one, and keeps the address', (
      WidgetTester tester,
    ) async {
      // The lookup has already said the address has an account, so hiding
      // which half was wrong would hide nothing.
      final auth = FakeAuth();
      addTearDown(auth.dispose);
      await pump(tester, auth);
      await address(tester, FakeAuth.returningAddress);
      await password(tester, 'lift-2025', 'Sign in');

      expect(
        find.text('Wrong password. Try again, or set a new one.'),
        findsOneWidget,
      );
      expect(find.text(FakeAuth.returningAddress), findsOneWidget);
      expect(find.text('Welcome back'), findsOneWidget);
      expect(auth.current, isNull);
    });

    testWidgets('a returning account closes the screen, and is not asked '
        'its name', (WidgetTester tester) async {
      final auth = FakeAuth();
      addTearDown(auth.dispose);
      final popped = await open(tester, auth, emailFirst: true);
      await address(tester, FakeAuth.returningAddress);
      await password(tester, FakeAuth.password, 'Sign in');

      // Once: the call and the stream both report the sign-in.
      expect(popped, <bool?>[true]);
      expect(find.byType(AccountNameStep), findsNothing);
      expect(auth.namesWritten, isEmpty);
      expect(auth.current?.email, FakeAuth.returningAddress);
    });

    testWidgets('Forgot your password? sends to the address typed, and says '
        'so in full', (WidgetTester tester) async {
      final auth = FakeAuth();
      await pump(tester, auth);
      await address(tester, FakeAuth.returningAddress);
      await tester.tap(find.text('Forgot your password?'));
      await tester.pumpAndSettle();

      expect(auth.emailCalls, <String>['password email']);
      expect(
        find.text(
          'A link to set a new password is on its way to '
          '${FakeAuth.returningAddress}.',
        ),
        findsOneWidget,
      );
      // The old hedge is gone with the rule it served.
      expect(
        find.textContaining('If that address has an account'),
        findsNothing,
      );
    });
  });

  group('an address made with Apple or Google', () {
    testWidgets("offers that provider's button, through the provider path", (
      WidgetTester tester,
    ) async {
      final auth = FakeAuth();
      addTearDown(auth.dispose);
      final popped = await open(tester, auth, emailFirst: true);
      await address(tester, FakeAuth.googleAddress);

      expect(find.text('This address signs in with Google.'), findsOneWidget);
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();

      expect(auth.lastProvider, 'google');
      expect(popped, <bool?>[true]);
    });

    testWidgets('Set a password instead sends the email', (
      WidgetTester tester,
    ) async {
      final auth = FakeAuth();
      await pump(tester, auth);
      await address(tester, FakeAuth.appleAddress);
      expect(find.text('This address signs in with Apple.'), findsOneWidget);

      await tester.tap(find.text('Set a password instead'));
      await tester.pumpAndSettle();
      expect(auth.emailCalls, <String>['password email']);
      expect(find.textContaining('A link to set a password'), findsOneWidget);
    });
  });

  group('a new address', () {
    testWidgets('shows the password rule, part by part', (
      WidgetTester tester,
    ) async {
      await pump(tester, FakeAuth());
      await address(tester, 'sam@example.com');
      await tester.enterText(
        find.byKey(EmailSignInSteps.passwordFieldKey),
        'lifting1',
      );
      await tester.pump();

      for (final part in <String>['8 characters', 'a number', 'a symbol']) {
        expect(find.text(part), findsOneWidget);
      }
      Icon tick(String part) => tester.widget<Icon>(
        find.descendant(
          of: find.ancestor(of: find.text(part), matching: find.byType(Row)),
          matching: find.byType(Icon),
        ),
      );
      expect(tick('8 characters').icon, Icons.check_circle);
      expect(tick('a number').icon, Icons.check_circle);
      expect(tick('a symbol').icon, Icons.radio_button_unchecked);

      // Not sent until the rule is met.
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();
      expect(
        find.text('Use at least 8 characters, with a number and a symbol.'),
        findsOneWidget,
      );
      expect(find.byKey(EmailSignInSteps.codeFieldKey), findsNothing);
    });

    testWidgets('waits a minute before another code, then sends one', (
      WidgetTester tester,
    ) async {
      var now = DateTime(2026, 10, 20, 9);
      final auth = FakeAuth();
      await pump(tester, auth, clock: () => now);
      await address(tester, 'sam@example.com');
      await password(tester, 'lifting-1', 'Create account');

      expect(find.text('Enter the 6-digit code we sent to'), findsOneWidget);
      expect(find.text('Send a new code in 1:00'), findsOneWidget);

      now = now.add(const Duration(seconds: 60));
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Send a new code'));
      await tester.pumpAndSettle();

      expect(auth.emailCalls, <String>['create', 'resend']);
      expect(
        find.text('A new code is on its way to sam@example.com.'),
        findsOneWidget,
      );
    });

    testWidgets('a wrong code says so, and stays on the code', (
      WidgetTester tester,
    ) async {
      final auth = FakeAuth();
      await pump(tester, auth);
      await address(tester, 'sam@example.com');
      await password(tester, 'lifting-1', 'Create account');
      await code(tester, '000000');

      expect(
        find.text(
          'That code is wrong or has expired. Check it, or send a new one.',
        ),
        findsOneWidget,
      );
      expect(auth.current, isNull);
      expect(find.byKey(EmailSignInSteps.codeFieldKey), findsOneWidget);
    });

    testWidgets('the code, then the name, then the screen closes with it '
        'written', (WidgetTester tester) async {
      final auth = FakeAuth();
      addTearDown(auth.dispose);
      final popped = await open(tester, auth, emailFirst: true);
      await makeAnAccount(tester);

      // Signed in, and asked once, in place of the form.
      expect(auth.current?.email, 'sam@example.com');
      expect(find.byType(AccountNameStep), findsOneWidget);
      expect(find.byType(EmailSignInSteps), findsNothing);
      expect(popped, isEmpty);
      final field = tester.widget<TextField>(
        find.byKey(AccountNameStep.fieldKey),
      );
      expect(field.controller?.text, isEmpty);

      await tester.enterText(find.byKey(AccountNameStep.fieldKey), ' Sam ');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(auth.namesWritten, <String?>['Sam']);
      expect(auth.current?.name, 'Sam');
      expect(popped, <bool?>[true]);
      expect(find.text('under'), findsOneWidget);
    });

    testWidgets('skipping the name writes nothing, and still signs in', (
      WidgetTester tester,
    ) async {
      final auth = FakeAuth();
      addTearDown(auth.dispose);
      final popped = await open(tester, auth, emailFirst: true);
      await makeAnAccount(tester);

      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();

      expect(auth.namesWritten, isEmpty);
      expect(popped, <bool?>[true]);
    });

    testWidgets('back on the name step is Skip: it closes signed in', (
      WidgetTester tester,
    ) async {
      // Closing with nothing would tell the sales screen there is no account.
      final auth = FakeAuth();
      addTearDown(auth.dispose);
      final popped = await open(tester, auth, emailFirst: true);
      await makeAnAccount(tester);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(auth.namesWritten, isEmpty);
      expect(popped, <bool?>[true]);
    });

    testWidgets('the stream does not close the screen past the name step', (
      WidgetTester tester,
    ) async {
      // The stream reports the account before the code's call returns. An
      // account whose code was typed long after it was made no longer reads
      // as new, so a stream left to decide would close the screen here; the
      // call that checked the code knows better.
      final auth = FakeAuth(readsAsNew: false);
      addTearDown(auth.dispose);
      final popped = await open(tester, auth, emailFirst: true);
      await makeAnAccount(tester);
      expect(find.byType(AccountNameStep), findsOneWidget);

      // Nor does anything else that arrives while the question is up.
      auth.arrive('sam@example.com');
      await tester.pumpAndSettle();
      expect(find.byType(AccountNameStep), findsOneWidget);
      expect(popped, isEmpty);
    });

    testWidgets('a name that does not save is said once, then lets them go', (
      WidgetTester tester,
    ) async {
      final auth = FakeAuth(nameFailure: AuthFailure.unavailable);
      addTearDown(auth.dispose);
      final popped = await open(tester, auth, emailFirst: true);
      await makeAnAccount(tester);

      await tester.enterText(find.byKey(AccountNameStep.fieldKey), 'Sam');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(
        find.text('Your name did not save. You can add it later in Settings.'),
        findsOneWidget,
      );
      expect(popped, isEmpty);

      // The second press goes on, whatever the server says.
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(popped, <bool?>[true]);
    });
  });

  group('Apple and Google', () {
    testWidgets('come first, with email one tap behind them', (
      WidgetTester tester,
    ) async {
      await pump(tester, FakeAuth(), emailFirst: false);

      expect(find.byType(ProviderSignInButton), findsNWidgets(2));
      expect(find.text('Continue with email'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(find.text('Continue with email'));
      await tester.pumpAndSettle();
      expect(find.byKey(EmailSignInSteps.emailFieldKey), findsOneWidget);
      expect(find.text('Other ways to sign in'), findsOneWidget);
    });

    testWidgets('say that they make an account too', (
      WidgetTester tester,
    ) async {
      // "Sign in" alone reads as a door for people who already have one.
      await pump(tester, FakeAuth(), emailFirst: false);
      expect(find.text('Sign in or create your account'), findsOneWidget);
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

    testWidgets('a new Apple account is never asked its name', (
      WidgetTester tester,
    ) async {
      // Guideline 4: App Review rejected Run 1.0.0 for asking after Sign in
      // with Apple, though the question could be skipped.
      final auth = FakeAuth(providerMakesAccount: true);
      addTearDown(auth.dispose);
      final popped = await open(tester, auth);

      await tester.tap(find.text('Continue with Apple'));
      await tester.pumpAndSettle();

      expect(auth.isNewAccount, isTrue);
      expect(find.byType(AccountNameStep), findsNothing);
      expect(popped, <bool?>[true]);
    });

    testWidgets('Google signs into an account and closes the screen', (
      WidgetTester tester,
    ) async {
      final auth = FakeAuth();
      addTearDown(auth.dispose);
      final popped = await open(tester, auth);

      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();

      expect(auth.lastProvider, 'google');
      expect(find.byType(AccountNameStep), findsNothing);
      expect(popped, <bool?>[true]);
    });

    testWidgets("a new Google account is asked, starting with Google's first "
        'name', (WidgetTester tester) async {
      final auth = FakeAuth(providerMakesAccount: true, googleName: 'Sam Lee');
      addTearDown(auth.dispose);
      final popped = await open(tester, auth);

      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();

      expect(find.byType(AccountNameStep), findsOneWidget);
      expect(find.text('Create your account'), findsOneWidget);
      final field = tester.widget<TextField>(
        find.byKey(AccountNameStep.fieldKey),
      );
      expect(field.controller?.text, 'Sam');
      expect(popped, isEmpty);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(auth.namesWritten, <String?>['Sam']);
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
      expect(find.text('Sign in or create your account'), findsOneWidget);
      for (final failure in AuthFailure.values) {
        expect(find.text(failure.message), findsNothing);
      }
      // And the buttons are usable again.
      final apple = tester.widget<ProviderSignInButton>(
        find.byType(ProviderSignInButton).first,
      );
      expect(apple.onPressed, isNotNull);
    });

    for (final isNew in <bool>[false, true]) {
      testWidgets('Apple in the browser says so, and closes when it lands'
          '${isNew ? ', unasked, with a new account' : ''}', (
        WidgetTester tester,
      ) async {
        // Android: Apple's sign-in finishes in the browser and the account
        // arrives afterwards, through the link back into the app. A new
        // account made that way is Apple's too, and is not asked its name.
        final auth = FakeAuth(
          providerOutcome: ProviderOutcome.continuing,
          providerMakesAccount: isNew,
        );
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
        expect(auth.isNewAccount, isNew);
        expect(find.byType(AccountNameStep), findsNothing);
        expect(popped, <bool?>[true]);
      });
    }

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
