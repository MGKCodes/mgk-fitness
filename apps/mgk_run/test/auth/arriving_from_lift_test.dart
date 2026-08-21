import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/features/auth/presentation/auth_gate.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_permission.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_script.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// **Signed in is not the same as onboarded.**
///
/// For as long as signing up and onboarding were one moment, reading the two as
/// one thing was correct. They are not one moment any more, and under a shared
/// profile the gap between them is the growth path rather than an edge case: a
/// runner makes their profile in Lift, installs this app, and arrives with a
/// session and no idea what this coach is.
///
/// The consequence is not only a missed conversation. `GeolocatorLocationSource`
/// requests location at recording time when it has not been granted, so that
/// runner presses start and meets the OS dialog on top of the run they are
/// trying to begin — which is the exact scenario ADR-0019 moved permissions
/// into onboarding to avoid.
void main() {
  Future<void> pumpGate(WidgetTester tester, FakeAuthRepository auth) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: AuthGate(
          auth: auth,
          historySource: () async => const [],
          requestPermission: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a signed-in runner who has never met the coach gets the '
      'conversation, not the shell', (tester) async {
    await pumpGate(
      tester,
      FakeAuthRepository(signedIn: true, name: 'Sam', metCoach: false),
    );

    expect(find.text(introWhoIAm), findsOneWidget);
    expect(
      find.text('Record a run'),
      findsNothing,
      reason: 'the shell is what they would have been dropped into',
    );
  });

  testWidgets('and is not asked for a name the profile already carries', (
    tester,
  ) async {
    await pumpGate(
      tester,
      FakeAuthRepository(signedIn: true, name: 'Sam', metCoach: false),
    );

    expect(find.text(introPrompt(IntroStep.name)), findsNothing);

    await tester.tap(find.text('Sounds good'));
    await tester.pumpAndSettle();

    // Straight to the permissions, which are the only thing this install has
    // genuinely never answered.
    expect(find.text(introPermissions.first.explain), findsOneWidget);
    expect(find.text(introPrompt(IntroStep.name)), findsNothing);
  });

  testWidgets('and is never asked to make a second profile', (tester) async {
    final auth = FakeAuthRepository(
      signedIn: true,
      name: 'Sam',
      metCoach: false,
    );
    await pumpGate(tester, auth);

    await tester.tap(find.text('Sounds good'));
    await tester.pumpAndSettle();
    for (final permission in introPermissions) {
      expect(
        find.text(introPrompt(IntroStep.signUp)),
        findsNothing,
        reason: 'they have a profile; asking again dead-ends on it',
      );
      await tester.tap(find.text(permission.cta));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }

    // The conversation is over, the fact is recorded, and Home is underneath.
    expect(auth.coachMarks, 1);
    expect(find.text(introPrompt(IntroStep.signUp)), findsNothing);
  });

  testWidgets('a runner who has met the coach goes straight to the shell', (
    tester,
  ) async {
    final auth = FakeAuthRepository(signedIn: true, name: 'Sam');
    await pumpGate(tester, auth);

    expect(find.text(introWhoIAm), findsNothing);
    expect(
      auth.coachMarks,
      0,
      reason: 'nothing to record, and nothing to re-record on every launch',
    );
  });

  testWidgets('creating a profile here records the fact too', (tester) async {
    // Otherwise the runner who signs up on this phone is shown the whole
    // conversation again on their next one.
    final auth = FakeAuthRepository(metCoach: false);
    await pumpGate(tester, auth);

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
    await tester.enterText(find.byType(TextField), 'sam@runio.app');
    await tester.tap(find.byTooltip('Continue'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'password');
    await tester.tap(find.byTooltip('Create my profile'));
    await tester.pumpAndSettle();

    expect(auth.coachMarks, 1);
    // And the conversation they just finished is not immediately replayed by
    // the gate above, which has not seen the write land yet.
    expect(find.text(introWhoIAm), findsNothing);
  });
}
