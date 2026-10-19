/// The email path, walked the way a runner walks it (ADR-0047): the address,
/// then the one step it leads to.
///
/// Shared by every test that signs in or makes an account with an address, so
/// a change to the steps is mended here once rather than in each of them. Not
/// a `_test.dart` file, so it is not a suite of its own.
///
/// **Fixed pumps after every press.** A submitting `PrimaryButton` draws an
/// indeterminate spinner, and `pumpAndSettle` never returns on a screen
/// showing one. The fake answers at once, so a frame and a second are plenty.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// A new address, and a password that meets the rule (8 characters, a number
/// and a symbol), for making an account.
const String newAddress = 'new@example.com';
const String goodNewPassword = 'Hunter-2222';

/// Scrolls [target] into view and taps it. The default test surface is
/// shorter than a phone, and the lower buttons can sit below it, where a plain
/// tap lands on nothing.
Future<void> tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// From Apple, Google and email, to the address.
Future<void> openEmail(WidgetTester tester) async {
  await tapVisible(tester, find.text('Continue with email'));
}

/// Types [address] into the address step and presses Continue.
Future<void> submitAddress(WidgetTester tester, String address) async {
  await tester.enterText(find.byKey(EmailSignInSteps.emailFieldKey), address);
  await tester.pump();
  await tapVisible(tester, find.widgetWithText(PrimaryButton, 'Continue'));
}

/// Types [password] into the password field and presses [label]: *Sign in* on
/// *Welcome back*, *Create account* on *Create your account*.
Future<void> submitPassword(
  WidgetTester tester,
  String password, {
  String label = 'Sign in',
}) async {
  await tester.enterText(
    find.byKey(EmailSignInSteps.passwordFieldKey),
    password,
  );
  await tester.pump();
  await tapVisible(tester, find.widgetWithText(PrimaryButton, label));
}

/// Types [code] into the code step. The sixth digit sends it, as Mail's
/// autofill does, so there is no button to press.
Future<void> enterCode(WidgetTester tester, String code) async {
  await tester.enterText(find.byKey(EmailSignInSteps.codeFieldKey), code);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// Signing back in with an address that has a password, from the three
/// choices.
Future<void> signInByEmail(
  WidgetTester tester, {
  String address = FakeAuthRepository.passwordAddress,
  String password = FakeAuthRepository.rightPassword,
}) async {
  await openEmail(tester);
  await submitAddress(tester, address);
  await submitPassword(tester, password);
}

/// Making an account with an address, from the three choices: the address,
/// a new password, then the code from the email.
Future<void> createAccountByEmail(
  WidgetTester tester, {
  String address = newAddress,
  String password = goodNewPassword,
  String code = FakeAuthRepository.rightCode,
}) async {
  await openEmail(tester);
  await submitAddress(tester, address);
  await submitPassword(tester, password, label: 'Create account');
  await enterCode(tester, code);
}
