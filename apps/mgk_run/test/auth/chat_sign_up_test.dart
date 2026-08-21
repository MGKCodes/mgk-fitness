import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/features/auth/data/auth_repository.dart';
import 'package:mgk_run/src/features/auth/presentation/auth_gate.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_permission.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_script.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Refuses every sign-up the way the backend does, and counts the attempts.
class _RefusingAuth extends FakeAuthRepository {
  _RefusingAuth({required this.throwing});

  /// Whether to throw, or simply report that no session was created.
  final bool throwing;
  int attempts = 0;

  @override
  Future<bool> signUp({
    required String email,
    required String password,
    String? name,
  }) async {
    attempts++;
    if (throwing) {
      throw const AuthException(
        'Password should be at least 6 characters. anon_key=abc123',
      );
    }
    return false;
  }
}

/// Sign-up happens **in the conversation**, and these are the paths through it
/// that are not the happy one.
///
/// The happy path is walked by `onboarding_flow_test.dart`. What is here is
/// everything that used to be a form's job — a validator, a red line under a
/// field, a backend message rendered verbatim — now that there is no form to
/// do it.
void main() {
  Future<void> toEmailStep(WidgetTester tester, {AuthRepository? auth}) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: AuthGate(
          auth: auth ?? FakeAuthRepository(),
          historySource: () async => const [],
          requestPermission: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

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
  }

  Future<void> toPasswordStep(
    WidgetTester tester, {
    AuthRepository? auth,
  }) async {
    await toEmailStep(tester, auth: auth);
    await tester.enterText(find.byType(TextField), 'sam@runio.app');
    await tester.tap(find.byTooltip('Continue'));
    await tester.pumpAndSettle();
  }

  testWidgets('the sign-up path never shows a form', (tester) async {
    await toPasswordStep(tester);

    // `TextFormField` is what the sign-in screen is built from. Its absence is
    // the assertion: the conversation asks for the address and the password
    // itself rather than pushing a screen that does.
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Create your account'), findsNothing);
    expect(
      find.byType(TextField),
      findsOneWidget,
      reason: 'one question at a time, or it is a form in a chat bubble',
    );
  });

  testWidgets('a mistyped address is questioned, not rejected', (tester) async {
    await toEmailStep(tester);

    await tester.enterText(find.byType(TextField), 'sam at runio');
    await tester.tap(find.byTooltip('Continue'));
    await tester.pumpAndSettle();

    expect(find.text(introBadEmail), findsOneWidget);
    expect(
      find.text(introPrompt(IntroStep.password)),
      findsNothing,
      reason: 'and it does not move on',
    );
  });

  testWidgets('the password rule is said before the password is asked for', (
    tester,
  ) async {
    await toPasswordStep(tester);

    expect(
      find.textContaining('$kMinPasswordLength characters'),
      findsOneWidget,
      reason: 'a rule quoted only on rejection is a rule kept back',
    );
  });

  testWidgets('a short password never reaches the backend', (tester) async {
    final auth = _RefusingAuth(throwing: true);
    await toPasswordStep(tester, auth: auth);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.tap(find.byTooltip('Create my profile'));
    await tester.pumpAndSettle();

    expect(find.text(introShortPassword), findsOneWidget);
    expect(
      auth.attempts,
      0,
      reason: 'the rule was stated here, so it is enforced here',
    );
  });

  testWidgets('a refused sign-up says a code, never the backend words', (
    tester,
  ) async {
    final auth = _RefusingAuth(throwing: true);
    await toPasswordStep(tester, auth: auth);

    await tester.enterText(find.byType(TextField), 'long enough');
    await tester.tap(find.byTooltip('Create my profile'));
    await tester.pumpAndSettle();

    expect(auth.attempts, 1);
    expect(find.text(introTrouble(kSignUpCodeRefused)), findsOneWidget);
    expect(
      find.textContaining('anon_key'),
      findsNothing,
      reason: 'a backend message is written for a log, not for a first screen',
    );
  });

  testWidgets('an unconfirmed address is not dressed up as a failure', (
    tester,
  ) async {
    // No session, but nothing went wrong: the profile exists and the only
    // thing left is a link in an inbox.
    final auth = _RefusingAuth(throwing: false);
    await toPasswordStep(tester, auth: auth);

    await tester.enterText(find.byType(TextField), 'long enough');
    await tester.tap(find.byTooltip('Create my profile'));
    await tester.pumpAndSettle();

    expect(find.text(introConfirmEmail), findsOneWidget);
    expect(find.textContaining('E-ACC'), findsNothing);
  });
}
