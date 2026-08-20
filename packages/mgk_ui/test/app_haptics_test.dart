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
