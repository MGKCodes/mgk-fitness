import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_auth/mgk_auth.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/core/config/app_config.dart';
import 'package:mgk_run/src/features/auth/data/auth_repository.dart';
import 'package:mgk_run/src/features/auth/presentation/sign_in_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'email_path.dart';

/// Row E5 of the build 12 field test: an account made in aeroplane mode.
///
/// Nothing failed and nothing said anything. The screen hung with no offline
/// state, then appeared to go through when the network came back. Three
/// separate faults produced that, and this file covers the two of them that are
/// visible from outside the repository — what the runner is told, and whether
/// an account that was genuinely created is reported as a failure.
///
/// The third, the missing deadline, is not directly observable from here: it
/// lives on a gotrue call this suite has no client for. What it *produces* is,
/// so [TimeoutException] is driven through the screen like any other failure.
///
/// **The email path's words are the suite's since 1.0.2** (ADR-0047):
/// `EmailSignInFlow` names each failure, and `mgk_auth`'s tests hold what each
/// server answer is sorted into. What stays here is what this screen does with
/// them, and the words it still writes itself, for Apple, Google and the debug
/// sign-in.
void main() {
  const offline =
      'We could not reach the server. Check your connection and try again.';
  const noSignal = 'No connection. Try again when you have a signal.';
  const generic = 'Something went wrong. Try again.';

  const dev = DevAccount(
    label: 'Dev',
    email: 'dev@mgkfitness.mgkcodes.com',
    password: 'password',
  );

  Future<int Function()> pumpScreen(
    WidgetTester tester,
    AuthRepository auth, {
    List<DevAccount> devAccounts = const <DevAccount>[],
  }) async {
    var authenticated = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SignInScreen(
          auth: auth,
          devAccounts: devAccounts,
          onAuthenticated: () => authenticated++,
        ),
      ),
    );
    return () => authenticated;
  }

  group('a phone that cannot reach the server says so', () {
    testWidgets('on every step of the email path, and stays usable', (
      tester,
    ) async {
      final auth = FakeAuthRepository();
      final authenticated = await pumpScreen(tester, auth);
      await openEmail(tester);
      await submitAddress(tester, FakeAuthRepository.passwordAddress);

      auth.emailFailure = EmailFailure.unavailable;
      await submitPassword(tester, FakeAuthRepository.rightPassword);

      expect(find.text(noSignal), findsOneWidget);
      expect(find.text(generic), findsNothing);
      expect(authenticated(), 0, reason: 'no session, so nothing to dismiss');
      // The whole complaint was a spinner with nothing behind it. Retrying has
      // to be possible the moment the runner turns the radio back on.
      expect(
        tester
            .widget<PrimaryButton>(
              find.widgetWithText(PrimaryButton, 'Sign in'),
            )
            .busy,
        isFalse,
      );

      auth.emailFailure = null;
      await submitPassword(tester, FakeAuthRepository.rightPassword);
      expect(auth.isSignedIn, isTrue);
      expect(authenticated(), 1);
    });

    testWidgets('making an account offline is not made, and says why', (
      tester,
    ) async {
      final auth = FakeAuthRepository();
      await pumpScreen(tester, auth);
      await openEmail(tester);
      await submitAddress(tester, newAddress);

      auth.emailFailure = EmailFailure.unavailable;
      await submitPassword(tester, goodNewPassword, label: 'Create account');

      expect(find.text(noSignal), findsOneWidget);
      expect(find.byKey(EmailSignInSteps.codeFieldKey), findsNothing);
      expect(find.text('Create your account'), findsOneWidget);
    });

    testWidgets('when gotrue wraps a dead socket in a retryable failure', (
      tester,
    ) async {
      // Verbatim the shape gotrue produces offline: it never lets a socket
      // error out raw, it wraps it in an AuthException whose message is the
      // underlying error's toString(). Printing that message — which the screen
      // used to do for anything wearing the AuthException type — put this at
      // somebody trying to sign in. The debug sign-in is the call left on this
      // screen that can still meet it.
      final auth = FakeAuthRepository()
        ..failure = AuthRetryableFetchException(
          message:
              'ClientException with SocketException: Failed host lookup, '
              'uri=https://db.example.supabase.co',
        );
      final authenticated = await pumpScreen(
        tester,
        auth,
        devAccounts: const <DevAccount>[dev],
      );

      await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Dev'));

      expect(find.text(offline), findsOneWidget);
      expect(
        find.textContaining('SocketException'),
        findsNothing,
        reason: 'the wrapped error is a stack trace in a sentence, not copy',
      );
      expect(find.text(generic), findsNothing);
      expect(authenticated(), 0);
    });

    testWidgets('when the call blows the deadline instead of answering', (
      tester,
    ) async {
      final auth = FakeAuthRepository()
        ..failure = TimeoutException('signIn', const Duration(seconds: 20));
      await pumpScreen(tester, auth, devAccounts: const <DevAccount>[dev]);

      await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Dev'));

      expect(find.text(offline), findsOneWidget);
      expect(find.text(generic), findsNothing);
    });

    testWidgets('and so does Google, in the same words', (tester) async {
      final auth = FakeAuthRepository()
        ..failure = const ProviderSignInException(ProviderFailure.unavailable);
      await pumpScreen(tester, auth);

      await tapVisible(tester, find.text('Continue with Google'));

      expect(find.text(offline), findsOneWidget);
    });
  });

  /// The other half of the same fix: the server answering is not a network
  /// fault, and its words are better than any paraphrase of them.
  testWidgets("a real refusal still shows the server's own message", (
    tester,
  ) async {
    final auth = FakeAuthRepository()
      ..failure = const AuthException('Invalid login credentials');
    await pumpScreen(tester, auth, devAccounts: const <DevAccount>[dev]);

    await tapVisible(tester, find.widgetWithText(OutlinedButton, 'Dev'));

    expect(find.text('Invalid login credentials'), findsOneWidget);
    expect(
      find.text(offline),
      findsNothing,
      reason:
          'AuthRetryableFetchException is a subtype of this, so the offline '
          'branch has to be the narrower test, not the broader one',
    );
  });

  /// The correctness trap, and the expensive one: the account was made.
  group('an account that exists is not a failure', () {
    testWidgets('making one survives a profile write that does not land', (
      tester,
    ) async {
      final auth = FakeAuthRepository()
        ..profileFailure = const SocketException('Network is unreachable');
      final authenticated = await pumpScreen(tester, auth);

      await createAccountByEmail(tester);

      expect(
        authenticated(),
        1,
        reason:
            'the gate this was raised from has to dismiss, or the runner is '
            'left on a finished form and tries to make the account again',
      );
      expect(find.text(generic), findsNothing);
      expect(find.text(noSignal), findsNothing);
      expect(auth.isSignedIn, isTrue);
      expect(
        auth.profileWrites,
        1,
        reason: 'the row was attempted; swallowing is not skipping',
      );
    });

    testWidgets('and so does signing back in', (tester) async {
      final auth = FakeAuthRepository()
        ..profileFailure = const SocketException('Network is unreachable');
      final authenticated = await pumpScreen(tester, auth);

      await signInByEmail(tester);

      expect(authenticated(), 1);
      expect(find.text(generic), findsNothing);
      expect(auth.isSignedIn, isTrue);
      expect(auth.profileWrites, 1);
    });
  });

  /// Straight at the seam, with no screen and no Supabase in the way, because
  /// this is the line the whole third fix rests on.
  test('ensureProfileBestEffort absorbs what ensureProfile throws', () async {
    await expectLater(
      _ProfileWriteFails().ensureProfileBestEffort(),
      completes,
    );
    // The swallow belongs to the wrapper. [AuthRepository.ensureProfile] stays
    // honest for any caller that does want to know it failed.
    await expectLater(
      _ProfileWriteFails().ensureProfile(),
      throwsA(isA<SocketException>()),
    );
  });
}

/// A repository whose `core.profiles` upsert fails the way an unreachable
/// network fails it, and which touches no Supabase client to do so.
class _ProfileWriteFails extends AuthRepository {
  @override
  Future<void> ensureProfile() async {
    throw const SocketException('Network is unreachable');
  }
}
