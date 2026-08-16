import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  bool reduceMotion = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  group('Pulse', () {
    testWidgets('settles when inactive, so pumpAndSettle can return', (
      tester,
    ) async {
      // The bug this pins: the in-run status pill hand-rolled a pulse that
      // repeated forever regardless of state, which burns a ticker under a
      // paused pill and hangs any pumpAndSettle that reaches the screen.
      await _pump(tester, const Pulse(active: false, child: Text('paused')));
      await tester.pumpAndSettle();

      expect(find.text('paused'), findsOneWidget);
    });

    testWidgets('stops animating when it goes inactive mid-life', (
      tester,
    ) async {
      await _pump(tester, const Pulse(child: Text('live')));
      await tester.pump(const Duration(milliseconds: 200));

      await _pump(tester, const Pulse(active: false, child: Text('live')));
      await tester.pumpAndSettle();

      expect(find.text('live'), findsOneWidget);
    });

    testWidgets('does not animate under reduced motion', (tester) async {
      // A thing that never stops flashing is the worst version of a motion
      // barrier, so this one is not optional.
      await _pump(tester, const Pulse(child: Text('live')), reduceMotion: true);
      await tester.pumpAndSettle();

      expect(find.text('live'), findsOneWidget);
    });
  });

  group('PressScale', () {
    testWidgets('scales down while held and back up on release', (
      tester,
    ) async {
      await _pump(tester, const PressScale(child: Text('tap me')));

      double scaleOf() =>
          tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;

      expect(scaleOf(), 1);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('tap me')),
      );
      await tester.pump();
      expect(scaleOf(), lessThan(1));

      await gesture.up();
      await tester.pumpAndSettle();
      expect(scaleOf(), 1);
    });

    testWidgets('a child that wants the tap still gets it', (tester) async {
      // Listener rather than a competing GestureDetector, so wrapping an
      // existing button does not swallow its press.
      var taps = 0;
      await _pump(
        tester,
        PressScale(
          child: ElevatedButton(
            onPressed: () => taps++,
            child: const Text('inner'),
          ),
        ),
      );

      await tester.tap(find.text('inner'));
      await tester.pumpAndSettle();

      expect(taps, 1);
    });

    testWidgets('does not react when disabled', (tester) async {
      await _pump(
        tester,
        const PressScale(enabled: false, child: Text('busy')),
      );

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('busy')),
      );
      await tester.pump();

      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
      await gesture.up();
    });
  });

  group('SequencedReveal', () {
    testWidgets('reveals one turn at a time, with a typing beat between', (
      tester,
    ) async {
      await _pump(
        tester,
        const SequencedReveal(
          children: <Widget>[Text('one'), Text('two'), Text('three')],
        ),
      );

      // Nothing yet — somebody is composing.
      expect(find.text('one'), findsNothing);
      expect(find.byType(TypingIndicator), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('one'), findsOneWidget);
      expect(find.text('two'), findsNothing);

      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('two'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.text('three'), findsOneWidget);
      // Nothing left to say, so nobody is typing.
      expect(find.byType(TypingIndicator), findsNothing);
    });

    testWidgets('reveals everything at once under reduced motion', (
      tester,
    ) async {
      await _pump(
        tester,
        const SequencedReveal(
          children: <Widget>[Text('one'), Text('two'), Text('three')],
        ),
        reduceMotion: true,
      );
      await tester.pump();

      expect(find.text('one'), findsOneWidget);
      expect(find.text('three'), findsOneWidget);
      expect(find.byType(TypingIndicator), findsNothing);
    });

    testWidgets('a shrinking transcript does not overrun its children', (
      tester,
    ) async {
      // The intro rebuilds its turns from a step counter, so stepping back
      // produces fewer turns than are already on screen. Reading past the end
      // of the list would throw.
      await _pump(
        tester,
        const SequencedReveal(
          children: <Widget>[Text('one'), Text('two'), Text('three')],
        ),
        reduceMotion: true,
      );
      await tester.pump();

      await _pump(
        tester,
        const SequencedReveal(children: <Widget>[Text('one')]),
        reduceMotion: true,
      );
      await tester.pumpAndSettle();

      expect(find.text('one'), findsOneWidget);
      expect(find.text('two'), findsNothing);
    });
  });

  group('HeroNumeral', () {
    testWidgets('sets the value and the unit as separate type', (tester) async {
      // At 112pt a single formatted string would set `km` in 112pt too, and
      // the number would stop being the thing you see.
      await _pump(
        tester,
        const HeroNumeral(
          label: 'DISTANCE',
          value: 3.42,
          unit: 'km',
          animate: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('DISTANCE'), findsOneWidget);
      expect(find.text('3.42'), findsOneWidget);
      expect(find.text('km'), findsOneWidget);
      expect(find.text('3.42 km'), findsNothing);
    });

    testWidgets('counts up to its value when it appears', (tester) async {
      await _pump(
        tester,
        const HeroNumeral(label: 'DISTANCE', value: 5, unit: 'km'),
      );

      expect(find.text('0.00'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('5.00'), findsOneWidget);
    });
  });
}
