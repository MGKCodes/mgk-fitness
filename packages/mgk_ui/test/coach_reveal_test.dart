import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// The coach's line used to fade in already open, hold for under two seconds
/// and close. On a screen that had only just appeared that was reported as
/// "it kind of just happens and you can't really tell what it is". It opens
/// out of the mark now, is held for as long as its caller asks, and can be
/// told to wait until the screen is on show.
void main() {
  const CoachLine line = CoachLine(
    headline: 'Longest one yet.',
    detail: 'You went further than you ever have.',
  );

  Widget host({
    bool ready = true,
    Duration duration = kCoachRevealDuration,
    VoidCallback? onFinished,
  }) => MaterialApp(
    home: Scaffold(
      body: Stack(
        children: <Widget>[
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: CoachReveal(
              note: line,
              ready: ready,
              duration: duration,
              onFinished: onFinished,
            ),
          ),
        ],
      ),
    ),
  );

  double barWidth(WidgetTester tester) =>
      tester.getSize(find.byType(CoachMarkSurface)).width;

  testWidgets('it opens out of the mark, and closes back into it', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(host());

    // The mark, before anything has moved.
    expect(barWidth(tester), kCoachMarkSize);

    await tester.pump(const Duration(milliseconds: 230));
    expect(
      barWidth(tester),
      inExclusiveRange(kCoachMarkSize, 388),
      reason: 'part way open, part way through opening',
    );

    await tester.pump(CoachReveal.openFor);
    expect(barWidth(tester), 388, reason: 'the full width it was given');

    await tester.pumpAndSettle();
    expect(barWidth(tester), kCoachMarkSize);
    expect(find.text('C'), findsOneWidget);
  });

  testWidgets('a longer duration is a longer read, not a slower animation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const Duration long = Duration(milliseconds: 6800);
    await tester.pumpWidget(host(duration: long));

    // Open and typed in the same time as at the default length.
    await tester.pump(CoachReveal.openFor + CoachReveal.typeFor);
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('Longest one yet.'), findsOneWidget);
    expect(find.text('You went further than you ever have.'), findsOneWidget);

    // Still open, whole and at full strength four and a half seconds later,
    // which is past where the default would have closed.
    await tester.pump(const Duration(milliseconds: 4500));
    expect(barWidth(tester), 388);
    expect(find.text('You went further than you ever have.'), findsOneWidget);
    final Opacity text = tester.widget<Opacity>(
      find
          .ancestor(
            of: find.text('Longest one yet.'),
            matching: find.byType(Opacity),
          )
          .first,
    );
    expect(text.opacity, 1);

    await tester.pumpAndSettle();
    expect(barWidth(tester), kCoachMarkSize);
  });

  testWidgets('told to wait, it rests as the mark and says nothing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var finished = 0;
    await tester.pumpWidget(host(ready: false, onFinished: () => finished++));

    await tester.pump(const Duration(seconds: 5));
    expect(barWidth(tester), kCoachMarkSize);
    expect(finished, 0, reason: 'a line nobody saw has not been delivered');

    // The screen is on show: it starts from the beginning, not part way in.
    await tester.pumpWidget(host(onFinished: () => finished++));
    await tester.pump(const Duration(milliseconds: 230));
    expect(barWidth(tester), inExclusiveRange(kCoachMarkSize, 388));

    await tester.pumpAndSettle();
    expect(finished, 1);
  });
}
