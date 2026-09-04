import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/features/auth/data/auth_repository.dart';
import 'package:mgk_run/src/features/auth/presentation/sign_in_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
void main() {
  const offline =
      'We could not reach the server. Check your connection and try again.';
  const generic = 'Something went wrong. Try again.';

  /// The form, filled in and submitted. Fixed pumps rather than `pumpAndSettle`
  /// — a submitting `PrimaryButton` draws an indeterminate spinner, and settle
  /// never returns on a screen showing one.
  Future<void> submit(WidgetTester tester, {required String label}) async {
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'sam@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'hunter2222',
    );
    // Scrolled to first: in sign-up mode the "what you get" block pushes the
    // button off an 800x600 test surface, and a tap that misses is a test that
    // passes for the wrong reason.
    final button = find.widgetWithText(PrimaryButton, label);
    await tester.ensureVisible(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  group('a phone that cannot reach the server says so', () {
    testWidgets('when gotrue wraps a dead socket in a retryable failure', (
      tester,
    ) async {
      // Verbatim the shape gotrue produces offline: it never lets a socket
      // error out raw, it wraps it in an AuthException whose message is the
      // underlying error's toString(). Printing that message — which the screen
      // used to do for anything wearing the AuthException type — put this at
      // somebody trying to sign in.
      final auth = FakeAuthRepository()
        ..failure = AuthRetryableFetchException(
          message:
              'ClientException with SocketException: Failed host lookup, '
              'uri=https://db.example.supabase.co',
        );
      var authenticated = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SignInScreen(
            auth: auth,
            onAuthenticated: () => authenticated++,
          ),
        ),
      );

      await submit(tester, label: 'Sign in');

      expect(find.text(offline), findsOneWidget);
      expect(
        find.textContaining('SocketException'),
        findsNothing,
        reason: 'the wrapped error is a stack trace in a sentence, not copy',
      );
      expect(find.text(generic), findsNothing);
      expect(
        authenticated,
        0,
        reason: 'no session was created, so nothing should be dismissed',
      );
    });

    testWidgets('when the call blows the deadline instead of answering', (
      tester,
    ) async {
      final auth = FakeAuthRepository()
        ..failure = TimeoutException('signUp', const Duration(seconds: 20));
      await tester.pumpWidget(
        MaterialApp(home: SignInScreen(auth: auth, initialSignUp: true)),
      );

      await submit(tester, label: 'Sign up');

      expect(find.text(offline), findsOneWidget);
      expect(find.text(generic), findsNothing);
    });

    testWidgets('and the form is usable again rather than stuck busy', (
      tester,
    ) async {
      final auth = FakeAuthRepository()
        ..failure = TimeoutException('signIn', const Duration(seconds: 20));
      await tester.pumpWidget(MaterialApp(home: SignInScreen(auth: auth)));

      await submit(tester, label: 'Sign in');

      // The whole complaint was a spinner with nothing behind it. Retrying has
      // to be possible the moment the runner turns the radio back on.
      final button = tester.widget<PrimaryButton>(
        find.widgetWithText(PrimaryButton, 'Sign in'),
      );
      expect(button.busy, isFalse);
    });
  });

  /// The other half of the same fix: the server answering is not a network
  /// fault, and its words are better than any paraphrase of them.
  testWidgets("a real refusal still shows the server's own message", (
    tester,
  ) async {
    final auth = FakeAuthRepository()
      ..failure = const AuthException('Invalid login credentials');
    await tester.pumpWidget(MaterialApp(home: SignInScreen(auth: auth)));

    await submit(tester, label: 'Sign in');

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
    testWidgets('signing up survives a profile write that does not land', (
      tester,
    ) async {
      final auth = FakeAuthRepository()
        ..profileFailure = const SocketException('Network is unreachable');
      var authenticated = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SignInScreen(
            auth: auth,
            initialSignUp: true,
            onAuthenticated: () => authenticated++,
          ),
        ),
      );

      await submit(tester, label: 'Sign up');

      expect(
        authenticated,
        1,
        reason:
            'the gate this was raised from has to dismiss, or the runner is '
            'left on a finished form and retries into "User already '
            'registered"',
      );
      expect(find.text(generic), findsNothing);
      expect(find.text(offline), findsNothing);
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
      var authenticated = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SignInScreen(
            auth: auth,
            onAuthenticated: () => authenticated++,
          ),
        ),
      );

      await submit(tester, label: 'Sign in');

      expect(authenticated, 1);
      expect(find.text(generic), findsNothing);
      expect(auth.isSignedIn, isTrue);
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
