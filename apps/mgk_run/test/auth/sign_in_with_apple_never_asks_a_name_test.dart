import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/features/auth/presentation/auth_gate.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_permission.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_store.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_script.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// **Nothing asks for a name after Sign in with Apple.**
///
/// App Review rejected 1.0.0 (build 29, 16 October 2026) under guideline 4:
/// the reviewer signed in with Apple on a fresh install, the new account had
/// never met the coach, and the intro asked "What should I call you?". Apple's
/// rule is that a name or an email its sheet could have supplied is not asked
/// for afterwards.
///
/// The same question had a second way in: a runner who met the coach before
/// having an account, then signed in for a plan, had the whole intro played
/// again on the next launch, because nothing recorded the meeting against the
/// new account.
void main() {
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
          introStore: intro ?? InMemoryIntroStore(),
          auth: auth,
          historySource: () async => const [],
          requestPermission: (_) async => true,
        ),
      ),
    );
    // The gate reads its intro marker asynchronously, so frame one is blank.
    await tester.pump();
    await tester.pumpAndSettle();
  }

  testWidgets('signing in with Apple on a fresh install meets the coach '
      'without being asked a name', (tester) async {
    final auth = FakeAuthRepository(metCoach: false);
    await pumpGate(tester, auth);

    // The reviewer's path: the welcome screen, the sign-in form, Apple.
    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue with Apple'));
    await tester.pumpAndSettle();
    expect(auth.lastProvider, 'apple');

    // The conversation, since this account has never had it.
    expect(find.text(introWhoIAm), findsOneWidget);
    await tester.tap(find.text('Sounds good'));
    await tester.pumpAndSettle();

    expect(find.text(introPrompt(IntroStep.name)), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(
      find.text(introPermissionsFor(defaultTargetPlatform).first.explain),
      findsOneWidget,
      reason: 'straight from the greeting to the permissions',
    );

    for (final permission in introPermissionsFor(defaultTargetPlatform)) {
      expect(find.byType(TextField), findsNothing);
      await tester.tap(find.text(permission.cta));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }

    expect(auth.coachMarks, 1);
    expect(
      auth.currentName,
      isNull,
      reason: 'no name was given, and none is made up',
    );
  });

  testWidgets('an email account with no name is still asked', (tester) async {
    // Unchanged on purpose: the rule is Apple's, about Apple's sheet. An
    // account made with an address in Lift carries no name to skip to.
    await pumpGate(tester, FakeAuthRepository(signedIn: true, metCoach: false));

    await tester.tap(find.text('Sounds good'));
    await tester.pumpAndSettle();

    expect(find.text(introPrompt(IntroStep.name)), findsOneWidget);
  });

  group('an install that met the coach before signing in', () {
    testWidgets('does not play the intro again', (tester) async {
      final auth = FakeAuthRepository(
        signedIn: true,
        metCoach: false,
        apple: true,
      );
      await pumpGate(
        tester,
        auth,
        intro: InMemoryIntroStore(done: true, name: 'Alex'),
      );

      expect(find.text(introWhoIAm), findsNothing);
      expect(find.text(introPrompt(IntroStep.name)), findsNothing);
      expect(
        auth.coachMarks,
        1,
        reason: 'recorded against the account, so the next launch is quiet',
      );
    });

    testWidgets('gives the profile the name the phone was told', (
      tester,
    ) async {
      final auth = FakeAuthRepository(signedIn: true, metCoach: false);
      await pumpGate(
        tester,
        auth,
        intro: InMemoryIntroStore(done: true, name: 'Alex'),
      );

      expect(auth.currentName, 'Alex');
    });

    testWidgets('and leaves a name the profile already has', (tester) async {
      final auth = FakeAuthRepository(
        signedIn: true,
        name: 'Sam',
        metCoach: false,
      );
      await pumpGate(
        tester,
        auth,
        intro: InMemoryIntroStore(done: true, name: 'Alex'),
      );

      expect(auth.currentName, 'Sam');
    });
  });
}
