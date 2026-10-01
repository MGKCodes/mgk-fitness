import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/preview/fake_coach_service.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/auth/presentation/auth_gate.dart';
import 'package:mgk_run/src/features/coaching/domain/intake_slots.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_shape.dart';
import 'package:mgk_run/src/core/config/app_config.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_flow.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_permission.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_store.dart';
import 'package:mgk_run/src/features/settings/domain/backup_consent.dart';

/// A consent store that records whether it was asked, and when.
class _RecordingConsent implements BackupConsentStore {
  BackupConsent _value = BackupConsent.unknown;
  int reads = 0;

  @override
  Future<BackupConsent> read() async {
    reads++;
    return _value;
  }

  @override
  Future<void> write(BackupConsent value) async => _value = value;
}

/// Creating an account and signing back into one are different acts, and the
/// app used to treat them identically: both landed on an empty Home with the
/// one thing worth doing hidden behind a button, and both were met by a
/// data-privacy modal first (ADR-0017).
///
/// Walks **moment one**: the greeting, a name, each permission in turn, then
/// the address and the password. What it no longer walks is the shape question
/// and the costs statement, which moved to the plan flow (ADR-0019) — nor a
/// form, because there is no longer one to walk: the profile is created in the
/// conversation itself.
///
/// Driven off `introPermissionsFor(defaultTargetPlatform)` rather than a fixed list of taps, so adding or
/// removing a permission does not silently strand every flow test on a screen
/// it does not know how to leave.
Future<void> _throughIntro(WidgetTester tester, {String? name}) async {
  await tester.tap(find.text('Get started'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Sounds good'));
  await tester.pumpAndSettle();
  if (name != null) await tester.enterText(find.byType(TextField), name);
  await tester.tap(find.byTooltip('Continue'));
  await tester.pumpAndSettle();
  for (final permission in introPermissionsFor(defaultTargetPlatform)) {
    await tester.tap(find.text(permission.cta));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('creating an account lands on Home, not in the plan flow', (
    tester,
  ) async {
    // This assertion is the inverse of the one it replaces, and deliberately.
    // Sign-up used to push the plan flow the instant the shell mounted, which
    // made building a plan the price of finishing sign-up. Onboarding is two
    // moments now (ADR-0019): this one ends with a free account and a working
    // run tracker, and the plan is somewhere a runner goes.
    //
    // The coach has still been met — that happened in the intro, which is the
    // whole reason it is a conversation (ADR-0018).
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final auth = FakeAuthRepository();
    final consent = _RecordingConsent();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: AuthGate(
          introStore: InMemoryIntroStore(),
          auth: auth,
          coach: FakeCoachService(),
          consentStore: consent,
          historySource: () async => const [],
          requestPermission: (_) async => true,
        ),
      ),
    );
    // The gate reads its intro marker asynchronously, so frame one is blank.
    await tester.pump();
    await tester.pumpAndSettle();

    await _throughIntro(tester, name: 'Sam');

    expect(
      find.byType(CoachFlow),
      findsNothing,
      reason: 'a plan is asked for, not the toll for finishing sign-up',
    );

    // And nothing asks to back up data that does not exist yet. The account is
    // seconds old, so there is nothing to restore and nothing to copy; the
    // question is picked up on the next launch, by which time they have had a
    // chance to use the app (ADR-0012).
    expect(
      consent.reads,
      0,
      reason: 'consent for a backup of nothing is a question with no meaning',
    );
  });

  group('the coach answers the permission either way', () {
    /// Walks as far as the location dialog and reports what the coach said
    /// after [granted].
    Future<void> toLocationAnswer(
      WidgetTester tester, {
      required bool granted,
    }) async {
      await tester.binding.setSurfaceSize(const Size(420, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: AuthGate(
            introStore: InMemoryIntroStore(),
            auth: FakeAuthRepository(),
            historySource: () async => const [],
            requestPermission: (_) async => granted,
          ),
        ),
      );
      // The gate reads its intro marker asynchronously, so frame one is blank.
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sounds good'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Sam');
      await tester.tap(find.byTooltip('Continue'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(introPermissionsFor(defaultTargetPlatform).first.cta),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('allowed is acknowledged and moves on', (tester) async {
      await toLocationAnswer(tester, granted: true);

      expect(find.text('Allowed'), findsOneWidget);
      expect(find.textContaining('the one that matters'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('and refused is answered, not treated as a failure', (
      tester,
    ) async {
      // The point of asking here rather than mid-run is that somebody is
      // sitting still and can be told what a no actually costs them. A refusal
      // that produced a dead end, or nothing at all, would be worse than the
      // system prompt landing on a pavement.
      await toLocationAnswer(tester, granted: false);

      expect(find.text('Not now'), findsOneWidget);
      expect(find.textContaining('No problem'), findsOneWidget);
      expect(
        find.textContaining('log them just the same'),
        findsOneWidget,
        reason: 'a refusal has to say what still works',
      );
      expect(
        find.text('Continue'),
        findsOneWidget,
        reason: 'and must not be a dead end',
      );
    });
  });

  testWidgets('the name is kept even though there is no account to keep it on', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // **The regression this guards.** The intro asks what to call somebody and
    // then, since it stopped creating an account, had nowhere to put the
    // answer: `currentName` reads auth metadata, and there is no session. The
    // runner would tell the coach their name and the coach would forget it
    // between the last permission and the first screen.
    final auth = FakeAuthRepository();
    final intro = InMemoryIntroStore();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: AuthGate(
          introStore: intro,
          auth: auth,
          historySource: () async => const [],
          requestPermission: (_) async => true,
        ),
      ),
    );
    // The gate reads its intro marker asynchronously, so frame one is blank.
    await tester.pump();
    await tester.pumpAndSettle();

    await _throughIntro(tester, name: 'Sam');

    expect(await intro.readName(), 'Sam');
    expect(
      auth.lastName,
      isNull,
      reason: 'nothing signed up, so nothing was written to a profile',
    );
  });

  testWidgets('signing in asks for no name — they already have one', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: AuthGate(
          introStore: InMemoryIntroStore(),
          auth: FakeAuthRepository(),
          historySource: () async => const [],
          requestPermission: (_) async => true,
        ),
      ),
    );
    // The gate reads its intro marker asynchronously, so frame one is blank.
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();
    // The form is the second step since build 27.
    await tester.tap(find.text('Continue with email'));
    await tester.pumpAndSettle();

    expect(find.text('First name (optional)'), findsNothing);
    expect(find.byType(TextFormField), findsNWidgets(2));
    // And no pitch: a returning runner is not deciding.
    expect(find.text('Every run tracked, and every run kept'), findsNothing);
  });

  group('the intake bar counts the slots this shape actually needs', () {
    test('a block needs six', () {
      const slots = IntakeSlots(shape: PlanShape.block);
      expect(slots.requiredSlots, hasLength(6));
    });

    test('a horizon needs five — there is no date to ask for', () {
      const slots = IntakeSlots(shape: PlanShape.horizon);
      expect(slots.requiredSlots, hasLength(5));
      expect(slots.requiredSlots, isNot(contains('event_date')));
    });

    test('a rhythm needs fewer, and never a time trial', () {
      const slots = IntakeSlots(shape: PlanShape.rhythm);
      expect(slots.requiredSlots, contains('rhythm'));
      expect(
        slots.requiredSlots,
        isNot(contains('time_trial')),
        reason: 'they came to keep turning up, not to be assessed',
      );
      expect(slots.requiredSlots.length, lessThan(6));
    });

    test('a log needs nothing once its intent is known', () {
      const slots = IntakeSlots(shape: PlanShape.log);
      expect(slots.requiredSlots, isEmpty);
    });

    test('filling a slot removes it from missing but not from required', () {
      const empty = IntakeSlots(shape: PlanShape.block);
      final filled = empty.merge(const IntakeSlots(goalDistanceMeters: 42195));

      expect(
        filled.requiredSlots,
        hasLength(6),
        reason: 'the bar keeps its length',
      );
      expect(
        filled.missingRequired.length,
        empty.missingRequired.length - 1,
        reason: 'and the fill moves it along',
      );
    });
  });

  testWidgets('a dev quick sign-in is a sign-in, not a sign-up', (
    tester,
  ) async {
    // "Get started" claims the sign-up intent before the auth call, and only a
    // toggle or a failed sign-up retracted it — so the dev buttons, which sit
    // on the same screen, carried it through to a Home that treated an existing
    // account as brand new.
    //
    // What that flag decides has changed (it no longer pushes the plan flow),
    // so this now watches the thing it still decides: whether the shell takes
    // the new-account road, which skips the restore and the consent question
    // in front of it.
    //
    // The change of mind is a real one now. Sign-up finishes inside the
    // conversation, so walking the intro no longer arrives at the screen the
    // dev buttons live on - it arrives at Home, signed in. What still has to
    // hold is that entering the conversation and leaving it does not leave the
    // claim behind.
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final consent = _RecordingConsent();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: AuthGate(
          introStore: InMemoryIntroStore(),
          auth: FakeAuthRepository(),
          coach: FakeCoachService(),
          consentStore: consent,
          historySource: () async => const [],
          requestPermission: (_) async => true,
          devAccounts: const <DevAccount>[
            DevAccount(
              label: 'Dev',
              email: 'dev@mgkfitness.mgkcodes.com',
              password: 'x',
            ),
          ],
        ),
      ),
    );
    // The gate reads its intro marker asynchronously, so frame one is blank.
    await tester.pump();
    await tester.pumpAndSettle();

    // Start down the sign-up road, which is what claims the intent...
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text('Sounds good'), findsOneWidget);

    // ...then change their mind, back out, and sign in as the dev account.
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dev'));
    await tester.pumpAndSettle();

    expect(
      consent.reads,
      greaterThan(0),
      reason:
          'signing in restores, and a restore asks before it moves anything',
    );
  });
}
