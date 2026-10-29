import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/main.dart';
import 'package:mgk_lift/src/core/database/app_database.dart';
import 'package:mgk_lift/src/features/auth/data/phone_training_data.dart';
import 'package:mgk_lift/src/features/coaching/data/supabase_coach.dart';
import 'package:mgk_lift/src/features/coaching/domain/coach.dart';
import 'package:mgk_lift/src/features/home/presentation/lift_shell.dart';
import 'package:mgk_lift/src/features/onboarding/domain/intro_store.dart';
import 'package:mgk_lift/src/features/onboarding/domain/practice_session.dart';
import 'package:mgk_lift/src/features/onboarding/domain/walkthrough_script.dart';
import 'package:mgk_lift/src/features/settings/domain/coach_preference.dart';
import 'package:mgk_lift/src/features/settings/presentation/settings_screen.dart';
import 'package:mgk_lift/src/features/stats/domain/session_history.dart';
import 'package:mgk_lift/src/features/tracking/data/in_memory_session_recorder.dart';
import 'package:mgk_lift/src/features/tracking/domain/rest_alerts.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';
import 'package:mgk_lift/src/features/tracking/domain/workout_library.dart';
import 'package:mgk_lift/src/features/tracking/presentation/active_session_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// The walkthrough over the real app (ADR-0006): one control lit at a time,
/// the tabs changing as it goes, then a practice set in a real session that
/// nothing keeps.
void main() {
  /// An iPhone 14's screen, so the steps are laid out where a phone lays
  /// them out, with Track's button high and the bar at the foot.
  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Finder overlay() => find.byType(WalkthroughOverlay);
  Finder onCard(String text) =>
      find.descendant(of: overlay(), matching: find.text(text));
  Finder said(WalkthroughStep step) => onCard(step.line);

  Future<void> next(WidgetTester tester) async {
    await tester.tap(onCard(kWalkthroughNext));
    await tester.pumpAndSettle();
  }

  Future<void> skip(WidgetTester tester) async {
    await tester.tap(onCard(kWalkthroughSkip));
    await tester.pumpAndSettle();
  }

  /// A new lifter's shell, the walkthrough over it from [from], as the gate
  /// opens it after *Get started*.
  Future<void> shell(
    WidgetTester tester, {
    WalkthroughStep from = WalkthroughStep.track,
    InMemorySessionRecorder? recorder,
    CoachService? coach,
    CoachPreferenceStore? coachPreference,
    RestAlerts? restAlerts,
    SessionHistory? history,
    VoidCallback? onEnded,
  }) async {
    phone(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: LiftShell(
          recorder: recorder ?? InMemorySessionRecorder(),
          library: InMemoryWorkoutLibrary(),
          history: history ?? InMemorySessionHistory(),
          coach: coach,
          coachPreference: coachPreference,
          restAlerts: restAlerts,
          walkthroughOnOpen: true,
          walkthroughFrom: from,
          onWalkthroughEnded: onEnded,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Get started walks through every step over the real app, logs '
      'a practice set, and keeps none of it', (tester) async {
    phone(tester);
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final store = InMemoryIntroStore();
    await tester.pumpWidget(MgkLiftApp(database: db, introStore: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text(kWelcomeStart));
    await tester.pumpAndSettle();

    // Track, its one button lit.
    expect(said(WalkthroughStep.track), findsOneWidget);
    expect(find.text('Start a session'), findsOneWidget);

    // The same button again, as the way to the workouts (TR3).
    await next(tester);
    expect(said(WalkthroughStep.workouts), findsOneWidget);

    // Plan, on its own tab: the free offer is what is behind the veil.
    await next(tester);
    expect(said(WalkthroughStep.plan), findsOneWidget);
    expect(find.text('Train with a coach'), findsOneWidget);
    expect(find.text('Ready when you are'), findsNothing, reason: 'Plan shows');

    // Profile, and its way into Settings.
    await next(tester);
    expect(said(WalkthroughStep.profile), findsOneWidget);
    expect(
      find.textContaining('Log your first session and your totals'),
      findsOneWidget,
    );
    await next(tester);
    expect(said(WalkthroughStep.settings), findsOneWidget);

    // A build with no server has no coach, so no C to point at.
    await next(tester);
    expect(said(WalkthroughStep.coach), findsNothing);
    expect(said(WalkthroughStep.tryASet), findsOneWidget);

    // The practice session: a real session screen, one movement.
    await next(tester);
    expect(find.byType(ActiveSessionScreen), findsOneWidget);
    expect(find.text(kPracticeName), findsWidgets);
    expect(find.text(kPracticeMovement), findsOneWidget);
    expect(said(WalkthroughStep.logASet), findsOneWidget);

    // The lifter's own tap, through the hole, logs the set and moves on.
    await tester.tap(find.byTooltip('Mark done').first);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Mark not done'), findsOneWidget);
    expect(said(WalkthroughStep.rest), findsOneWidget);
    expect(find.text('RESTING'), findsOneWidget, reason: 'the timer started');

    // Unsubscribed: the swap is chosen by hand, so nobody promises to
    // suggest one.
    await next(tester);
    expect(onCard(kSwapLineByHand), findsOneWidget);
    await next(tester);
    expect(said(WalkthroughStep.reorder), findsOneWidget);

    // The end: one button, no Skip.
    await next(tester);
    expect(said(WalkthroughStep.done), findsOneWidget);
    expect(onCard(kWalkthroughSkip), findsNothing);
    await tester.tap(onCard(kWalkthroughStart));
    await tester.pumpAndSettle();

    // Track, with nothing of the practice anywhere.
    expect(overlay(), findsNothing);
    expect(find.byType(ActiveSessionScreen), findsNothing);
    expect(find.text('Ready when you are'), findsOneWidget);
    expect(find.text('Resume session'), findsNothing);
    expect(store.seen, isTrue);
    expect(await PhoneTrainingData(db).isEmpty(), isTrue);
    expect(await db.select(db.workouts).get(), isEmpty);
    expect(await db.select(db.exerciseSets).get(), isEmpty);
  });

  testWidgets('at a larger text size, every step still lands, with nothing '
      'overflowing', (tester) async {
    // The steps name controls rather than places, so a layout pushed about
    // by large text moves the hole with it. 1.3x, the larger of the two
    // sizes the app's own screens are held to here; at 2x the bar's labels
    // and the session's top bar overflow without any walkthrough over them,
    // and the card on its own is held at 2x in mgk_ui.
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await shell(tester, coach: FakeCoach());
    final seen = <WalkthroughStep>[];
    for (
      var i = 0;
      i < 20 && onCard(kWalkthroughStart).evaluate().isEmpty;
      i++
    ) {
      for (final step in WalkthroughStep.values) {
        if (said(step).evaluate().isNotEmpty) seen.add(step);
      }
      await next(tester);
    }
    expect(seen, contains(WalkthroughStep.coach));
    expect(seen, contains(WalkthroughStep.logASet));
    expect(seen, contains(WalkthroughStep.reorder));
    expect(said(WalkthroughStep.done), findsOneWidget);
    await tester.tap(onCard(kWalkthroughStart));
    await tester.pumpAndSettle();
    expect(overlay(), findsNothing);
  });

  testWidgets('Skip from the middle ends it the same way', (tester) async {
    phone(tester);
    final db = AppDatabase.memory();
    addTearDown(db.close);
    final store = InMemoryIntroStore();
    await tester.pumpWidget(MgkLiftApp(database: db, introStore: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text(kWelcomeStart));
    await tester.pumpAndSettle();

    // Into the practice session, a set logged, then Skip.
    while (said(WalkthroughStep.logASet).evaluate().isEmpty) {
      await next(tester);
    }
    await tester.tap(find.byTooltip('Mark done').first);
    await tester.pumpAndSettle();
    await skip(tester);

    expect(overlay(), findsNothing);
    expect(find.byType(ActiveSessionScreen), findsNothing);
    expect(find.text('Ready when you are'), findsOneWidget);
    expect(find.text('Resume session'), findsNothing);
    expect(store.seen, isTrue);
    expect(await PhoneTrainingData(db).isEmpty(), isTrue);
  });

  testWidgets('Skip on another tab lands on Track', (tester) async {
    var ended = 0;
    await shell(tester, onEnded: () => ended++);
    await next(tester);
    await next(tester);
    expect(said(WalkthroughStep.plan), findsOneWidget);

    await skip(tester);
    expect(overlay(), findsNothing);
    expect(find.text('Ready when you are'), findsOneWidget);
    expect(ended, 1);
  });

  testWidgets('back is Skip, over the shell and in the practice', (
    tester,
  ) async {
    var ended = 0;
    await shell(tester, onEnded: () => ended++);
    await next(tester);
    await next(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(overlay(), findsNothing);
    expect(find.byType(LiftShell), findsOneWidget, reason: 'not left the app');
    expect(find.text('Ready when you are'), findsOneWidget);
    expect(ended, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await shell(tester, from: WalkthroughStep.swap, onEnded: () => ended++);
    expect(find.byType(ActiveSessionScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(overlay(), findsNothing);
    expect(find.byType(ActiveSessionScreen), findsNothing);
    expect(find.text('Ready when you are'), findsOneWidget);
    expect(ended, 2);
  });

  testWidgets('nothing under the veil takes a tap but the lit tick', (
    tester,
  ) async {
    await shell(tester);
    await next(tester);
    await next(tester);
    expect(said(WalkthroughStep.plan), findsOneWidget);

    // The bar is under the veil: Track does not open.
    await tester.tap(find.text('Track'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(said(WalkthroughStep.plan), findsOneWidget);
    expect(find.text('Train with a coach'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await shell(tester, from: WalkthroughStep.logASet);
    // The second set's tick is not the one lit.
    await tester.tap(find.byTooltip('Mark done').at(1), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Mark not done'), findsNothing);
    expect(said(WalkthroughStep.logASet), findsOneWidget);

    // Next moves on without the tap, for anybody who would rather not; with
    // no set ticked there is no rest to point at, so that step is passed.
    await next(tester);
    expect(said(WalkthroughStep.rest), findsNothing);
    expect(onCard(kSwapLineByHand), findsOneWidget);
  });

  testWidgets('the practice set reaches nothing real: not the recorder, the '
      'log, or a notification', (tester) async {
    final real = InMemorySessionRecorder();
    final history = InMemorySessionHistory();
    final alerts = FakeRestAlerts(isAllowed: false, wasAsked: false);
    await shell(
      tester,
      from: WalkthroughStep.logASet,
      recorder: real,
      history: history,
      restAlerts: alerts,
    );
    await tester.tap(find.byTooltip('Mark done').first);
    await tester.pumpAndSettle();
    expect(find.text('RESTING'), findsOneWidget);

    // The phone locked mid-rest: a real session would hand the buzz over.
    for (final state in <AppLifecycleState>[
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(alerts.calls, isEmpty, reason: 'nothing scheduled, nothing asked');
    expect(alerts.wasAsked, isFalse);
    expect(
      find.textContaining('Want a buzz when rest is over'),
      findsNothing,
      reason: 'no offer to turn alerts on',
    );

    await skip(tester);
    expect(await real.current(), isNull, reason: 'no session to resume');
    expect(await history.all(), isEmpty);
  });

  testWidgets('a session already open: Resume is lit, and the workouts step '
      'is passed over', (tester) async {
    final open = InMemorySessionRecorder(
      Session(
        id: 'open',
        name: 'Push',
        startedAt: DateTime.now().subtract(const Duration(minutes: 20)),
      ),
    );
    await shell(tester, recorder: open);
    expect(find.text('Resume session'), findsOneWidget);
    expect(said(WalkthroughStep.track), findsOneWidget);

    await next(tester);
    expect(said(WalkthroughStep.workouts), findsNothing);
    expect(said(WalkthroughStep.plan), findsOneWidget);

    await skip(tester);
    expect(await open.current(), isNotNull, reason: 'their session is theirs');
  });

  group('the C', () {
    testWidgets('is pointed at when the coach is on', (tester) async {
      await shell(
        tester,
        from: WalkthroughStep.settings,
        coach: FakeCoach(),
        coachPreference: InMemoryCoachPreference(),
      );
      expect(said(WalkthroughStep.settings), findsOneWidget);
      await next(tester);
      expect(said(WalkthroughStep.coach), findsOneWidget);
    });

    testWidgets('is passed over when the coach is switched off', (
      tester,
    ) async {
      await shell(
        tester,
        from: WalkthroughStep.settings,
        coach: FakeCoach(),
        coachPreference: InMemoryCoachPreference(enabled: false),
      );
      await next(tester);
      expect(said(WalkthroughStep.coach), findsNothing);
      expect(said(WalkthroughStep.tryASet), findsOneWidget);
    });
  });

  testWidgets('Settings › Show me around plays it again from the top', (
    tester,
  ) async {
    phone(tester);
    var ended = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: LiftShell(
          recorder: InMemorySessionRecorder(),
          library: InMemoryWorkoutLibrary(),
          onWalkthroughEnded: () => ended++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(overlay(), findsNothing);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(kShowMeAround), 200);
    await tester.tap(find.text(kShowMeAround));
    await tester.pumpAndSettle();

    expect(find.byType(SettingsScreen), findsNothing);
    expect(said(WalkthroughStep.track), findsOneWidget);
    expect(find.text('Ready when you are'), findsOneWidget, reason: 'on Track');

    await skip(tester);
    expect(overlay(), findsNothing);
    expect(ended, 1);
  });

  testWidgets('a screen reader hears the line and finds Next and Skip, and '
      'nothing behind the veil', (tester) async {
    final semantics = tester.ensureSemantics();
    await shell(tester);

    expect(find.bySemanticsLabel(WalkthroughStep.track.line), findsOneWidget);
    expect(find.bySemanticsLabel(kWalkthroughNext), findsOneWidget);
    expect(find.bySemanticsLabel(kWalkthroughSkip), findsOneWidget);
    // Track's own button is behind the veil, for a double tap as for a
    // finger.
    expect(find.bySemanticsLabel('Start a session'), findsNothing);
    semantics.dispose();
  });
}
