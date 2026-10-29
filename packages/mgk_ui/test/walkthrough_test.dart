import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// The walkthrough's pieces: controls marked by id and found where they are
/// drawn, and the veil that lights one and takes every other tap.
void main() {
  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(body: child),
  );

  group('a target', () {
    Widget at(WalkthroughTargets targets, double top, {Object? id = 'a'}) =>
        host(
          WalkthroughScope(
            targets: targets,
            child: Stack(
              children: <Widget>[
                Positioned(
                  top: top,
                  left: 40,
                  child: WalkthroughTarget(
                    id: id,
                    child: const SizedBox(
                      width: 80,
                      height: 40,
                      key: ValueKey<String>('box'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

    testWidgets('is found where it is drawn, and followed when it moves', (
      tester,
    ) async {
      final targets = WalkthroughTargets();
      await tester.pumpWidget(at(targets, 100));
      expect(
        targets.rectOf('a'),
        tester.getRect(find.byKey(const ValueKey<String>('box'))),
      );

      await tester.pumpWidget(at(targets, 300));
      expect(targets.rectOf('a')!.top, 300);
      expect(targets.rectOf('b'), isNull);
    });

    testWidgets('with no id, or gone, is nothing', (tester) async {
      final targets = WalkthroughTargets();
      await tester.pumpWidget(at(targets, 100, id: null));
      expect(targets.rectOf('a'), isNull);

      await tester.pumpWidget(at(targets, 100));
      expect(targets.rectOf('a'), isNotNull);
      await tester.pumpWidget(host(const SizedBox.shrink()));
      expect(targets.rectOf('a'), isNull);
    });

    testWidgets('kept alive in a hidden tab is not showing', (tester) async {
      // A tab behind the one on screen still has a size and a place; a hole
      // cut there would point at nothing.
      final targets = WalkthroughTargets();
      await tester.pumpWidget(
        host(
          WalkthroughScope(
            targets: targets,
            child: Column(
              children: <Widget>[
                const Offstage(
                  child: WalkthroughTarget(
                    id: 'tab',
                    child: SizedBox(width: 50, height: 50),
                  ),
                ),
                WalkthroughTarget(
                  id: 'tab',
                  child: Container(
                    key: const ValueKey<String>('shown'),
                    width: 60,
                    height: 60,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(
        targets.rectOf('tab'),
        tester.getRect(find.byKey(const ValueKey<String>('shown'))),
      );
    });

    testWidgets('outside a scope registers nothing and draws its child', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const WalkthroughTarget(id: 'a', child: Text('as it was'))),
      );
      expect(find.text('as it was'), findsOneWidget);
    });
  });

  group('the veil', () {
    late WalkthroughTargets targets;
    late ValueNotifier<WalkthroughFrame?> frame;
    late int top;
    late int bottom;
    late int nexts;
    late int skips;

    setUp(() {
      targets = WalkthroughTargets();
      frame = ValueNotifier<WalkthroughFrame?>(null);
      top = bottom = nexts = skips = 0;
    });

    /// Two buttons, one near the top of the screen and one near the foot,
    /// under the veil.
    Future<void> pump(WidgetTester tester, WalkthroughFrame? step) async {
      frame.value = step;
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        host(
          WalkthroughScope(
            targets: targets,
            child: Stack(
              children: <Widget>[
                Positioned(
                  top: 120,
                  left: 40,
                  child: WalkthroughTarget(
                    id: 'top',
                    child: AppFilledButton(
                      label: 'Top',
                      onPressed: () => top++,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 120,
                  left: 40,
                  child: WalkthroughTarget(
                    id: 'bottom',
                    child: AppFilledButton(
                      label: 'Bottom',
                      onPressed: () => bottom++,
                    ),
                  ),
                ),
                Positioned.fill(
                  child: WalkthroughOverlay(
                    targets: targets,
                    frame: frame,
                    onNext: () => nexts++,
                    onSkip: () => skips++,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder card() => find.byType(CoachAvatar);

    testWidgets('takes every tap, the lit control included', (tester) async {
      await pump(
        tester,
        const WalkthroughFrame(line: 'This is the top.', target: 'top'),
      );
      await tester.tap(find.text('Top'), warnIfMissed: false);
      await tester.tap(find.text('Bottom'), warnIfMissed: false);
      expect(top, 0);
      expect(bottom, 0);
    });

    testWidgets('on an interactive step lets the lit control, and only it, '
        'take a tap', (tester) async {
      await pump(
        tester,
        const WalkthroughFrame(
          line: 'Tap the top.',
          target: 'top',
          interactive: true,
        ),
      );
      await tester.tap(find.text('Top'));
      await tester.tap(find.text('Bottom'), warnIfMissed: false);
      expect(top, 1);
      expect(bottom, 0);
    });

    testWidgets('the card is the coach speaking: its C beside the line', (
      tester,
    ) async {
      await pump(tester, const WalkthroughFrame(line: "Let's try a set."));
      expect(find.text("Let's try a set."), findsOneWidget);
      expect(card(), findsOneWidget);
      expect(
        find.descendant(of: card(), matching: find.byType(CoachLetter)),
        findsOneWidget,
      );
      final mark = tester.getRect(card());
      final words = tester.getRect(find.text("Let's try a set."));
      expect(mark.right, lessThanOrEqualTo(words.left));
    });

    testWidgets('sits under a control near the top, over one near the foot', (
      tester,
    ) async {
      await pump(
        tester,
        const WalkthroughFrame(line: 'The top.', target: 'top'),
      );
      expect(
        tester.getRect(card()).top,
        greaterThan(tester.getRect(find.text('Top')).bottom),
      );

      frame.value = const WalkthroughFrame(line: 'The foot.', target: 'bottom');
      await tester.pumpAndSettle();
      expect(
        tester.getRect(card()).bottom,
        lessThan(tester.getRect(find.text('Bottom')).top),
      );
    });

    testWidgets('Next and Skip are the card\'s; a last step has no Skip', (
      tester,
    ) async {
      await pump(tester, const WalkthroughFrame(line: 'A step.'));
      await tester.tap(find.text('Next'));
      await tester.tap(find.text('Skip'));
      expect(nexts, 1);
      expect(skips, 1);

      frame.value = const WalkthroughFrame(
        line: 'The end.',
        next: 'Start training',
        skip: null,
      );
      await tester.pumpAndSettle();
      expect(find.text('Skip'), findsNothing);
      await tester.tap(find.text('Start training'));
      expect(nexts, 2);
    });

    testWidgets('at twice the text size on a small phone, the card holds', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pump(
        tester,
        const WalkthroughFrame(
          line:
              'And this is me. Tap the C any time to ask about your training. '
              'Coaching is a subscription. Logging never is.',
          target: 'bottom',
        ),
      );
      tester.view.physicalSize = const Size(960, 1704);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // Both buttons still there to be pressed.
      await tester.tap(find.text('Next'));
      await tester.tap(find.text('Skip'));
      expect(nexts, 1);
      expect(skips, 1);
    });

    testWidgets('between two steps: no card, and still no tap through', (
      tester,
    ) async {
      await pump(tester, null);
      expect(card(), findsNothing);
      await tester.tap(find.text('Top'), warnIfMissed: false);
      expect(top, 0);
    });

    testWidgets('a screen reader hears the line and its two buttons, and '
        'nothing under the veil', (tester) async {
      final semantics = tester.ensureSemantics();
      await pump(
        tester,
        const WalkthroughFrame(line: 'This is the top.', target: 'top'),
      );
      expect(find.bySemanticsLabel('This is the top.'), findsOneWidget);
      expect(find.bySemanticsLabel('Next'), findsOneWidget);
      expect(find.bySemanticsLabel('Skip'), findsOneWidget);
      expect(find.bySemanticsLabel('Bottom'), findsNothing);
      semantics.dispose();
    });
  });
}
