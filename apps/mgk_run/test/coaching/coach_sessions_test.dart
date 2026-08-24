import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/coaching/data/coach_memory_repository.dart';
import 'package:mgk_run/src/features/coaching/data/coach_memory_store.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_memory.dart';
import 'package:mgk_run/src/features/coaching/presentation/chat_controller.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_button.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_conversation.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';
import 'package:mgk_ui/mgk_ui.dart';

/// A coach that answers and records what it was briefed with.
class _Chat implements CoachChatClient, CoachSummariseClient {
  final List<String> briefs = <String>[];
  int summaries = 0;

  @override
  Future<ChatTurn> chat({
    required String brief,
    required List<ChatMessage> history,
    required String message,
  }) async {
    briefs.add(brief);
    return const ChatTurn(reply: 'Noted.');
  }

  @override
  Future<String?> summarise({
    String? previous,
    required List<ChatMessage> transcript,
  }) async {
    summaries++;
    return 'They run before dawn.';
  }
}

void main() {
  // The whole of Phase 4 rests on one sentence from the first field test: asked
  // to look at a previous run, the coach answered "You ran 10 km in 60 minutes
  // yesterday" about a run logged through this chat a week earlier. Nothing was
  // invented — there was only ever one transcript, so week-old context was in
  // front of the model and read as current. See ADR-0025.
  group('a conversation is a session, not a lifetime', () {
    late InMemoryCoachMemoryStore store;
    late DateTime clock;
    late CoachMemoryRepository memory;
    late _Chat chat;
    var ids = 0;

    setUp(() {
      store = InMemoryCoachMemoryStore();
      clock = DateTime(2026, 8, 24, 7, 30);
      memory = CoachMemoryRepository(store: store, now: () => clock);
      chat = _Chat();
      ids = 0;
    });

    ChatController build() => ChatController(
      client: chat,
      brief: (_) async => 'a brief',
      memory: memory,
      summariser: chat,
      now: () => clock,
      newConversationId: () => 'c${ids++}',
    );

    test('reopening the app the next morning starts a new one', () async {
      final yesterday = build();
      await yesterday.send('My calf is tight on the outside.');
      final first = yesterday.conversationId;
      expect(first, isNotNull);

      // A second controller over the same store is a relaunch. Twenty-two
      // hours later.
      clock = DateTime(2026, 8, 25, 5, 30);
      final today = build();
      await today.restore();

      expect(
        today.messages,
        isEmpty,
        reason: 'a transcript from yesterday is not this morning\'s context',
      );
      await today.send('How am I doing?');
      expect(today.conversationId, isNot(first));
    });

    test('but coming straight back does not', () async {
      final before = build();
      await before.send('My calf is tight on the outside.');
      final first = before.conversationId;

      // Ten seconds in the notification centre, or a force-quit and a relaunch.
      clock = clock.add(const Duration(seconds: 10));
      final after = build();
      await after.restore();

      expect(after.messages.first.text, 'My calf is tight on the outside.');
      await after.send('It is still sore.');
      expect(
        after.conversationId,
        first,
        reason: 'the gap decides, not the fact of having been away',
      );
    });

    test('and neither does carrying on within one', () async {
      final controller = build();
      await controller.send('My calf is tight.');
      final first = controller.conversationId;

      clock = clock.add(const Duration(minutes: 4));
      await controller.send('It eased off after a mile.');

      expect(controller.conversationId, first);
      expect(await memory.conversations(), hasLength(1));
    });

    test('closing the sheet folds the memory without ending the talk', () async {
      final controller = build();
      await controller.send('I work nights.');
      final first = controller.conversationId;

      // Closing the sheet is a fold, not a boundary — a runner who shuts it and
      // reopens it two minutes later has not changed the subject.
      await controller.endConversation();
      expect(chat.summaries, 1);

      clock = clock.add(const Duration(minutes: 2));
      await controller.send('Which is why I run before dawn.');

      expect(controller.conversationId, first);
      expect(await memory.conversations(), hasLength(1));
    });

    test('coming back after half an hour away ends it', () async {
      final controller = build();
      await controller.send('My calf is tight.');
      final first = controller.conversationId;

      clock = clock.add(const Duration(minutes: 45));
      expect(await controller.endStaleConversation(), isTrue);
      expect(controller.messages, isEmpty);

      await controller.send('New question.');
      expect(controller.conversationId, isNot(first));
      expect(await memory.conversations(), hasLength(2));
    });

    test('coming back after ten seconds away does not', () async {
      final controller = build();
      await controller.send('My calf is tight.');

      clock = clock.add(const Duration(seconds: 10));
      expect(await controller.endStaleConversation(), isFalse);
      expect(controller.messages, isNotEmpty);
    });

    test('a suggested question starts its own, mid-conversation', () async {
      final controller = build();
      await controller.send('My calf is tight on the outside.');
      final first = controller.conversationId;

      await controller.ask('How has my training been going?');

      expect(controller.conversationId, isNot(first));
      expect(
        controller.messages.map((m) => m.text),
        isNot(contains('My calf is tight on the outside.')),
        reason: 'a chip raises its own subject rather than continuing one',
      );
      expect(await memory.conversations(), hasLength(2));
    });

    // The property the fold slice buys: two folds in one conversation must not
    // show the summariser the same turn twice.
    test('a second fold sees only what was said since the first', () async {
      final summariser = _Recorder();
      final controller = ChatController(
        client: chat,
        brief: (_) async => 'a brief',
        memory: memory,
        summariser: summariser,
        now: () => clock,
        newConversationId: () => 'c${ids++}',
      );
      await controller.send('One.');
      await controller.endConversation();
      clock = clock.add(const Duration(minutes: 2));
      await controller.send('Two.');
      await controller.endConversation();

      expect(summariser.calls, 2);
      expect(
        summariser.transcripts.last.map((m) => m.text),
        isNot(contains('One.')),
      );
      expect(summariser.transcripts.last.map((m) => m.text), contains('Two.'));
    });
  });

  group('previous conversations are kept and readable', () {
    test('they are listed newest first, with what opened them', () async {
      final store = InMemoryCoachMemoryStore();
      final memory = CoachMemoryRepository(store: store);

      await store.appendTurn(
        conversationId: 'older',
        role: CoachRole.user,
        text: 'I have entered a half in April.',
        at: DateTime(2026, 8, 10, 9),
      );
      await store.appendTurn(
        conversationId: 'older',
        role: CoachRole.assistant,
        text: 'Good. We will build to it.',
        at: DateTime(2026, 8, 10, 9, 1),
      );
      await store.appendTurn(
        conversationId: 'newer',
        role: CoachRole.user,
        text: 'My calf is tight.',
        at: DateTime(2026, 8, 20, 7),
      );

      final listed = await memory.conversations();
      expect(listed.map((c) => c.id), <String>['newer', 'older']);
      expect(listed.last.opening, 'I have entered a half in April.');
      expect(listed.last.turns, 2);
      expect(listed.last.lastTurnAt, DateTime(2026, 8, 10, 9, 1));
    });

    test('and read back in the order they were spoken', () async {
      final store = InMemoryCoachMemoryStore();
      final memory = CoachMemoryRepository(store: store);
      final controller = ChatController(
        client: _Chat(),
        brief: (_) async => '',
        memory: memory,
      );

      await store.appendTurn(
        conversationId: 'old',
        role: CoachRole.user,
        text: 'I have entered a half in April.',
        at: DateTime(2026, 8, 10, 9),
      );
      await store.appendTurn(
        conversationId: 'old',
        role: CoachRole.assistant,
        text: 'Good. We will build to it.',
        at: DateTime(2026, 8, 10, 9, 1),
      );

      final read = await controller.readBack('old');
      expect(read.map((t) => t.text), <String>[
        'I have entered a half in April.',
        'Good. We will build to it.',
      ]);
      expect(
        read.first.isUser,
        isTrue,
        reason: 'who said what has to survive the read-back',
      );
    });

    test('the live conversation is not one of them', () async {
      final store = InMemoryCoachMemoryStore();
      final memory = CoachMemoryRepository(store: store);
      final controller = ChatController(
        client: _Chat(),
        brief: (_) async => '',
        memory: memory,
        newConversationId: () => 'live',
      );

      await store.appendTurn(
        conversationId: 'old',
        role: CoachRole.user,
        text: 'Last week.',
        at: DateTime(2026, 8, 10, 9),
      );
      await controller.send('This morning.');

      final past = await controller.pastConversations();
      expect(past.map((c) => c.id), <String>['old']);
    });
  });

  group('the shell, end to end', () {
    Future<void> pump(
      WidgetTester tester,
      InMemoryCoachMemoryStore store,
      _Chat coach,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: HomeShell(
            auth: FakeAuthRepository(signedIn: true, email: 'dev@runio.app'),
            historySource: () async => const <RunSummary>[],
            chatClient: coach,
            memoryStore: store,
            initialTab: 1,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a launch a week later opens on nothing, and keeps the week', (
      tester,
    ) async {
      final store = InMemoryCoachMemoryStore();
      final aWeekAgo = DateTime.now().subtract(const Duration(days: 7));
      await store.appendTurn(
        conversationId: 'last-week',
        role: CoachRole.user,
        text: 'I ran 10k in 60 minutes this morning.',
        at: aWeekAgo,
      );
      await store.appendTurn(
        conversationId: 'last-week',
        role: CoachRole.assistant,
        text: 'Logged. Nice one.',
        at: aWeekAgo.add(const Duration(seconds: 30)),
      );

      await pump(tester, store, _Chat());
      await tester.tap(find.byType(CoachButton));
      await tester.pumpAndSettle();

      expect(
        find.text('I ran 10k in 60 minutes this morning.'),
        findsNothing,
        reason: 'this is the sentence that became "you ran 10 km yesterday"',
      );

      // Kept, though. It is one tap away rather than in front of the model.
      await tester.tap(find.byTooltip('Previous conversations'));
      await tester.pumpAndSettle();
      expect(
        find.text('I ran 10k in 60 minutes this morning.'),
        findsOneWidget,
      );

      // And readable, in full.
      await tester.tap(find.text('I ran 10k in 60 minutes this morning.'));
      await tester.pumpAndSettle();
      expect(find.text('Logged. Nice one.'), findsOneWidget);
      expect(
        find.textContaining('has ended'),
        findsOneWidget,
        reason: 'a page with no composer has to say why',
      );
    });

    // `recall` was built with the memory and never called by anything. This is
    // the wiring test for it: an old conversation reaches the brief when it is
    // relevant, dated, and without the whole transcript coming with it.
    testWidgets('an old conversation reaches the brief when it is asked '
        'about', (tester) async {
      final store = InMemoryCoachMemoryStore();
      final coach = _Chat();
      final lastMonth = DateTime.now().subtract(const Duration(days: 30));
      await store.appendTurn(
        conversationId: 'last-month',
        role: CoachRole.user,
        text: 'My calf tightens on the faster sessions.',
        at: lastMonth,
      );
      await store.appendTurn(
        conversationId: 'last-month',
        role: CoachRole.assistant,
        text: 'Then we keep the threshold work honest rather than hard.',
        at: lastMonth.add(const Duration(seconds: 30)),
      );

      await pump(tester, store, coach);
      await tester.tap(find.byType(CoachButton));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Is my calf a problem?');
      await tester.tap(find.byIcon(Icons.arrow_upward).last);
      await tester.pumpAndSettle();

      final brief = coach.briefs.single;
      expect(
        brief,
        contains('My calf tightens on the faster sessions.'),
        reason: 'the point of recall: relevant, not recent',
      );
      expect(
        brief,
        contains('weeks ago, they said'),
        reason: 'undated is how a month-old remark becomes this morning',
      );
      expect(
        brief,
        isNot(contains('Then we keep the threshold work honest')),
        reason: 'the coach\'s own past answers are conclusions, not evidence',
      );
      expect(
        'Is my calf a problem?'.allMatches(brief).length,
        0,
        reason: 'the live conversation is already the history it is sent',
      );
    });

    /// Mounts the sheet on its own, so the controller under test is one this
    /// test holds and can read [ChatController.openRequests] off.
    Future<ChatController> pumpSheet(WidgetTester tester) async {
      final controller = ChatController(
        client: _Chat(),
        brief: (_) async => '',
        memory: CoachMemoryRepository(store: InMemoryCoachMemoryStore()),
      );
      addTearDown(controller.dispose);
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Scaffold(
            body: CoachConversationSheet(
              controller: controller,
              suggestions: const <String>['How has my training been going?'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return controller;
    }

    testWidgets('a tapped suggestion is a hand-off, not a composed message', (
      tester,
    ) async {
      final controller = await pumpSheet(tester);

      await tester.tap(find.text('How has my training been going?'));
      await tester.pumpAndSettle();

      expect(find.text('Noted.'), findsOneWidget);
      expect(
        controller.openRequests.value,
        1,
        reason:
            'a chip goes through ask(), which starts a session; send() '
            'would leave this at zero',
      );
    });

    testWidgets('a typed message does not', (tester) async {
      final controller = await pumpSheet(tester);

      await tester.enterText(find.byType(TextField), 'How am I doing?');
      await tester.tap(find.byIcon(Icons.arrow_upward).last);
      await tester.pumpAndSettle();

      expect(find.text('Noted.'), findsOneWidget);
      expect(controller.openRequests.value, 0);
    });
  });

  group('what recall is allowed to hand the coach', () {
    CoachTurn turn(String id, CoachRole role, String text) => CoachTurn(
      conversationId: id,
      seq: 0,
      role: role,
      text: text,
      at: DateTime(2026, 8, 10),
    );

    test('the conversation being had is dropped', () {
      final kept = recollectionsFrom(<CoachTurn>[
        turn('live', CoachRole.user, 'said just now'),
        turn('old', CoachRole.user, 'said last week'),
      ], exceptConversation: 'live');

      expect(kept.map((t) => t.text), <String>['said last week']);
    });

    test('so are the coach\'s own past answers', () {
      final kept = recollectionsFrom(<CoachTurn>[
        turn('old', CoachRole.assistant, 'You are ready for a half.'),
        turn('old', CoachRole.user, 'I am worried about the distance.'),
      ]);

      expect(kept.map((t) => t.text), <String>[
        'I am worried about the distance.',
      ]);
    });

    test('and it is small', () {
      final kept = recollectionsFrom(<CoachTurn>[
        for (var i = 0; i < 20; i++) turn('old', CoachRole.user, 'line $i'),
      ]);
      expect(kept, hasLength(4));
    });
  });
}

/// A summariser that records what it was handed.
class _Recorder implements CoachSummariseClient {
  final List<List<ChatMessage>> transcripts = <List<ChatMessage>>[];
  int calls = 0;

  @override
  Future<String?> summarise({
    String? previous,
    required List<ChatMessage> transcript,
  }) async {
    calls++;
    transcripts.add(transcript);
    return 'A summary.';
  }
}
