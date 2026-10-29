import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// The coach's scripted lines, which both apps open on. Run drew them first,
/// as its own `Said`; these are what Lift draws, and what Run can point at.
void main() {
  Widget host(Widget child) => MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(body: child),
  );

  testWidgets('a line is the coach speaking: the C beside it, no bubble', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(host(const ScriptedLine("Hey. I'm your coach.")));

    expect(find.text("Hey. I'm your coach."), findsOneWidget);
    expect(find.byType(CoachAvatar), findsOneWidget);
    // The coach's one mark, at this size too.
    expect(
      find.descendant(
        of: find.byType(CoachAvatar),
        matching: find.byType(CoachLetter),
      ),
      findsOneWidget,
    );
    // No fill behind the words: a filled bubble is a conversation the model
    // is holding, which this is not.
    expect(find.byType(ConversationBubble), findsNothing);
  });

  testWidgets('the mark sits to the left of the words, at their top', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        const ScriptedLine(
          'A line long enough to run onto a second one, so the mark has a '
          'paragraph to sit beside rather than a single row of text.',
        ),
      ),
    );

    final mark = tester.getRect(find.byType(CoachAvatar));
    final words = tester.getRect(find.textContaining('A line long'));
    expect(mark.right, lessThanOrEqualTo(words.left));
    expect(mark.top, lessThanOrEqualTo(words.top + 1));
  });
}
