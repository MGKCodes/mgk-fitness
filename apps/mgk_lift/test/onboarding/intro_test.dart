import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/onboarding/data/local_intro_store.dart';
import 'package:mgk_lift/src/features/onboarding/domain/intro_script.dart';
import 'package:mgk_lift/src/features/onboarding/presentation/intro_screen.dart';
import 'package:mgk_lift/src/features/onboarding/presentation/welcome_screen.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The words of Lift's first open, the screens that say them, and where the
/// answer is kept (ADR-0006).
void main() {
  group('what the coach says', () {
    test('the six lines, in the order the tabs sit on the bar', () {
      expect(kIntroLines, <String>[
        "Hey. I'm your coach.",
        'Track is where you log a session, set by set. It works with no '
            'signal.',
        "Plan is a week I build around your days, your kit and anything "
            "you're working around.",
        'Profile keeps your history, your bests and your progress photos.',
        'Tap the C at the bottom to ask me anything about your training. '
            'Coaching and plans are a subscription. Logging never is.',
        'Your sessions stay on this phone. Sign in whenever you want them '
            'backed up.',
      ]);
    });

    test('no em dashes, in the coach or on the welcome', () {
      // The coach's server tells the model never to use one; a scripted line
      // that does is a seam in the voice.
      for (final words in <String>[
        ...kIntroLines,
        kWelcomeHeadline,
        kWelcomeLine,
        kWelcomeStart,
        kWelcomeHaveAccount,
        kIntroStart,
      ]) {
        expect(words, isNot(contains('—')), reason: words);
      }
    });

    test('no price: the store says what it costs, in every currency', () {
      for (final line in kIntroLines) {
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

  group('the coach, before the app', () {
    testWidgets('the button waits for the last line', (tester) async {
      // Painted under the first line, it invites a tap that skips the five
      // after it.
      var finished = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: IntroScreen(onFinished: () => finished++),
        ),
      );
      await tester.pump();
      expect(find.text(kIntroStart), findsNothing);
      expect(find.text(kIntroLines.last), findsNothing);

      await tester.pumpAndSettle();
      expect(find.text(kIntroLines.last), findsOneWidget);
      expect(find.text(kIntroStart), findsOneWidget);

      await tester.tap(find.text(kIntroStart));
      await tester.tap(find.text(kIntroStart));
      expect(finished, 1, reason: 'a second tap does not finish twice');
    });

    testWidgets('with Reduce Motion on, everything is there at once', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: IntroScreen(onFinished: () {}),
            ),
          ),
        ),
      );
      await tester.pump();
      for (final line in kIntroLines) {
        expect(find.text(line), findsOneWidget, reason: line);
      }
      expect(find.text(kIntroStart), findsOneWidget);
    });

    testWidgets('each line is the coach speaking, with its C', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: IntroScreen(onFinished: () {}),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ScriptedLine), findsNWidgets(kIntroLines.length));
      expect(find.byType(CoachAvatar), findsNWidgets(kIntroLines.length));
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
