import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/coaching/data/coach_errors.dart';
import 'package:mgk_run/src/features/coaching/presentation/chat_controller.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_conversation.dart';

/// A chat backend under the test's control: it records what it was asked and
/// answers with whatever the test queued.
class _ScriptedChat implements CoachChatClient {
  _ScriptedChat(this.turns);

  final List<ChatTurn> turns;

  final List<String> briefs = <String>[];
  final List<List<ChatMessage>> histories = <List<ChatMessage>>[];
  final List<String> messages = <String>[];

  int _i = 0;

  @override
  Future<ChatTurn> chat({
    required String brief,
    required List<ChatMessage> history,
    required String message,
  }) async {
    briefs.add(brief);
    histories.add(history);
    messages.add(message);
    return turns[_i++ % turns.length];
  }
}

/// A backend that refuses because the runner has spent their allowance.
class _LimitedChat implements CoachChatClient {
  @override
  Future<ChatTurn> chat({
    required String brief,
    required List<ChatMessage> history,
    required String message,
  }) async => throw const CoachLimitException(
    scope: 'daily_requests',
    retryAfterSeconds: 120,
    spendCapped: false,
  );
}

/// A backend that fails in an unremarkable way.
class _BrokenChat implements CoachChatClient {
  @override
  Future<ChatTurn> chat({
    required String brief,
    required List<ChatMessage> history,
    required String message,
  }) async => throw StateError('socket closed');
}

void main() {
  group('the wire', () {
    test('an ordinary reply carries no intent', () {
      final turn = chatTurnFromResponse(<String, dynamic>{
        'reply': 'Around 1:42 off that 5k.',
        'intent': null,
      });

      expect(turn.reply, 'Around 1:42 off that 5k.');
      expect(turn.intent, isNull);
    });

    test('an adapt_week intent arrives as words, not as a plan edit', () {
      final turn = chatTurnFromResponse(<String, dynamic>{
        'reply': "Let's take Tuesday off.",
        'intent': <String, dynamic>{
          'kind': 'adapt_week',
          'request': "can't run Tuesday",
        },
      });

      expect(turn.intent, isNotNull);
      expect(turn.intent!.isAdaptWeek, isTrue);
      expect(turn.intent!.request, "can't run Tuesday");
    });

    // The model may propose; it may not invent the vocabulary it proposes in.
    // An action the app does not understand has to do nothing at all, rather
    // than the nearest thing the app *does* understand.
    test('an intent the app does not know is no intent', () {
      for (final raw in <Object?>[
        <String, dynamic>{'kind': 'delete_plan', 'request': 'start over'},
        <String, dynamic>{'kind': 'adapt_week'},
        <String, dynamic>{'kind': 'adapt_week', 'request': '   '},
        <String, dynamic>{'kind': 'adapt_week', 'request': 42},
        'adapt_week',
        <String>['adapt_week'],
      ]) {
        final turn = chatTurnFromResponse(<String, dynamic>{
          'reply': 'ok',
          'intent': raw,
        });
        expect(turn.intent, isNull, reason: 'intent from $raw');
      }
    });

    test('a missing reply is empty, not a crash', () {
      expect(chatTurnFromResponse(const <String, dynamic>{}).reply, isEmpty);
    });
  });

  group('a turn', () {
    test('round-trips: the runner speaks, the coach answers', () async {
      final backend = _ScriptedChat(<ChatTurn>[
        const ChatTurn(reply: 'Around 1:42, and coming down.'),
      ]);
      final controller = ChatController(
        client: backend,
        brief: (_) async => 'They are in week 3 of 16 of a 21 km block.',
      );
      addTearDown(controller.dispose);

      expect(controller.isEmpty, isTrue);
      await controller.send('  What could I run a half in?  ');

      expect(controller.messages.map((m) => m.text).toList(), <String>[
        'What could I run a half in?',
        'Around 1:42, and coming down.',
      ]);
      expect(controller.messages.first.isUser, isTrue);
      expect(controller.messages.last.role, 'coach');
      expect(controller.isBusy, isFalse);
      expect(controller.error, isNull);
    });

    // The brief is what makes the coach *this runner's* coach. It is written
    // per turn rather than once, because a run recorded between two questions
    // has to change the answer to the second.
    test(
      'carries the brief, and the history without the new message',
      () async {
        final backend = _ScriptedChat(<ChatTurn>[
          const ChatTurn(reply: 'one'),
          const ChatTurn(reply: 'two'),
        ]);
        var writes = 0;
        final controller = ChatController(
          client: backend,
          brief: (_) async => 'brief #${++writes}',
        );
        addTearDown(controller.dispose);

        await controller.send('first');
        await controller.send('second');

        expect(backend.briefs, <String>['brief #1', 'brief #2']);
        expect(backend.messages, <String>['first', 'second']);
        expect(backend.histories.first, isEmpty);
        expect(
          backend.histories.last.map((m) => '${m.role}:${m.text}').toList(),
          <String>['user:first', 'coach:one'],
          reason: 'the message being sent travels separately from the history',
        );
      },
    );

    // A brief is context, not a precondition — losing it should cost the coach
    // some detail, not cost the runner their question.
    test('survives a brief that cannot be written', () async {
      final backend = _ScriptedChat(<ChatTurn>[const ChatTurn(reply: 'ok')]);
      final controller = ChatController(
        client: backend,
        brief: (_) async => throw StateError('the plan store is unreadable'),
      );
      addTearDown(controller.dispose);

      await controller.send('hello');

      expect(backend.briefs, <String>['']);
      expect(controller.messages.last.text, 'ok');
      expect(controller.error, isNull);
    });

    // "Try again" is useless advice when a second attempt is certain to be
    // refused too. The runner has to be told what actually happened.
    test(
      'a rate-limited turn gives the real reason, not a generic one',
      () async {
        final controller = ChatController(
          client: _LimitedChat(),
          brief: (_) async => '',
        );
        addTearDown(controller.dispose);

        await controller.send('how am I doing?');

        expect(
          controller.error,
          "That's a lot of coaching in a short time. Try again in 2 minutes.",
        );
        expect(
          controller.messages.single.text,
          'how am I doing?',
          reason: 'the question they asked survives the refusal',
        );
        expect(
          controller.canSend,
          isTrue,
          reason: 'they can send it again once the window clears',
        );
      },
    );

    test('an unexpected failure still says something human', () async {
      final controller = ChatController(
        client: _BrokenChat(),
        brief: (_) async => '',
      );
      addTearDown(controller.dispose);

      await controller.send('hi');

      expect(controller.error, 'The coach hit a problem. Please try again.');
      expect(controller.error, isNot(contains('socket')));
    });
  });

  group('an adapt_week intent', () {
    test('is handed over as words, after the reply is on screen', () async {
      final backend = _ScriptedChat(<ChatTurn>[
        const ChatTurn(
          reply: "Let's not push through that.",
          intent: CoachIntent(
            kind: CoachIntent.adaptWeek,
            request: 'move Tuesday to Wednesday',
          ),
        ),
      ]);
      final handed = <String>[];
      var transcriptWhenHanded = 0;
      late final ChatController controller;
      controller = ChatController(
        client: backend,
        brief: (_) async => '',
        onAdaptRequest: (request) async {
          handed.add(request);
          transcriptWhenHanded = controller.messages.length;
          return null;
        },
      );
      addTearDown(controller.dispose);

      await controller.send('my calf is sore');

      expect(handed, <String>['move Tuesday to Wednesday']);
      expect(
        transcriptWhenHanded,
        2,
        reason: 'the coach has already answered before the change is proposed',
      );
    });

    test('an ordinary turn hands over nothing', () async {
      final backend = _ScriptedChat(<ChatTurn>[
        const ChatTurn(reply: 'Steady week.'),
      ]);
      var handed = 0;
      final controller = ChatController(
        client: backend,
        brief: (_) async => '',
        onAdaptRequest: (_) async {
          handed++;
          return null;
        },
      );
      addTearDown(controller.dispose);

      await controller.send('how was my week?');

      expect(handed, 0);
    });
  });

  group('the conversation sheet', () {
    Future<ChatController> pump(
      WidgetTester tester, {
      List<ChatTurn>? turns,
      List<String> suggestions = const <String>[],
      CoachChatClient? client,
    }) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final controller = ChatController(
        client:
            client ??
            _ScriptedChat(turns ?? <ChatTurn>[const ChatTurn(reply: 'hi')]),
        brief: (_) async => '',
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: CoachButton(
                  onTap: () => CoachConversationSheet.show(
                    context,
                    controller: controller,
                    suggestions: suggestions,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return controller;
    }

    // The mark is the way in, and it is the only thing spent at rest. The dock
    // it replaces cost 76px of every screen it was on and could only be on one.
    testWidgets('the mark opens it, and nothing before that', (tester) async {
      await pump(tester);

      expect(find.byType(CoachConversationSheet), findsNothing);
      expect(find.text('C'), findsOneWidget);

      await tester.tap(find.byType(CoachButton));
      await tester.pumpAndSettle();

      expect(find.byType(CoachConversationSheet), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('with no coach it says so rather than offering a dead field', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: CoachButton(
                  onTap: () =>
                      CoachConversationSheet.show(context, controller: null),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(CoachButton));
      await tester.pumpAndSettle();

      expect(find.textContaining('unavailable'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('opens on openers, not on instructions', (tester) async {
      await pump(
        tester,
        suggestions: const <String>[
          'How has my training been going?',
          'What could I run a half marathon in?',
        ],
      );
      await tester.tap(find.byType(CoachButton));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('can see your plan and your recent runs'),
        findsOneWidget,
      );
      expect(find.text('How has my training been going?'), findsOneWidget);
    });

    testWidgets('a suggestion is sent as the runner having said it', (
      tester,
    ) async {
      final controller = await pump(
        tester,
        suggestions: const <String>['How has my training been going?'],
      );
      await tester.tap(find.byType(CoachButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('How has my training been going?'));
      await tester.pumpAndSettle();

      expect(controller.messages.first.isUser, isTrue);
      expect(controller.messages.first.text, 'How has my training been going?');
    });

    testWidgets('a refusal is shown in the conversation, in its own words', (
      tester,
    ) async {
      await pump(tester, client: _LimitedChat());
      await tester.tap(find.byType(CoachButton));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'how am I doing?');
      await tester.tap(find.byIcon(Icons.arrow_upward).last);
      await tester.pumpAndSettle();

      // The real reason, not "something went wrong" — rephrasing cannot help a
      // spent allowance.
      expect(find.textContaining('a lot of coaching'), findsOneWidget);
      expect(find.text('how am I doing?'), findsOneWidget);
    });

    testWidgets('the coach opens on what it had noticed', (tester) async {
      final controller = await pump(tester);
      await tester.tap(find.byType(CoachButton));
      await tester.pumpAndSettle();
      await controller.openWithNote('Longest one yet.');
      await tester.pumpAndSettle();

      expect(find.text('Longest one yet.'), findsOneWidget);
    });
  });
}
