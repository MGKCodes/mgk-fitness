import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/features/auth/presentation/auth_gate.dart';
import 'package:mgk_run/src/features/history/domain/run_writer.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_permission.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_script.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_store.dart';
import 'package:mgk_run/src/features/settings/domain/backup_consent.dart';
import 'package:mgk_ui/mgk_ui.dart';

import 'email_path.dart';

/// **Whether an account is new is read from the account** (ADR-0047, point
/// 7), and what follows from it, seen through the whole app.
///
/// The sign-in screen used to report which half of its form was showing
/// (`onSignUpIntent`), and the gate took that as the answer: a new account
/// skipped the coach's introduction and the restore. Neither half of that
/// holds now. The intro ends without an account, so an account made at the
/// sign-in has never met the coach and meets it here, and its conversation is
/// Run's name step. The restore is skipped for an account the account itself
/// says was just made, by any way in.
void main() {
  late _CountingRestore restore;

  setUp(() => restore = _CountingRestore());

  /// The app on a phone that has never met the coach, opened at the welcome.
  /// Backup is already allowed, so a restore that runs is not held behind its
  /// question.
  Future<void> pumpGate(
    WidgetTester tester,
    FakeAuthRepository auth, {
    IntroStore? intro,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: AuthGate(
          auth: auth,
          introStore: intro ?? InMemoryIntroStore(),
          historySource: () async => const [],
          restore: restore,
          consentStore: InMemoryBackupConsent(BackupConsent.granted),
          requestPermission: (_) async => true,
        ),
      ),
    );
    // The gate reads its intro marker asynchronously, so frame one is blank.
    await tester.pump();
    await tester.pumpAndSettle();
  }

  /// Through every permission the intro asks for, to the shell.
  Future<void> throughPermissions(WidgetTester tester) async {
    for (final permission in introPermissionsFor(defaultTargetPlatform)) {
      await tester.tap(find.text(permission.cta));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }
  }

  /// The intro's name field, and what is in it.
  String? nameInField(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller?.text;

  testWidgets('a new email account meets the coach, is asked its name there, '
      'and skips the restore', (tester) async {
    final auth = FakeAuthRepository();
    await pumpGate(tester, auth);

    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();
    await createAccountByEmail(tester);
    await tester.pumpAndSettle();

    expect(auth.accountIsNew, isTrue);
    // The conversation, since this account has never had it.
    expect(find.text(introWhoIAm), findsOneWidget);
    await tester.tap(find.text('Sounds good'));
    await tester.pumpAndSettle();
    // Run's name step is the coach's question: no second one anywhere.
    expect(find.text(introPrompt(IntroStep.name)), findsOneWidget);
    expect(nameInField(tester), isEmpty, reason: 'nothing to start it with');
    await tester.enterText(find.byType(TextField), 'Sam');
    await tester.tap(find.byTooltip('Continue'));
    await tester.pumpAndSettle();
    await throughPermissions(tester);

    expect(find.byType(HomeShell), findsOneWidget);
    expect(auth.coachMarks, 1);
    expect(auth.currentName, 'Sam', reason: 'the name is the account\'s');
    expect(
      restore.calls,
      0,
      reason: 'an account made seconds ago has nothing on the server',
    );
  });

  testWidgets('a returning account signs straight in, and restores', (
    tester,
  ) async {
    final auth = FakeAuthRepository();
    await pumpGate(tester, auth);

    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();
    await signInByEmail(tester);
    await tester.pumpAndSettle();

    expect(auth.accountIsNew, isFalse);
    expect(find.text(introWhoIAm), findsNothing, reason: 'met the coach');
    expect(find.byType(HomeShell), findsOneWidget);
    expect(restore.calls, 1);
  });

  testWidgets('a new Google account is asked its name with Google\'s first '
      'name filled in, and can change it', (tester) async {
    final auth = FakeAuthRepository(
      metCoach: false,
      newAccount: true,
      googleName: 'Matthew',
    );
    await pumpGate(tester, auth);

    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Continue with Google'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sounds good'));
    await tester.pumpAndSettle();
    // Asked, not assumed: nobody has to use the name their provider holds.
    expect(find.text(introPrompt(IntroStep.name)), findsOneWidget);
    expect(nameInField(tester), 'Matthew');

    await tester.enterText(find.byType(TextField), 'Matt');
    await tester.tap(find.byTooltip('Continue'));
    await tester.pumpAndSettle();
    await throughPermissions(tester);

    expect(auth.currentName, 'Matt');
    expect(restore.calls, 0, reason: 'new, by Google as by email');
  });

  testWidgets('and clearing Google\'s name leaves the account without one', (
    tester,
  ) async {
    final auth = FakeAuthRepository(
      metCoach: false,
      newAccount: true,
      googleName: 'Matthew',
    );
    await pumpGate(tester, auth);

    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();
    await tapVisible(tester, find.text('Continue with Google'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sounds good'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.byTooltip('Continue'));
    await tester.pumpAndSettle();
    await throughPermissions(tester);

    expect(auth.currentName, isNull, reason: 'the prefill was only offered');
  });

  testWidgets('nothing is asked after Apple, even with a Google name on '
      'the account', (tester) async {
    // An account that has both: Apple's rule wins, because the question
    // itself is what App Review refused, filled in or not.
    final auth = FakeAuthRepository(
      signedIn: true,
      apple: true,
      metCoach: false,
      googleName: 'Matthew',
    );
    await pumpGate(tester, auth);

    await tester.tap(find.text('Sounds good'));
    await tester.pumpAndSettle();

    expect(find.text(introPrompt(IntroStep.name)), findsNothing);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a session restored at launch is not a new account, however '
      'new the account says it is', (tester) async {
    // The account reads as new until it next signs in, which can be days:
    // a restored session is not a sign-in. Taken at its word on a launch, it
    // would skip the restore and the launch backfill every time.
    final auth = FakeAuthRepository(signedIn: true, newAccount: true);
    await pumpGate(tester, auth);

    expect(auth.accountIsNew, isTrue);
    expect(find.byType(HomeShell), findsOneWidget);
    expect(restore.calls, 1);
  });
}

/// Records that it was asked.
class _CountingRestore implements DataRestore {
  int calls = 0;

  @override
  Future<RestoreResult> restoreAll() async {
    calls++;
    return RestoreResult();
  }
}
