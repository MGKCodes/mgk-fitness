import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/coaching/data/supabase_coach.dart';
import 'package:mgk_lift/src/features/coaching/domain/coach.dart';
import 'package:mgk_lift/src/features/coaching/presentation/coach_history_sheet.dart';
import 'package:mgk_lift/src/features/coaching/presentation/day_label.dart';
import 'package:mgk_lift/src/features/coaching/presentation/coach_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

Future<void> ask(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.tap(find.byIcon(Icons.arrow_upward));
  await tester.pumpAndSettle();
}

CoachConversationSummary summary(
  String id, {
  required DateTime at,
  int turns = 4,
  String? opening,
}) => CoachConversationSummary(
  id: id,
  startedAt: at.subtract(const Duration(minutes: 6)),
  lastTurnAt: at,
  turns: turns,
  opening: opening,
);

void main() {
  group('the session id', () {
    test('is unique per conversation', () {
      // Two devices opening a conversation in the same microsecond would
      // collide on a primary key without the entropy, and the write would fail
      // outright rather than degrade.
      final ids = <String>{
        for (var i = 0; i < 500; i++) newCoachConversationId(),
      };
      expect(ids.length, 500);
    });

    test('carries the app, because coach is one table for two apps', () {
      expect(newCoachConversationId(), startsWith('lift:'));
    });
  });

  group('resuming', () {
    testWidgets('an open conversation comes back', (tester) async {
      await tester.pumpWidget(
        wrap(
          CoachScreen(coach: FakeCoach(), transcript: FakeCoachTranscript()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Why has my bench stalled?'), findsOneWidget);
    });

    testWidgets('a closed one does not, and the screen opens fresh', (
      tester,
    ) async {
      // The whole of the session boundary on a cold start. `empty` reports no
      // open conversation, which is what a transcript whose last turn is older
      // than the window answers.
      await tester.pumpWidget(
        wrap(
          CoachScreen(
            coach: FakeCoach(),
            transcript: FakeCoachTranscript(empty: true),
            opener: 'It has read your log',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Why has my bench stalled?'), findsNothing);
      expect(find.text('It has read your log'), findsOneWidget);
    });
  });

  group('which conversation a turn goes to', () {
    testWidgets('a typed follow-up continues the conversation resumed', (
      tester,
    ) async {
      final coach = FakeCoach();
      await tester.pumpWidget(
        wrap(wrapScreen(coach, FakeCoachTranscript(openId: 'lift:resumed'))),
      );
      await tester.pumpAndSettle();

      await ask(tester, 'And my squat?');

      expect(coach.askedIn.single, 'lift:resumed');
    });

    testWidgets('a tapped suggestion starts a new one', (tester) async {
      // A chip is a subject the screen raised, not the next line of what was
      // being discussed. Continuing into it is how a half-finished exchange
      // about a sore shoulder becomes the context for "how is my training
      // going".
      final coach = FakeCoach();
      await tester.pumpWidget(
        wrap(
          wrapScreen(
            coach,
            FakeCoachTranscript(
              openId: 'lift:resumed',
              turns: <CoachTurn>[
                CoachTurn(
                  id: 'c1',
                  body: 'Ask me anything.',
                  fromCoach: true,
                  at: DateTime(2026, 8, 28, 9),
                  suggestions: const <String>['Why has my bench stalled?'],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Why has my bench stalled?'));
      await tester.pumpAndSettle();

      expect(coach.askedIn.single, isNot('lift:resumed'));
    });

    testWidgets('everything after a chip continues the chip, not what came '
        'before it', (tester) async {
      final coach = FakeCoach();
      await tester.pumpWidget(
        wrap(
          wrapScreen(
            coach,
            FakeCoachTranscript(
              openId: 'lift:resumed',
              turns: <CoachTurn>[
                CoachTurn(
                  id: 'c1',
                  body: 'Ask me anything.',
                  fromCoach: true,
                  at: DateTime(2026, 8, 28, 9),
                  suggestions: const <String>['Why has my bench stalled?'],
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Why has my bench stalled?'));
      await tester.pumpAndSettle();
      await ask(tester, 'And the squat?');

      expect(coach.askedIn.length, 2);
      expect(coach.askedIn.first, coach.askedIn.last);
      expect(coach.askedIn.first, isNot('lift:resumed'));
    });
  });

  group('previous conversations', () {
    testWidgets('lists what is kept, and says when', (tester) async {
      final now = DateTime(2026, 8, 28, 18);
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: PastConversationsSheet(
              transcript: FakeCoachTranscript(
                past: <CoachConversationSummary>[
                  summary(
                    'lift:a',
                    at: now.subtract(const Duration(days: 1)),
                    turns: 6,
                    opening: 'Why has my bench stalled?',
                  ),
                ],
              ),
              now: now,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('6 messages'), findsOneWidget);
      expect(find.text('Why has my bench stalled?'), findsOneWidget);
    });

    testWidgets('leaves out the conversation on screen behind it', (
      tester,
    ) async {
      // "Previous" means previous. Listing the live one offers to open a
      // read-only copy of what the lifter is already looking at.
      final now = DateTime(2026, 8, 28, 18);
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: PastConversationsSheet(
              transcript: FakeCoachTranscript(
                past: <CoachConversationSummary>[
                  summary('lift:live', at: now, opening: 'Happening now'),
                  summary(
                    'lift:old',
                    at: now.subtract(const Duration(days: 3)),
                    opening: 'Last week',
                  ),
                ],
              ),
              liveConversationId: 'lift:live',
              now: now,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Happening now'), findsNothing);
      expect(find.text('Last week'), findsOneWidget);
    });

    testWidgets('an empty history says what will fill it', (tester) async {
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: PastConversationsSheet(
              transcript: FakeCoachTranscript(),
              now: DateTime(2026, 8, 28),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Nothing here yet'), findsOneWidget);
    });

    testWidgets('loading is not the same state as empty', (tester) async {
      // A list that draws its empty message during the load tells a lifter
      // with ten conversations that they have none. The transcript here never
      // answers, which is the only way to hold the screen in the state being
      // asserted -- a fake that resolves on the next microtask has already
      // passed through it by the first pump.
      await tester.pumpWidget(
        wrap(
          Scaffold(
            body: PastConversationsSheet(
              transcript: _NeverTranscript(),
              now: DateTime(2026, 8, 28),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Nothing here yet'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('reading one back', () {
    testWidgets('shows the turns and no composer', (tester) async {
      // Reopening an old transcript to write into it is exactly the endless
      // chat sessions exist to end, so there is nothing here to write with.
      await tester.pumpWidget(
        wrap(
          PastConversationScreen(
            transcript: FakeCoachTranscript(),
            summary: summary('lift:old', at: DateTime(2026, 8, 20)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Why has my bench stalled?'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.textContaining('starts a new one'), findsOneWidget);
    });
  });

  group('dayLabel', () {
    final now = DateTime(2026, 8, 28, 12);

    test('names today and yesterday rather than counting hours', () {
      // 11pm and 1am are twenty-six hours apart and are two different days. A
      // duration would call both "1d" and help nobody remember which evening.
      expect(dayLabel(DateTime(2026, 8, 28, 1), now), 'Today');
      expect(dayLabel(DateTime(2026, 8, 27, 23), now), 'Yesterday');
    });

    test('uses the weekday inside a week, and a date past it', () {
      expect(dayLabel(DateTime(2026, 8, 25), now), 'Tuesday');
      expect(dayLabel(DateTime(2026, 8, 10), now), '10 Aug');
    });
  });
}

/// The screen, with an opener so an empty transcript still has something on it.
Widget wrapScreen(CoachService coach, CoachTranscript transcript) =>
    CoachScreen(coach: coach, transcript: transcript);

/// A transcript that never answers, for the states that only exist while a read
/// is outstanding.
class _NeverTranscript implements CoachTranscript {
  @override
  Future<List<CoachTurn>> read(String conversationId) =>
      Completer<List<CoachTurn>>().future;

  @override
  Future<String?> openConversationId({Duration window = coachSessionWindow}) =>
      Completer<String?>().future;

  @override
  Future<List<CoachConversationSummary>> conversations({int limit = 20}) =>
      Completer<List<CoachConversationSummary>>().future;

  @override
  Future<List<CoachTurn>> fullTranscript(String conversationId) =>
      Completer<List<CoachTurn>>().future;
}
