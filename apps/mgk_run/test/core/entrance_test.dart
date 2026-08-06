import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

double _opacityOf(WidgetTester tester, String text) {
  final opacity = tester.widget<Opacity>(
    find.ancestor(of: find.text(text), matching: find.byType(Opacity)).first,
  );
  return opacity.opacity;
}

void main() {
  testWidgets('content is invisible at rest and fully settled after', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Entrance(child: Text('hello'))),
      ),
    );

    expect(_opacityOf(tester, 'hello'), 0);
    await tester.pumpAndSettle();
    expect(_opacityOf(tester, 'hello'), 1);
  });

  testWidgets('a later item arrives after an earlier one', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              Entrance(child: Text('first')),
              Entrance(index: 4, child: Text('fifth')),
            ],
          ),
        ),
      ),
    );

    // Part-way through the first item's animation the staggered one has not
    // begun — that ordering is the whole effect.
    await tester.pump(AppMotion.base ~/ 2);
    expect(_opacityOf(tester, 'first'), greaterThan(0));
    expect(_opacityOf(tester, 'fifth'), 0);

    await tester.pumpAndSettle();
    expect(_opacityOf(tester, 'fifth'), 1);
  });

  testWidgets('a disposed item leaves no pending timer', (tester) async {
    // Regression: the stagger was a Future.delayed, so scrolling a row out of
    // view before it fired left a timer behind. testWidgets fails the test if
    // one is outstanding, which is what caught it.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Entrance(index: 6, child: Text('doomed'))),
      ),
    );
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );
    await tester.pumpAndSettle();

    expect(find.text('doomed'), findsNothing);
  });

  testWidgets('reduced motion skips straight to the settled state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          home: Scaffold(body: Entrance(index: 3, child: Text('instant'))),
        ),
      ),
    );

    // No pump beyond the first frame: motion is a genuine barrier for some
    // people, so the content must simply be there.
    expect(_opacityOf(tester, 'instant'), 1);
  });
}
