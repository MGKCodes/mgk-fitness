import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// Records every haptic the framework asks the platform for.
///
/// `HapticFeedback` goes out over `SystemChannels.platform` as a
/// `HapticFeedback.vibrate` call whose argument names the flavour, so a mock
/// handler is enough to assert both *that* something fired and *which* one —
/// which matters, because the whole point of naming these by occasion is that
/// the wrong occasion is a bug you can otherwise only feel on a real phone.
List<String> recordHaptics(WidgetTester tester) {
  final List<String> fired = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (MethodCall call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        fired.add((call.arguments as String?) ?? 'vibrate');
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return fired;
}

void main() {
  group('the vocabulary maps occasions onto flavours', () {
    testWidgets('a tap and a selection are the lightest', (
      WidgetTester tester,
    ) async {
      final List<String> fired = recordHaptics(tester);

      await AppHaptics.tap();
      await AppHaptics.selection();

      expect(fired, <String>[
        'HapticFeedbackType.selectionClick',
        'HapticFeedbackType.selectionClick',
      ]);
    });

    testWidgets('committing and a milestone are heavier than a touch', (
      WidgetTester tester,
    ) async {
      final List<String> fired = recordHaptics(tester);

      await AppHaptics.commit();
      await AppHaptics.milestone();

      expect(fired, <String>[
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.mediumImpact',
      ]);
    });

    testWidgets('a problem is the heaviest, and the rarest', (
      WidgetTester tester,
    ) async {
      final List<String> fired = recordHaptics(tester);

      await AppHaptics.problem();

      expect(fired, <String>['HapticFeedbackType.heavyImpact']);
    });
  });

  group('the quiet controls', () {
    testWidgets('a text button ticks and still fires', (
      WidgetTester tester,
    ) async {
      final List<String> fired = recordHaptics(tester);
      int taps = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: AppTextButton(label: 'Never mind', onPressed: () => taps++),
          ),
        ),
      );

      await tester.tap(find.text('Never mind'));
      await tester.pump();

      expect(fired, <String>['HapticFeedbackType.selectionClick']);
      expect(taps, 1);
      await tester.pumpAndSettle();
    });

    testWidgets('an icon button ticks, and carries its accessible name', (
      WidgetTester tester,
    ) async {
      final List<String> fired = recordHaptics(tester);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: AppIconButton(
              icon: Icons.close,
              tooltip: 'Close',
              onPressed: () {},
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(fired, <String>['HapticFeedbackType.selectionClick']);
      // The tooltip is required on this widget precisely so this cannot be
      // forgotten: an icon alone is the one control that cannot explain itself.
      expect(find.byTooltip('Close'), findsOneWidget);
      await tester.pumpAndSettle();
    });

    testWidgets('neither pretends to have felt you when it is disabled', (
      WidgetTester tester,
    ) async {
      final List<String> fired = recordHaptics(tester);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: <Widget>[
                AppTextButton(label: 'Busy', onPressed: null, busy: true),
                AppIconButton(
                  icon: Icons.close,
                  tooltip: 'Close',
                  onPressed: null,
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('Busy'), warnIfMissed: false);
      await tester.tap(find.byIcon(Icons.close), warnIfMissed: false);
      await tester.pump();

      expect(fired, isEmpty);
      await tester.pumpAndSettle();
    });
  });

  group('AppCard', () {
    testWidgets('a tappable card ticks; a plain one is not a control', (
      WidgetTester tester,
    ) async {
      final List<String> fired = recordHaptics(tester);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: const Scaffold(
            body: AppCard(child: SizedBox(width: 200, height: 80)),
          ),
        ),
      );

      await tester.tap(find.byType(AppCard));
      await tester.pump();
      expect(
        fired,
        isEmpty,
        reason: 'a card that does nothing must not pretend to be pressable',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: AppCard(
              onTap: () {},
              child: const SizedBox(width: 200, height: 80),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AppCard));
      await tester.pump();
      expect(fired, <String>['HapticFeedbackType.selectionClick']);

      await tester.pumpAndSettle();
    });

    testWidgets('and the card still owns its tap', (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: AppCard(
              onTap: () => taps++,
              child: const SizedBox(width: 200, height: 80),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AppCard));
      await tester.pump();

      // PressScale only listens, so wrapping the card must not have eaten the
      // gesture on its way through.
      expect(taps, 1);
      await tester.pumpAndSettle();
    });
  });

  group('PressScale', () {
    testWidgets('ticks on the way down, before the tap does anything', (
      WidgetTester tester,
    ) async {
      final List<String> fired = recordHaptics(tester);
      final List<String> order = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: PressScale(
              onTap: () => order.add('tap'),
              child: const ColoredBox(
                color: Colors.black,
                child: SizedBox(width: 120, height: 48),
              ),
            ),
          ),
        ),
      );

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(find.byType(PressScale)),
      );
      await tester.pump();

      // Felt before the action, which is the whole point of the widget.
      expect(fired, <String>['HapticFeedbackType.selectionClick']);
      expect(order, isEmpty);

      await gesture.up();
      await tester.pump();
      expect(order, <String>['tap']);

      await tester.pumpAndSettle();
    });

    testWidgets('stays silent where a press is not really a press', (
      WidgetTester tester,
    ) async {
      final List<String> fired = recordHaptics(tester);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: PressScale(
              haptic: false,
              onTap: () {},
              child: const ColoredBox(
                color: Colors.black,
                child: SizedBox(width: 120, height: 48),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(PressScale));
      await tester.pump();

      expect(fired, isEmpty);
      await tester.pumpAndSettle();
    });

    testWidgets('a disabled control does not pretend to have felt you', (
      WidgetTester tester,
    ) async {
      final List<String> fired = recordHaptics(tester);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: PressScale(
              enabled: false,
              onTap: () {},
              child: const ColoredBox(
                color: Colors.black,
                child: SizedBox(width: 120, height: 48),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(PressScale));
      await tester.pump();

      expect(fired, isEmpty);
      await tester.pumpAndSettle();
    });
  });
}
