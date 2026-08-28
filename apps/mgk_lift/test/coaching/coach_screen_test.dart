import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
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

  testWidgets('only the message is sent; the server holds the thread', (
    WidgetTester tester,
  ) async {
    // The transcript lives in coach.turns and is replayed server-side, so the
    // screen sends one line and nothing else. Sending its own history would be
    // a second source of truth for what was said, and the one the client can
    // rewrite.
    final coach = FakeCoach(reply: 'You have not added weight in a month.');
    await tester.pumpWidget(
      wrap(CoachScreen(coach: coach, opener: 'Bench has not moved.')),
    );
    await tester.pumpAndSettle();

    await ask(tester, 'Why has my bench stalled?');
    await ask(tester, 'So what do I do?');

    expect(coach.asked, <String>[
      'Why has my bench stalled?',
      'So what do I do?',
    ]);
  });

  group('resuming a stored conversation', () {
    testWidgets('what was said before is on screen when it opens', (
      WidgetTester tester,
    ) async {
      // The whole point: the server always replayed this to the model, so a
      // screen that did not show it invited the lifter to re-explain an injury
      // the coach already knew about.
      await tester.pumpWidget(
        wrap(
          CoachScreen(coach: FakeCoach(), transcript: FakeCoachTranscript()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Why has my bench stalled?'), findsOneWidget);
      expect(
        find.textContaining('held 85 kg for six sessions'),
        findsOneWidget,
      );
      expect(find.text('It has read your log'), findsNothing);
    });

    testWidgets('turns keep the order they were said in', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          CoachScreen(coach: FakeCoach(), transcript: FakeCoachTranscript()),
        ),
      );
      await tester.pumpAndSettle();

      final first = tester
          .getTopLeft(find.text('Why has my bench stalled?'))
          .dy;
      final later = tester
          .getTopLeft(find.text('Shoulder is sore on the left though'))
          .dy;
      expect(first, lessThan(later));
    });

    testWidgets('a transcript that will not load opens like a new one', (
      WidgetTester tester,
    ) async {
      // read() never throws — a failed read arrives as an empty list, and the
      // composer never depended on it. Breaking the working half to report the
      // broken one would be the wrong trade.
      await tester.pumpWidget(
        wrap(
          CoachScreen(
            coach: FakeCoach(),
            transcript: FakeCoachTranscript(empty: true),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('It has read your log'), findsOneWidget);
    });

    testWidgets('the opener gives way to a real conversation', (
      WidgetTester tester,
    ) async {
      // Appended after real history it reads as something the coach just said.
      await tester.pumpWidget(
        wrap(
          CoachScreen(
            coach: FakeCoach(),
            transcript: FakeCoachTranscript(),
            opener: 'Bench has not moved.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bench has not moved.'), findsNothing);
      expect(find.text('Why has my bench stalled?'), findsOneWidget);
    });

    testWidgets('the opener survives an empty transcript', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          CoachScreen(
            coach: FakeCoach(),
            transcript: FakeCoachTranscript(empty: true),
            opener: 'Bench has not moved.',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Bench has not moved.'), findsOneWidget);
    });

    testWidgets('a question asked mid-read still lands after the history', (
      WidgetTester tester,
    ) async {
      // The composer stays live while the transcript loads, so this race is
      // reachable by anyone who opens the coach and types immediately.
      // Appending the history would file it underneath the new question.
      final slow = _SlowTranscript();
      await tester.pumpWidget(
        wrap(CoachScreen(coach: FakeCoach(), transcript: slow)),
      );
      await tester.pump();

      await ask(tester, 'Shoulder is sore');
      slow.complete();
      await tester.pumpAndSettle();

      final history = tester
          .getTopLeft(find.text('Why has my bench stalled?'))
          .dy;
      final asked = tester.getTopLeft(find.text('Shoulder is sore')).dy;
      expect(history, lessThan(asked));
    });

    testWidgets('resuming does not resend the history', (
      WidgetTester tester,
    ) async {
      // The server holds the thread. Showing it must not turn the screen into a
      // second source of truth for what was said.
      final coach = FakeCoach();
      await tester.pumpWidget(
        wrap(CoachScreen(coach: coach, transcript: FakeCoachTranscript())),
      );
      await tester.pumpAndSettle();

      await ask(tester, 'So what do I do?');

      expect(coach.asked, <String>['So what do I do?']);
    });
  });

  group('suggested replies', () {
    CoachTurn coachSaid(String body, List<String> chips) => CoachTurn(
      id: body,
      body: body,
      fromCoach: true,
      at: DateTime(2026, 8, 6),
      suggestions: chips,
    );

    Widget withChips(List<CoachTurn> turns, {FakeCoach? coach}) => wrap(
      CoachScreen(
        coach: coach ?? FakeCoach(),
        transcript: FakeCoachTranscript(turns: turns),
      ),
    );

    testWidgets('the chips the coach offered are shown', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        withChips(<CoachTurn>[
          coachSaid('What are you training for?', <String>[
            'Get stronger',
            'Lose weight',
          ]),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Get stronger'), findsOneWidget);
      expect(find.text('Lose weight'), findsOneWidget);
    });

    testWidgets('tapping one sends exactly what it said', (
      WidgetTester tester,
    ) async {
      // Not a paraphrase. The server replays the transcript, so a chip sending
      // anything other than its own label puts a sentence nobody saw into what
      // the coach then reasons from.
      final coach = FakeCoach();
      await tester.pumpWidget(
        withChips(<CoachTurn>[
          coachSaid('What are you training for?', <String>['Get stronger']),
        ], coach: coach),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Get stronger'));
      await tester.pumpAndSettle();

      expect(coach.asked, <String>['Get stronger']);
    });

    testWidgets('only the newest turn offers them', (
      WidgetTester tester,
    ) async {
      // Chips under an older message offer to answer a question that has
      // already been answered.
      await tester.pumpWidget(
        withChips(<CoachTurn>[
          coachSaid('Old question?', <String>['Stale option']),
          coachSaid('New question?', <String>['Live option']),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('Stale option'), findsNothing);
      expect(find.text('Live option'), findsOneWidget);
    });

    testWidgets('a turn with none renders none', (WidgetTester tester) async {
      await tester.pumpWidget(
        wrap(
          CoachScreen(coach: FakeCoach(), transcript: FakeCoachTranscript()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OptionStack), findsNothing);
    });
  });
}

/// A transcript that answers only when told to, so the gap between opening the
/// screen and the history arriving can be tested rather than assumed away.
class _SlowTranscript implements CoachTranscript {
  final Completer<List<CoachTurn>> _done = Completer<List<CoachTurn>>();

  void complete() =>
      _done.complete(FakeCoachTranscript().read('lift:test-open'));

  @override
  Future<List<CoachTurn>> read(String conversationId) => _done.future;

  /// Answers immediately: the delay under test is the transcript arriving, not
  /// which conversation it belongs to.
  @override
  Future<String?> openConversationId({
    Duration window = coachSessionWindow,
  }) async => 'lift:test-open';

  @override
  Future<List<CoachConversationSummary>> conversations({
    int limit = 20,
  }) async => const <CoachConversationSummary>[];

  @override
  Future<List<CoachTurn>> fullTranscript(String conversationId) => _done.future;
}
