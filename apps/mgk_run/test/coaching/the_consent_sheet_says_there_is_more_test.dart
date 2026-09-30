import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/presentation/ai_consent_sheet.dart';

import '../plates/plate.dart' show kPhone, kSmallPhone, loadInter;

/// The coach's consent sheet on a 320pt phone (screen board C8). "Never sent"
/// and the retention line are below the fold there, and nothing on screen
/// said so; this is the sheet whose job is to be read before it is answered.
void main() {
  Future<void> open(WidgetTester tester, Size size) async {
    await loadInter();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => AiConsentSheet.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
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

  testWidgets('at 320pt the foot of the text fades, until it is reached', (
    tester,
  ) async {
    await open(tester, kSmallPhone);
    expect(fade(tester), 1, reason: 'there is more below the fold');

    await tester.drag(
      find.descendant(
        of: find.byType(AiConsentSheet),
        matching: find.byType(SingleChildScrollView),
      ),
      const Offset(0, -1500),
    );
    await tester.pumpAndSettle();
    expect(fade(tester), 0, reason: 'nothing left to hint at');
    // The buttons were never what scrolled.
    expect(find.text(AiConsentSheet.agreeLabel).hitTestable(), findsOneWidget);
  });

  testWidgets('and where it all fits, there is no fade', (tester) async {
    await open(tester, const Size(430, 1400));
    expect(fade(tester), 0);
  });

  testWidgets('on a 393pt phone it is there only if the text runs over', (
    tester,
  ) async {
    await open(tester, kPhone);
    final scroll = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(AiConsentSheet),
        matching: find.byType(Scrollable),
      ),
    );
    expect(fade(tester), scroll.position.extentAfter > 0.5 ? 1 : 0);
  });
}
