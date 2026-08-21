import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// A transition involves two screens, and both of them have to move.
///
/// `secondaryAnimation` — the page being covered — was ignored, so a push left
/// the page behind perfectly still while something slid over it, and a pop
/// uncovered it rather than bringing it back. These assert the covered page
/// actually goes somewhere, in both directions, because that is invisible in a
/// screenshot and easy to lose in a refactor.
void main() {
  Widget app(GlobalKey<NavigatorState> nav) => MaterialApp(
    theme: AppTheme.dark,
    navigatorKey: nav,
    home: const Scaffold(body: Center(child: Text('first'))),
  );

  /// The opacity actually applied to the named text, walked up through every
  /// FadeTransition above it — there are two, and only their product is what a
  /// person sees.
  double opacityOf(WidgetTester tester, String text) {
    double value = 1;
    for (final Element e
        in find
            .ancestor(
              of: find.text(text),
              matching: find.byType(FadeTransition),
            )
            .evaluate()) {
      value *= (e.widget as FadeTransition).opacity.value;
    }
    return value;
  }

  testWidgets('the covered page dims and lifts as another arrives', (
    WidgetTester tester,
  ) async {
    final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(app(nav));

    expect(opacityOf(tester, 'first'), 1);

    unawaited(
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Center(child: Text('second'))),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    // Mid-flight: the old page is on its way out rather than sitting still.
    expect(
      opacityOf(tester, 'first'),
      lessThan(1),
      reason: 'the page being covered used to not move at all',
    );

    await tester.pumpAndSettle();
  });

  testWidgets('and comes back rather than being switched on', (
    WidgetTester tester,
  ) async {
    final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(app(nav));

    unawaited(
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Center(child: Text('second'))),
        ),
      ),
    );
    await tester.pumpAndSettle();

    nav.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final double returning = opacityOf(tester, 'first');
    expect(returning, greaterThan(0));
    expect(returning, lessThan(1), reason: 'still on its way back');

    await tester.pumpAndSettle();
    expect(opacityOf(tester, 'first'), 1);
  });
}
