import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/onboarding/data/local_intro_store.dart';
import 'package:mgk_lift/src/features/onboarding/domain/walkthrough_script.dart';
import 'package:mgk_lift/src/features/onboarding/presentation/welcome_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The words of Lift's first open, the welcome that says the first of them,
/// and where the answer is kept (ADR-0006). The walkthrough itself is
/// `walkthrough_test.dart`.
void main() {
  group('what the coach says', () {
    test('a step for each place, in the order the walkthrough goes', () {
      expect(WalkthroughStep.values, <WalkthroughStep>[
        WalkthroughStep.track,
        WalkthroughStep.workouts,
        WalkthroughStep.plan,
        WalkthroughStep.profile,
        WalkthroughStep.settings,
        WalkthroughStep.coach,
        WalkthroughStep.tryASet,
        WalkthroughStep.logASet,
        WalkthroughStep.rest,
        WalkthroughStep.swap,
        WalkthroughStep.reorder,
        WalkthroughStep.done,
      ]);
      // The owner's words, as given, where nothing on screen contradicts
      // them.
      expect(
        WalkthroughStep.track.line,
        'Track is where you log. Start a session here and log it set by set. '
        'It works with no signal.',
      );
      expect(
        WalkthroughStep.coach.line,
        'And this is me. Tap the C any time to ask about your training. '
        'Coaching is a subscription. Logging never is.',
      );
      expect(WalkthroughStep.tryASet.line, "Let's try a set.");
      expect(
        WalkthroughStep.done.line,
        "That's it. Your real sessions start from Track.",
      );
    });

    test('only the tick waits for the lifter', () {
      expect(
        <WalkthroughStep>[
          for (final step in WalkthroughStep.values)
            if (step.interactive) step,
        ],
        <WalkthroughStep>[WalkthroughStep.logASet],
      );
    });

    test('what is said is true for the lifter it is said to', () {
      // Signed in, the sessions do not stay on the phone.
      expect(
        WalkthroughStep.settings.lineFor(signedIn: false, coached: false),
        contains('stay on this phone'),
      );
      expect(
        WalkthroughStep.settings.lineFor(signedIn: true, coached: false),
        kSettingsLineSignedIn,
      );
      // Unsubscribed, nobody suggests the swap: they choose it.
      expect(
        WalkthroughStep.swap.lineFor(signedIn: false, coached: false),
        kSwapLineByHand,
      );
      expect(
        WalkthroughStep.swap.lineFor(signedIn: true, coached: true),
        contains("I'll suggest"),
      );
    });

    test('no em dashes, in the coach or on the welcome', () {
      // The coach's server tells the model never to use one; a scripted line
      // that does is a seam in the voice.
      for (final words in <String>[
        for (final step in WalkthroughStep.values) step.line,
        kSettingsLineSignedIn,
        kSwapLineByHand,
        kWelcomeHeadline,
        kWelcomeLine,
        kWelcomeStart,
        kWelcomeHaveAccount,
        kWalkthroughStart,
        kShowMeAround,
      ]) {
        expect(words, isNot(contains('—')), reason: words);
      }
    });

    test('no price: the store says what it costs, in every currency', () {
      for (final line in <String>[
        for (final step in WalkthroughStep.values) step.line,
        kSettingsLineSignedIn,
        kSwapLineByHand,
      ]) {
        expect(line, isNot(matches(RegExp(r'[£$€]|\d'))), reason: line);
      }
    });
  });

  group('the welcome', () {
    Future<void> pump(WidgetTester tester, {VoidCallback? onHaveAccount}) =>
        tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark,
            home: WelcomeScreen(
              onGetStarted: () {},
              onHaveAccount: onHaveAccount,
            ),
          ),
        );

    testWidgets("Lift's name, the promise, and the two ways in", (
      tester,
    ) async {
      var signIns = 0;
      await pump(tester, onHaveAccount: () => signIns++);
      await tester.pumpAndSettle();

      expect(find.text('LIFT'), findsOneWidget);
      expect(find.text('Every session,\nlogged.'), findsOneWidget);
      expect(
        find.text(
          'Set by set, with no signal,\nand a coach when you want one.',
        ),
        findsOneWidget,
      );
      expect(find.text('Get started'), findsOneWidget);

      await tester.tap(find.text('I already have an account'));
      expect(signIns, 1);
    });

    testWidgets('no account to sign in to, no button that offers one', (
      tester,
    ) async {
      await pump(tester);
      await tester.pumpAndSettle();
      expect(find.text('I already have an account'), findsNothing);
    });
  });

  group('where the answer is kept', () {
    test('a phone that has never been asked has not seen it', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      expect(await LocalIntroStore(prefs: prefs).hasSeen(), isFalse);
    });

    test('seen survives a relaunch', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();

      await LocalIntroStore(prefs: prefs).markSeen();
      // A second instance, as a relaunch would build.
      expect(await LocalIntroStore(prefs: prefs).hasSeen(), isTrue);
      expect(prefs.getBool('intro.seen'), isTrue);
    });

    test('a value it cannot read counts as seen, never as a loop', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'intro.seen': 'yes',
      });
      final prefs = await SharedPreferences.getInstance();
      expect(await LocalIntroStore(prefs: prefs).hasSeen(), isTrue);
    });

    test('resolves the plugin per call rather than at construction', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final store = LocalIntroStore();
      expect(await store.hasSeen(), isFalse);
      await store.markSeen();
      expect(await store.hasSeen(), isTrue);
    });
  });
}
