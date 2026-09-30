import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

void main() {
  group('SpringCurve', () {
    test('starts at 0 and lands on 1', () {
      for (final curve in <Curve>[AppMotion.snappy, AppMotion.gentle]) {
        expect(curve.transform(0), 0);
        expect(curve.transform(1), 1);
      }
    });

    test('carries a little past, and only a little', () {
      // A settle that is felt, not a wobble that is watched.
      final peak = <double>[
        for (var i = 1; i < 100; i++) AppMotion.snappy.transform(i / 100),
      ].reduce((a, b) => a > b ? a : b);
      expect(peak, greaterThan(1));
      expect(peak, lessThan(1.08));
    });

    test('critically damped does not overshoot', () {
      const curve = SpringCurve(damping: 1, frequency: 10);
      for (var i = 1; i < 100; i++) {
        expect(curve.transform(i / 100), lessThanOrEqualTo(1));
      }
    });
  });

  group('GlassSurface', () {
    test('drains colour: every channel reads the same luma', () {
      final m = GlassSurface.toneMatrix(1.1);
      // Rows for R, G and B are identical, so a green pixel and a grey one of
      // the same brightness come out the same.
      expect(m.sublist(0, 5), m.sublist(5, 10));
      expect(m.sublist(5, 10), m.sublist(10, 15));
      // And alpha is untouched.
      expect(m.sublist(15), <double>[0, 0, 0, 1, 0]);
    });

    test('keeps colour when asked', () {
      final m = GlassSurface.toneMatrix(1, desaturate: false);
      expect(m, <double>[
        1, 0, 0, 0, 0, //
        0, 1, 0, 0, 0, //
        0, 0, 1, 0, 0, //
        0, 0, 0, 1, 0, //
      ]);
    });

    testWidgets('the presets build', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Column(
            children: <Widget>[
              GlassSurface.bar(child: Text('bar')),
              GlassSurface.dock(child: Text('dock')),
              GlassSurface.sheet(child: Text('sheet')),
            ],
          ),
        ),
      );
      expect(find.byType(BackdropFilter), findsNWidgets(3));
    });
  });

  group('AppToast', () {
    testWidgets('shows the message, and the action runs once and closes it', (
      tester,
    ) async {
      var undone = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: TextButton(
                  onPressed: () => AppToast.show(
                    context,
                    'Set removed.',
                    actionLabel: 'Undo',
                    onAction: () => undone++,
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      expect(find.text('Set removed.'), findsOneWidget);
      // On glass, not on a filled bar.
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.byType(GlassSurface),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(undone, 1);
      expect(find.text('Set removed.'), findsNothing);
    });

    testWidgets('a message with no action has no button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => AppToast.show(context, 'Saved.'),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.byType(TextButton),
        ),
        findsNothing,
      );
    });
  });

  group('showGlassSheet', () {
    testWidgets('is as tall as what is in it, on glass', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showGlassSheet<void>(
                  context: context,
                  builder: (_) =>
                      const SizedBox(height: 120, child: Text('in')),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      final sheet = find.ancestor(
        of: find.text('in'),
        matching: find.byType(GlassSurface),
      );
      expect(sheet, findsOneWidget);
      expect(tester.getSize(sheet).height, lessThan(200));
    });

    testWidgets('and no taller than its ceiling', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showGlassSheet<void>(
                  context: context,
                  maxHeightFactor: 0.5,
                  builder: (_) => ListView(
                    shrinkWrap: true,
                    children: <Widget>[
                      for (var i = 0; i < 100; i++) Text('row $i'),
                    ],
                  ),
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();

      final screen = tester.getSize(find.byType(Scaffold)).height;
      final sheet = find.ancestor(
        of: find.text('row 0'),
        matching: find.byType(GlassSurface),
      );
      expect(tester.getSize(sheet).height, lessThanOrEqualTo(screen * 0.5));
    });
  });
}
