import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/main.dart';
import 'package:mgk_lift/src/core/database/app_database.dart';
import 'package:mgk_lift/src/features/auth/data/fake_auth.dart';
import 'package:mgk_lift/src/features/auth/domain/account.dart';
import 'package:mgk_lift/src/features/auth/presentation/sign_in_screen.dart';
import 'package:mgk_lift/src/features/home/presentation/lift_shell.dart';
import 'package:mgk_lift/src/features/onboarding/domain/intro_script.dart';
import 'package:mgk_lift/src/features/onboarding/domain/intro_store.dart';
import 'package:mgk_lift/src/features/onboarding/presentation/first_run_gate.dart';
import 'package:mgk_lift/src/features/onboarding/presentation/intro_screen.dart';
import 'package:mgk_lift/src/features/onboarding/presentation/welcome_screen.dart';

/// Lift's first open (ADR-0006): Run's pattern, in Lift's words. A welcome,
/// the coach's lines, then the app, once per install, and never for somebody
/// who used Lift before it had one.
void main() {
  /// A phone tall enough that the welcome, the six lines and sign-in's
  /// choices are all on screen at once.
  void tall(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  const signedOutLine = 'Log a session set by set. It works with no signal.';
  const signedInLine =
      'Log a session set by set. It works with no signal and backs up when '
      'you are back.';

  Finder welcome() => find.byType(WelcomeScreen);
  Finder intro() => find.byType(IntroScreen);

  /// The gate on its own, over a stand-in for the app, for the tests about
  /// where it goes rather than what the app does when it gets there.
  Future<void> gate(
    WidgetTester tester,
    IntroStore store, {
    AuthService? auth,
    Future<bool> Function()? hasTraining,
    Widget? app,
    Duration readBudget = const Duration(seconds: 3),
  }) async {
    tall(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: FirstRunGate(
          store: store,
          auth: auth,
          hasTraining: hasTraining,
          readBudget: readBudget,
          app: app ?? const Scaffold(body: Text('the app')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('a new install', () {
    testWidgets('meets the welcome, then the coach, then Track', (
      tester,
    ) async {
      tall(tester);
      final store = InMemoryIntroStore();
      await tester.pumpWidget(MgkLiftApp(introStore: store));

      // The first frame is blank while the store is read, so the welcome can
      // never flash at somebody who has seen it.
      expect(welcome(), findsNothing);
      expect(find.byType(LiftShell), findsNothing);
      await tester.pumpAndSettle();

      expect(welcome(), findsOneWidget);
      expect(find.text(kWelcomeHeadline), findsOneWidget);
      expect(find.text(kWelcomeLine), findsOneWidget);
      // A build with no server has no account to sign in to.
      expect(find.text(kWelcomeHaveAccount), findsNothing);
      expect(find.byType(LiftShell), findsNothing, reason: 'not built yet');

      await tester.tap(find.text(kWelcomeStart));
      await tester.pumpAndSettle();

      expect(intro(), findsOneWidget);
      for (final line in kIntroLines) {
        expect(find.text(line), findsOneWidget, reason: line);
      }
      // It asks nothing: no name, no permission.
      expect(find.byType(TextField), findsNothing);
      expect(store.seen, isFalse, reason: 'not until it is finished');

      await tester.tap(find.text(kIntroStart));
      await tester.pumpAndSettle();

      expect(find.byType(LiftShell), findsOneWidget);
      expect(find.text('Ready when you are'), findsOneWidget);
      // Signed out, so nothing backs up, and Track does not say it will.
      expect(find.text(signedOutLine), findsOneWidget);
      expect(store.seen, isTrue);
      expect(store.marks, 1);
    });

    testWidgets('and the next launch goes straight to Track', (tester) async {
      tall(tester);
      final store = InMemoryIntroStore();
      await tester.pumpWidget(MgkLiftApp(introStore: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kWelcomeStart));
      await tester.pumpAndSettle();
      await tester.tap(find.text(kIntroStart));
      await tester.pumpAndSettle();

      // A relaunch: the app built from nothing, over the same phone.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(MgkLiftApp(introStore: store));
      expect(welcome(), findsNothing, reason: 'not even for a frame');
      await tester.pumpAndSettle();

      expect(welcome(), findsNothing);
      expect(intro(), findsNothing);
      expect(find.text('Ready when you are'), findsOneWidget);
      expect(store.marks, 1, reason: 'recorded once, not on every launch');
    });

    testWidgets('back from the coach returns to the welcome', (tester) async {
      final store = InMemoryIntroStore();
      await gate(tester, store);
      await tester.tap(find.text(kWelcomeStart));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(welcome(), findsOneWidget);

      // And the system's back, which would otherwise find nothing to pop and
      // leave the app from somebody's second screen.
      await tester.tap(find.text(kWelcomeStart));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(welcome(), findsOneWidget);
      expect(store.seen, isFalse);
    });
  });

  group('I already have an account', () {
    testWidgets('goes through sign-in, then the coach, then the app', (
      tester,
    ) async {
      // A lifter arriving from Run: an account, but Lift is new to them.
      final auth = FakeAuth();
      addTearDown(auth.dispose);
      final store = InMemoryIntroStore();
      await gate(
        tester,
        store,
        auth: auth,
        app: LiftShell(auth: auth),
      );

      await tester.tap(find.text(kWelcomeHaveAccount));
      await tester.pumpAndSettle();
      expect(find.byType(SignInScreen), findsOneWidget);

      await tester.tap(find.text('Continue with Apple'));
      await tester.pumpAndSettle();

      expect(find.byType(SignInScreen), findsNothing);
      expect(intro(), findsOneWidget);
      // Signed in now, so there is no welcome to go back to: it would offer
      // to sign them in.
      expect(find.byTooltip('Back'), findsNothing);
      expect(store.seen, isFalse);

      await tester.tap(find.text(kIntroStart));
      await tester.pumpAndSettle();

      expect(find.byType(LiftShell), findsOneWidget);
      // Signed in, so Track can say the session backs up.
      expect(find.text(signedInLine), findsOneWidget);
      expect(store.seen, isTrue);
    });

    testWidgets('backing out of sign-in returns to the welcome', (
      tester,
    ) async {
      final auth = FakeAuth();
      addTearDown(auth.dispose);
      final store = InMemoryIntroStore();
      await gate(tester, store, auth: auth);

      await tester.tap(find.text(kWelcomeHaveAccount));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.byType(SignInScreen), findsNothing);
      expect(welcome(), findsOneWidget);
      expect(intro(), findsNothing);
      expect(store.seen, isFalse);
    });

    testWidgets('an account that lands after backing out still meets the '
        'coach', (tester) async {
      // Apple on Android finishes in the browser and comes back through a
      // link, which can be after the lifter has given up on the screen.
      final auth = FakeAuth(providerOutcome: ProviderOutcome.continuing);
      addTearDown(auth.dispose);
      final store = InMemoryIntroStore();
      await gate(tester, store, auth: auth);

      await tester.tap(find.text(kWelcomeHaveAccount));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue with Apple'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(welcome(), findsOneWidget);

      auth.arrive('you@privaterelay.appleid.com');
      await tester.pumpAndSettle();

      expect(intro(), findsOneWidget);
      expect(find.text('the app'), findsNothing);
    });
  });

  group('somebody who used 2.0.0', () {
    testWidgets('with sessions on the phone never sees it', (tester) async {
      tall(tester);
      final db = AppDatabase.memory();
      addTearDown(db.close);
      await db
          .into(db.workouts)
          .insert(
            WorkoutsCompanion.insert(
              id: 'w1',
              name: 'Push',
              startedAt: DateTime(2026, 9, 1, 18),
              endedAt: Value(DateTime(2026, 9, 1, 19)),
            ),
          );
      final store = InMemoryIntroStore();

      // The real app, so the check main.dart wires is the one tested.
      await tester.pumpWidget(MgkLiftApp(database: db, introStore: store));
      await tester.pumpAndSettle();

      expect(welcome(), findsNothing);
      expect(intro(), findsNothing);
      expect(find.byType(LiftShell), findsOneWidget);
      // Marked without a word, so the check is not made again.
      expect(store.seen, isTrue);
    });

    testWidgets('with a session restored at launch never sees it', (
      tester,
    ) async {
      final auth = FakeAuth(
        account: const Account(id: 'u', email: 'a@b.com'),
      );
      addTearDown(auth.dispose);
      final store = InMemoryIntroStore();
      await gate(tester, store, auth: auth, hasTraining: () async => false);

      expect(welcome(), findsNothing);
      expect(find.text('the app'), findsOneWidget);
      expect(store.seen, isTrue);
    });

    testWidgets('restored a moment late, still never sees it', (tester) async {
      // Supabase can restore a session a beat after launch has asked. On the
      // welcome, an account nobody asked for is that session.
      final auth = FakeAuth();
      addTearDown(auth.dispose);
      final store = InMemoryIntroStore();
      await gate(tester, store, auth: auth);
      expect(welcome(), findsOneWidget);

      auth.arrive('a@b.com');
      await tester.pumpAndSettle();

      expect(welcome(), findsNothing);
      expect(intro(), findsNothing);
      expect(find.text('the app'), findsOneWidget);
      expect(store.seen, isTrue);
    });
  });

  group('a store that cannot answer', () {
    testWidgets('one that throws opens the app, not the welcome', (
      tester,
    ) async {
      final store = _BrokenStore();
      await gate(tester, store);

      expect(welcome(), findsNothing);
      expect(find.text('the app'), findsOneWidget);
    });

    testWidgets('and keeps opening it, launch after launch', (tester) async {
      // The loop this must never be: a welcome on every launch because the
      // answer could not be read or kept.
      for (var launch = 0; launch < 3; launch++) {
        await tester.pumpWidget(const SizedBox.shrink());
        await gate(tester, _BrokenStore());
        expect(welcome(), findsNothing, reason: 'launch $launch');
        expect(find.text('the app'), findsOneWidget);
      }
    });

    testWidgets('one that never answers opens the app after a wait', (
      tester,
    ) async {
      tall(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: FirstRunGate(
            store: _SilentStore(),
            readBudget: const Duration(seconds: 2),
            app: const Text('the app'),
          ),
        ),
      );
      expect(find.text('the app'), findsNothing);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(welcome(), findsNothing);
      expect(find.text('the app'), findsOneWidget);
    });

    testWidgets('a phone whose training cannot be read counts as used', (
      tester,
    ) async {
      final store = InMemoryIntroStore();
      await gate(
        tester,
        store,
        hasTraining: () async => throw StateError('no database'),
      );

      expect(welcome(), findsNothing);
      expect(find.text('the app'), findsOneWidget);
    });
  });
}

/// A store whose plugin is gone: every read and write throws, which the
/// interface forbids and the gate must survive anyway.
class _BrokenStore implements IntroStore {
  @override
  Future<bool> hasSeen() async => throw StateError('no plugin');

  @override
  Future<void> markSeen() async => throw StateError('no plugin');
}

/// A store whose read never comes back.
class _SilentStore implements IntroStore {
  @override
  Future<bool> hasSeen() => Completer<bool>().future;

  @override
  Future<void> markSeen() async {}
}
