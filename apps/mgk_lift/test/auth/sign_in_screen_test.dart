import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/auth/data/fake_auth.dart';
import 'package:mgk_lift/src/features/auth/domain/account.dart';
import 'package:mgk_lift/src/features/auth/presentation/sign_in_screen.dart';

Future<void> pump(
  WidgetTester tester,
  AuthService auth, {
  int pending = 0,
}) async {
  tester.view.physicalSize = const Size(1080, 4200);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: SignInScreen(auth: auth, pendingWorkouts: pending)),
  );
  await tester.pumpAndSettle();
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

  testWidgets('the reason to sign up is specific, not a category', (
    WidgetTester tester,
  ) async {
    await pump(tester, FakeAuth(), pending: 9);
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('9 sessions exist only on this phone'),
      findsOneWidget,
    );
  });

  testWidgets('one screen toggles between signing in and signing up', (
    WidgetTester tester,
  ) async {
    await pump(tester, FakeAuth());
    expect(find.text('Welcome back'), findsOneWidget);

    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    expect(find.text('Back up your training'), findsOneWidget);

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

      expect(find.text('That email and password do not match.'), findsOneWidget);
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
}
