import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/coaching/data/supabase_coach.dart';
import 'package:mgk_lift/src/features/coaching/domain/coach.dart';
import 'package:mgk_lift/src/features/coaching/presentation/coach_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

Future<void> ask(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.byIcon(Icons.arrow_upward));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('an empty conversation suggests something concrete', (
    WidgetTester tester,
  ) async {
    // "Ask me anything" is the least useful prompt in software.
    await tester.pumpWidget(wrap(CoachScreen(coach: FakeCoach())));
    await tester.pumpAndSettle();

    expect(find.text('It has read your log'), findsOneWidget);
    expect(find.textContaining('why a lift has stalled'), findsOneWidget);
  });

  testWidgets('a reply appears after the question', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(CoachScreen(coach: FakeCoach(reply: 'Add 2.5kg next week.'))),
    );
    await tester.pumpAndSettle();

    await ask(tester, 'Why has my bench stalled?');

    expect(find.text('Why has my bench stalled?'), findsOneWidget);
    expect(find.text('Add 2.5kg next week.'), findsOneWidget);
  });

  group('when it cannot answer', () {
    testWidgets('the question stays on screen', (WidgetTester tester) async {
      // Removing it would lose what they typed, and the failure is nearly
      // always transient - the obvious next action is to send it again.
      await tester.pumpWidget(
        wrap(CoachScreen(coach: FakeCoach(failWith: CoachFailure.unavailable))),
      );
      await tester.pumpAndSettle();

      await ask(tester, 'Shoulder is sore');

      expect(find.text('Shoulder is sore'), findsOneWidget);
    });

    testWidgets('being offline says tracking still works', (
      WidgetTester tester,
    ) async {
      // The normal case in a gym basement, and not the lifter's fault.
      await tester.pumpWidget(
        wrap(CoachScreen(coach: FakeCoach(failWith: CoachFailure.unavailable))),
      );
      await tester.pumpAndSettle();
      await ask(tester, 'anything');

      expect(find.textContaining('Tracking works without one'), findsOneWidget);
    });

    testWidgets('a spent allowance says when it comes back', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          CoachScreen(coach: FakeCoach(failWith: CoachFailure.limitReached)),
        ),
      );
      await tester.pumpAndSettle();
      await ask(tester, 'anything');

      expect(find.textContaining('resets in the morning'), findsOneWidget);
    });

    testWidgets('the free tier is told what the coach is, not just refused', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(CoachScreen(coach: FakeCoach(failWith: CoachFailure.notEntitled))),
      );
      await tester.pumpAndSettle();
      await ask(tester, 'anything');

      expect(find.text('Coaching is part of the paid plan.'), findsOneWidget);
    });
  });

  testWidgets('an empty message is not sent', (WidgetTester tester) async {
    await tester.pumpWidget(wrap(CoachScreen(coach: FakeCoach())));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.arrow_upward));
    await tester.pumpAndSettle();

    expect(find.text('It has read your log'), findsOneWidget);
  });

  testWidgets('an opener means the screen is not an empty box', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      wrap(CoachScreen(coach: FakeCoach(), opener: 'Bench has not moved.')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bench has not moved.'), findsOneWidget);
    expect(find.text('It has read your log'), findsNothing);
  });

  group('the conversation is carried', () {
    testWidgets('the first message has nothing behind it', (
      WidgetTester tester,
    ) async {
      final coach = FakeCoach();
      await tester.pumpWidget(wrap(CoachScreen(coach: coach)));
      await tester.pumpAndSettle();

      await ask(tester, 'Why has my bench stalled?');

      expect(coach.lastHistory, isEmpty);
    });

    testWidgets('later messages carry what was said before them', (
      WidgetTester tester,
    ) async {
      // Without this the coach answers "so what do I do?" as if it were the
      // first thing anyone had said to it.
      final coach = FakeCoach(reply: 'You have not added weight in a month.');
      await tester.pumpWidget(
        wrap(CoachScreen(coach: coach, opener: 'Bench has not moved.')),
      );
      await tester.pumpAndSettle();

      await ask(tester, 'Why has my bench stalled?');
      await ask(tester, 'So what do I do?');

      expect(coach.lastHistory.map((CoachTurn t) => t.body).toList(), <String>[
        'Bench has not moved.',
        'Why has my bench stalled?',
        'You have not added weight in a month.',
      ]);
      // The message being sent must not also appear in its own history.
      expect(
        coach.lastHistory.map((CoachTurn t) => t.body),
        isNot(contains('So what do I do?')),
      );
    });
  });
}
