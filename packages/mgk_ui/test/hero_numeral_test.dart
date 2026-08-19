import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// Finds the numeral itself: the only [Text] built from spans rather than a
/// plain string. The eyebrow and the unit are both plain.
TextSpan _numeralSpan(WidgetTester tester) {
  final Text numeral = tester
      .widgetList<Text>(find.byType(Text))
      .firstWhere((Text t) => t.textSpan != null);
  return numeral.textSpan! as TextSpan;
}

List<TextSpan> _runs(TextSpan root) => root.children!.cast<TextSpan>().toList();

void main() {
  group('HeroNumeral splits digits from separators', () {
    testWidgets('the decimal point is spared the tabular digit cell', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HeroNumeral(
              label: 'DISTANCE',
              value: 0.45,
              unit: 'km',
              animate: false,
            ),
          ),
        ),
      );

      final List<TextSpan> runs = _runs(_numeralSpan(tester));
      expect(
        runs.map((TextSpan s) => s.text),
        <String>['0', '.', '45'],
        reason: 'digits and separators must be separate runs',
      );

      // The point is why this exists: tabular figures lock a *ticking* digit to
      // a fixed cell, and a separator never ticks. Left in the feature it takes
      // a full digit width, and `0.45` reads as two numbers.
      expect(
        runs[0].style!.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
      expect(runs[1].style!.fontFeatures, isEmpty);
      expect(
        runs[2].style!.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    testWidgets('a thousands separator is spared it too', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HeroNumeral(
              label: 'TOTAL',
              value: 1234.5,
              unit: 'km',
              animate: false,
              format: (double v) => '1,234.50',
            ),
          ),
        ),
      );

      final List<TextSpan> runs = _runs(_numeralSpan(tester));
      expect(runs.map((TextSpan s) => s.text), <String>[
        '1',
        ',',
        '234',
        '.',
        '50',
      ]);
      expect(runs[1].style!.fontFeatures, isEmpty);
      expect(runs[3].style!.fontFeatures, isEmpty);
    });

    testWidgets('a whole number is a single run and keeps its grid', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HeroNumeral(
              label: 'TOTAL',
              value: 12,
              unit: 'km',
              animate: false,
              format: (double v) => '12',
            ),
          ),
        ),
      );

      final List<TextSpan> runs = _runs(_numeralSpan(tester));
      expect(runs.map((TextSpan s) => s.text), <String>['12']);
      expect(
        runs.single.style!.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    testWidgets('the split survives the count-up animation', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HeroNumeral(label: 'DISTANCE', value: 3.42, unit: 'km'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 120));

      // Mid-count the value is not 3.42 yet, but it is still one number with
      // one point in it, and the point must not have reclaimed its cell.
      final List<TextSpan> runs = _runs(_numeralSpan(tester));
      expect(runs.length, 3);
      expect(runs[1].text, '.');
      expect(runs[1].style!.fontFeatures, isEmpty);

      await tester.pumpAndSettle();
      expect(_runs(_numeralSpan(tester)).map((TextSpan s) => s.text), <String>[
        '3',
        '.',
        '42',
      ]);
    });
  });
}
