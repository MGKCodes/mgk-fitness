import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// The rail's ends have to say which way is which.
///
/// Two bare numbers asked the runner to infer that these were paces per
/// kilometre and that the *larger* one was slower. Pace runs backwards to every
/// other number on the screen, so the direction is the half that bites.
Widget _wrap(Widget child) => MaterialApp(
  theme: AppTheme.dark,
  home: Scaffold(body: child),
);

/// The plain text of every composed end label on screen.
List<String> _ends(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .where((Text t) => t.textSpan != null)
    .map((Text t) => t.textSpan!.toPlainText())
    .toList();

void main() {
  testWidgets('a corridor names both directions and carries the unit', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const PaceBandMeter(
          standing: PaceStanding.inBand,
          position: 0.5,
          slowLabel: '6:55',
          fastLabel: '6:24',
          unitSuffix: '/KM',
        ),
      ),
    );

    final List<String> ends = _ends(tester);
    expect(ends, hasLength(2));
    expect(ends.first, 'SLOWER  6:55/KM');
    expect(ends.last, '6:24/KM  FASTER');
  });

  testWidgets('a ceiling says what the one edge is, in speed not magnitude', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const PaceBandMeter(
          standing: PaceStanding.inBand,
          position: 0.2,
          fastLabel: '6:24',
          unitSuffix: '/KM',
          bandStart: 0,
        ),
      ),
    );

    final List<String> ends = _ends(tester);
    expect(ends, hasLength(1));
    expect(ends.single, 'NO FASTER THAN  6:24/KM');

    // The rule this phrasing exists for: a bigger pace number is a slower pace,
    // so any word implying a numeric bound can be read backwards. "MAX 6:24"
    // parses as "do not exceed 6:24", which is "do not go slower than 6:24" —
    // the opposite of a ceiling.
    for (final String banned in <String>['MAX', 'LIMIT', 'CAP', 'UP TO']) {
      expect(
        ends.single.contains(banned),
        isFalse,
        reason: '$banned inherits the pace reversal and can be read backwards',
      );
    }
  });

  testWidgets('the direction word is quieter than the figure it labels', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const PaceBandMeter(
          standing: PaceStanding.inBand,
          position: 0.5,
          slowLabel: '6:55',
          fastLabel: '6:24',
          unitSuffix: '/KM',
        ),
      ),
    );

    final TextSpan root =
        tester
                .widgetList<Text>(find.byType(Text))
                .firstWhere((Text t) => t.textSpan != null)
                .textSpan!
            as TextSpan;
    final List<TextSpan> runs = root.children!.cast<TextSpan>().toList();

    final double wordSize = runs.first.style!.fontSize!;
    final double valueSize = runs.last.style!.fontSize!;
    expect(
      wordSize,
      lessThan(valueSize),
      reason: 'the number is the fact; the word is scaffolding',
    );
  });

  testWidgets('no labels at all still renders the bare rail', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const PaceBandMeter(standing: PaceStanding.unknown, position: 0.5)),
    );

    expect(_ends(tester), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
