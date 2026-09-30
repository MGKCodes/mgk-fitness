import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required int lines}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 200,
              child: ScrollEdgeFade(
                child: SingleChildScrollView(
                  child: Column(
                    children: <Widget>[
                      for (var i = 0; i < lines; i++)
                        SizedBox(height: 40, child: Text('line $i')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  double fade(WidgetTester tester) => tester
      .widget<AnimatedOpacity>(
        find.descendant(
          of: find.byType(ScrollEdgeFade),
          matching: find.byType(AnimatedOpacity),
        ),
      )
      .opacity;

  testWidgets('says there is more while there is', (tester) async {
    await pump(tester, lines: 20);
    expect(fade(tester), 1);

    // At the end, the fade goes: nothing more to hint at.
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -2000),
    );
    await tester.pumpAndSettle();
    expect(fade(tester), 0);

    // And comes back on the way up.
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(fade(tester), 1);
  });

  testWidgets('a region that fits is drawn as it was', (tester) async {
    await pump(tester, lines: 3);
    expect(fade(tester), 0);
  });

  testWidgets('the fade takes no touches', (tester) async {
    await pump(tester, lines: 20);
    // The last visible line sits under the fade and is still a scroll target.
    await tester.drag(find.text('line 4'), const Offset(0, -100));
    await tester.pumpAndSettle();
    final scrolled = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrolled.position.pixels, greaterThan(0));
  });
}
