import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/preview/fake_coach_service.dart';
import 'package:mgk_run/src/core/config/app_config.dart';
import 'package:mgk_run/src/features/auth/presentation/auth_gate.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/home/presentation/home_tab.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_permission.dart';
import 'package:mgk_run/src/features/onboarding/domain/intro_store.dart';
import 'package:mgk_run/src/features/onboarding/domain/walkthrough_script.dart';
import 'package:mgk_run/src/features/recording/domain/run_recorder.dart';
import 'package:mgk_run/src/features/settings/presentation/settings_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// The tour over the real app (ADR-0050): after the intro on *Get started*,
/// one control lit at a time, the tabs changing as it goes, ending on the
/// button that starts a run and starting nothing.
void main() {
  /// An iPhone 14's screen, so the steps are laid out where a phone lays
  /// them out.
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Finder overlay() => find.byType(WalkthroughOverlay);
  Finder onCard(String text) =>
      find.descendant(of: overlay(), matching: find.text(text));
  Finder said(TourStep step) => onCard(step.line);

  /// What the step on screen lights, as the overlay was handed it.
  Object? lit(WidgetTester tester) =>
      tester.widget<WalkthroughOverlay>(overlay()).frame.value?.target;

  /// Pumped rather than settled where the coach's mark may be playing its
  /// line, as the other shell tests are; settled where the tour is up, since
  /// the reveal is held at rest under it.
  Future<void> frames(WidgetTester tester, [int count = 14]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  Future<void> next(WidgetTester tester) async {
    await tester.tap(onCard(kTourNext));
    await tester.pumpAndSettle();
  }

  /// Welcome → *Get started* → the intro, every permission granted.
  Future<void> throughIntro(WidgetTester tester) async {
    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sounds good'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Sam');
    await tester.tap(find.byTooltip('Continue'));
    await tester.pumpAndSettle();
    for (final permission in introPermissionsFor(defaultTargetPlatform)) {
      await tester.tap(find.text(permission.cta));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }
  }

  Future<void> gate(
    WidgetTester tester, {
    IntroStore? introStore,
    FakeAuthRepository? auth,
    FakeCoachService? coach,
    List<DevAccount>? devAccounts,
    RunRecorder Function()? recorderFactory,
  }) async {
    phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: AuthGate(
          introStore: introStore ?? InMemoryIntroStore(),
          auth: auth ?? FakeAuthRepository(),
          coach: coach,
          devAccounts: devAccounts,
          historySource: () async => const [],
          recorderFactory: recorderFactory,
          requestPermission: (_) async => true,
        ),
      ),
    );
    // The gate reads its intro marker asynchronously, so frame one is blank.
    await tester.pump();
    await tester.pumpAndSettle();
  }

  /// A shell with no tour on open, as an install that has had its intro sees.
  Future<void> shell(
    WidgetTester tester, {
    FakeAuthRepository? auth,
    bool walkthroughOnOpen = false,
    TourStep from = TourStep.today,
    VoidCallback? onEnded,
  }) async {
    phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          auth: auth ?? FakeAuthRepository(),
          historySource: () async => const [],
          walkthroughOnOpen: walkthroughOnOpen,
          walkthroughFrom: from,
          onWalkthroughEnded: onEnded,
        ),
      ),
    );
    await frames(tester);
  }

  testWidgets('Get started: after the intro, every step over the real app, '
      'each lighting its own control, ending on start and starting nothing', (
    tester,
  ) async {
    var recorders = 0;
    await gate(
      tester,
      coach: FakeCoachService(),
      recorderFactory: () {
        recorders++;
        throw StateError('the tour must not start a run');
      },
    );
    await throughIntro(tester);

    // Home, its Today card lit, with the tab bar behind the veil.
    expect(said(TourStep.today), findsOneWidget);
    expect(lit(tester), TourSpot.today);
    expect(find.byType(HomeTab), findsOneWidget);

    await next(tester);
    expect(said(TourStep.week), findsOneWidget);
    expect(lit(tester), TourSpot.week);

    // Plan, on its own tab.
    await next(tester);
    expect(said(TourStep.plan), findsOneWidget);
    expect(lit(tester), TourSpot.planTab);

    // Profile, and its way into Settings.
    await next(tester);
    expect(said(TourStep.profile), findsOneWidget);
    expect(lit(tester), TourSpot.profileTab);
    await next(tester);
    expect(said(TourStep.settings), findsOneWidget, reason: 'signed out');
    expect(lit(tester), TourSpot.settings);

    // The coach, there because this build has one.
    await next(tester);
    expect(said(TourStep.coach), findsOneWidget);
    expect(lit(tester), TourSpot.coach);

    // The way out: the start button lit, one button, no Skip.
    await next(tester);
    expect(said(TourStep.start), findsOneWidget);
    expect(lit(tester), TourSpot.start);
    expect(onCard(kTourDone), findsOneWidget);
    expect(onCard(kTourSkip), findsNothing);

    // The lit button cannot be pressed through the veil.
    await tester.tap(find.text('Record a run'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(said(TourStep.start), findsOneWidget);

    await tester.tap(onCard(kTourDone));
    await tester.pumpAndSettle();
    expect(overlay(), findsNothing);
    expect(find.text('Record a run'), findsOneWidget, reason: 'on Home');
    expect(recorders, 0, reason: 'no run, no GPS, nothing on the lock screen');
  });

  testWidgets('a build with no coach passes over the C', (tester) async {
    await gate(tester);
    await throughIntro(tester);
    for (var i = 0; i < 4; i++) {
      await next(tester);
    }
    expect(said(TourStep.settings), findsOneWidget);
    await next(tester);
    expect(said(TourStep.coach), findsNothing);
    expect(said(TourStep.start), findsOneWidget);
  });

  testWidgets('Skip ends it from the middle, on Home', (tester) async {
    await gate(tester, coach: FakeCoachService());
    await throughIntro(tester);
    await next(tester);
    await next(tester);
    expect(said(TourStep.plan), findsOneWidget);

    await tester.tap(onCard(kTourSkip));
    await tester.pumpAndSettle();
    expect(overlay(), findsNothing);
    expect(find.byType(HomeTab), findsOneWidget, reason: 'Home, not Plan');
  });

  testWidgets('back is Skip, and does not leave the app', (tester) async {
    await gate(tester);
    await throughIntro(tester);
    expect(said(TourStep.today), findsOneWidget);

    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(handled, isTrue);
    expect(overlay(), findsNothing);
    expect(find.byType(HomeTab), findsOneWidget);
  });

  testWidgets('"I already have an account" goes past it', (tester) async {
    await gate(
      tester,
      devAccounts: const <DevAccount>[
        DevAccount(
          label: 'Runner A',
          email: 'a@mgkfitness.mgkcodes.com',
          password: 'password',
        ),
      ],
    );
    await tester.tap(find.text('I already have an account'));
    await tester.pumpAndSettle();
    final quickSignIn = find.widgetWithText(OutlinedButton, 'Runner A');
    await tester.ensureVisible(quickSignIn);
    await tester.pumpAndSettle();
    await tester.tap(quickSignIn);
    await frames(tester);

    expect(find.text('Record a run'), findsOneWidget);
    expect(overlay(), findsNothing);
  });

  testWidgets('an account that has never met this coach has the intro, and '
      'no tour after it', (tester) async {
    await gate(
      tester,
      // No name on the account, so the intro asks for one.
      auth: FakeAuthRepository(signedIn: true, metCoach: false),
    );
    await tester.tap(find.text('Sounds good'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Sam');
    await tester.tap(find.byTooltip('Continue'));
    await tester.pumpAndSettle();
    for (final permission in introPermissionsFor(defaultTargetPlatform)) {
      await tester.tap(find.text(permission.cta));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }
    await frames(tester);

    expect(find.byType(HomeTab), findsOneWidget);
    expect(overlay(), findsNothing);
  });

  testWidgets('an install that has had its intro is not toured on opening', (
    tester,
  ) async {
    // Everybody updating from 1.0.x: the marker says the intro happened.
    await gate(tester, introStore: InMemoryIntroStore(done: true));
    await frames(tester);
    expect(find.byType(HomeTab), findsOneWidget);
    expect(overlay(), findsNothing);
  });

  testWidgets('Settings › Show me around plays it again from the top', (
    tester,
  ) async {
    await shell(tester);
    expect(overlay(), findsNothing);

    await tester.tap(find.text('Profile'));
    await frames(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    final row = find.text(kShowMeAround);
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsNothing, reason: 'closed');
    expect(said(TourStep.today), findsOneWidget);
    expect(lit(tester), TourSpot.today);
  });

  testWidgets('a signed-in runner is told what Settings does for them', (
    tester,
  ) async {
    var ended = 0;
    await shell(
      tester,
      auth: FakeAuthRepository(signedIn: true, email: 'sam@example.com'),
      walkthroughOnOpen: true,
      from: TourStep.settings,
      onEnded: () => ended++,
    );
    await tester.pumpAndSettle();
    expect(onCard(kSettingsLineSignedIn), findsOneWidget);
    expect(said(TourStep.settings), findsNothing);

    await tester.tap(onCard(kTourSkip));
    await tester.pumpAndSettle();
    expect(ended, 1);
  });

  group('the lines', () {
    final lines = <String>[
      for (final step in TourStep.values) step.line,
      kSettingsLineSignedIn,
    ];

    test('keep the coach\'s voice: no em dashes', () {
      for (final line in lines) {
        expect(line, isNot(contains('—')), reason: line);
        expect(line, isNot(contains('–')), reason: line);
      }
    });

    test('name no price', () {
      for (final line in lines) {
        expect(line, isNot(matches(RegExp(r'[£$€]|\d'))), reason: line);
        expect(line.toLowerCase(), isNot(contains('free')), reason: line);
      }
    });

    test('the last step is the start button', () {
      expect(TourStep.values.last, TourStep.start);
      expect(TourStep.start.spot, TourSpot.start);
    });
  });
}
