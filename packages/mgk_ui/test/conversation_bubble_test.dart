import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// The two layout rules in this file are the kind that get undone by accident,
/// because undoing either still compiles and still looks fine with a full
/// screen of conversation. They only show up on the first turn.
void main() {
  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(body: child),
  );

  group('ConversationView', () {
    testWidgets('settles a short conversation at the top', (
      WidgetTester tester,
    ) async {
      // This assertion used to be its own inverse, and the reason it flipped is
      // worth keeping: the coach became a sheet. See [ConversationAnchor].
      // Bottom-anchored inside a sheet, every turn on screen jumps the height
      // of the keyboard each time the composer is tapped.
      await tester.pumpWidget(
        host(
          const ConversationView(
            children: <Widget>[
              ConversationBubble(text: 'One line.', fromCoach: true),
            ],
          ),
        ),
      );

      final screen = tester.getSize(find.byType(Scaffold)).height;
      final bubble = tester.getRect(find.byType(ConversationBubble));

      expect(
        bubble.top,
        lessThan(screen / 3),
        reason: 'a single turn should stay where it was read',
      );
    });

    testWidgets('the bottom anchor is still available for a full page', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          const ConversationView(
            anchor: ConversationAnchor.bottom,
            children: <Widget>[
              ConversationBubble(text: 'One line.', fromCoach: true),
            ],
          ),
        ),
      );

      final screen = tester.getSize(find.byType(Scaffold)).height;
      final bubble = tester.getRect(find.byType(ConversationBubble));
      expect(bubble.bottom, greaterThan(screen * 2 / 3));
    });

    testWidgets('a long conversation still scrolls', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          ConversationView(
            children: <Widget>[
              for (int i = 0; i < 40; i++)
                ConversationBubble(
                  text: 'Turn $i',
                  fromCoach: i.isEven,
                  // Not the subject here, and a SelectableText carries its own
                  // Scrollable, which would make the one below ambiguous.
                  selectable: false,
                ),
            ],
          ),
        ),
      );

      // Forcing the content to viewport height must not also cap it there.
      final ScrollableState scrollable = tester.state(find.byType(Scrollable));
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
    });

    testWidgets('survives being offered less height than its padding', (
      WidgetTester tester,
    ) async {
      // A zero-height layout pass is ordinary — it happens to a tab underneath
      // a full-height sheet — and it made minHeight negative, which fails an
      // assertion and replaces the whole route with the red error screen.
      await tester.pumpWidget(
        host(
          const SizedBox(
            height: 0,
            child: ConversationView(
              padding: EdgeInsets.symmetric(vertical: 24),
              children: <Widget>[
                ConversationBubble(
                  text: 'Still here.',
                  fromCoach: true,
                  selectable: false,
                ),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('ConversationBubble', () {
    testWidgets('never reaches both margins', (WidgetTester tester) async {
      await tester.pumpWidget(
        host(
          const ConversationView(
            children: <Widget>[
              ConversationBubble(
                text:
                    'A reply long enough that it would happily run the full '
                    'width of the screen if nothing stopped it, which is the '
                    'point of the constraint being tested here.',
                fromCoach: true,
              ),
            ],
          ),
        ),
      );

      final screen = tester.getSize(find.byType(Scaffold)).width;
      final bubble = tester.getSize(find.byType(ConversationBubble)).width;

      // Full width stops reading as one side of a conversation and starts
      // reading as a paragraph.
      expect(bubble, lessThan(screen));
    });

    testWidgets('the two sides differ in weight, not colour', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        host(
          const ConversationView(
            children: <Widget>[
              ConversationBubble(text: 'Coach.', fromCoach: true),
              ConversationBubble(text: 'Lifter.', fromCoach: false),
            ],
          ),
        ),
      );

      Color fillOf(String text) {
        final DecoratedBox box = tester.widget(
          find.descendant(
            of: find.widgetWithText(ConversationBubble, text),
            matching: find.byType(DecoratedBox),
          ),
        );
        return ((box.decoration as BoxDecoration).color)!;
      }

      // ADR-0009: there is no accent to reach for, so the sides are told apart
      // by surface weight. Both fills must stay greyscale.
      for (final Color fill in <Color>[fillOf('Coach.'), fillOf('Lifter.')]) {
        expect(
          fill.r == fill.g && fill.g == fill.b,
          isTrue,
          reason: 'bubbles must not introduce a hue',
        );
      }
      expect(fillOf('Coach.'), isNot(fillOf('Lifter.')));
    });
  });
}
