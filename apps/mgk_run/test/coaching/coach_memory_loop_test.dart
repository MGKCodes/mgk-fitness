import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/coaching/data/coach_memory_repository.dart';
import 'package:mgk_run/src/features/coaching/data/coach_memory_store.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_memory.dart';
import 'package:mgk_run/src/features/coaching/presentation/chat_controller.dart';

/// A coach that answers, and records the brief it was handed.
class _Chat implements CoachChatClient {
  final List<String> briefs = <String>[];

  @override
  Future<ChatTurn> chat({
    required String brief,
    required List<ChatMessage> history,
    required String message,
  }) async {
    briefs.add(brief);
    return const ChatTurn(reply: 'Noted.');
  }
}

/// A summariser that records what it was given and answers with [reply].
class _Summariser implements CoachSummariseClient {
  _Summariser([this.reply = 'They work shifts and run before dawn.']);

  final String? reply;
  final List<String?> previous = <String?>[];
  final List<List<ChatMessage>> transcripts = <List<ChatMessage>>[];
  int calls = 0;

  @override
  Future<String?> summarise({
    String? previous,
    required List<ChatMessage> transcript,
  }) async {
    calls++;
    this.previous.add(previous);
    transcripts.add(transcript);
    return reply;
  }
}

void main() {
  late InMemoryCoachMemoryStore store;
  late CoachMemoryRepository memory;
  late _Chat chat;
  late _Summariser summariser;

  setUp(() {
    store = InMemoryCoachMemoryStore();
    memory = CoachMemoryRepository(store: store);
    chat = _Chat();
    summariser = _Summariser();
  });

  var ids = 0;
  ChatController build({
    CoachSummariseClient? summarise,
    Future<String> Function(String message)? brief,
  }) => ChatController(
    client: chat,
    brief: brief ?? (_) async => 'a brief',
    memory: memory,
    summariser: summarise ?? summariser,
    newConversationId: () => 'c${ids++}',
  );

  // The loop, end to end: said → stored → summarised → back in the brief.
  test('what is said comes back in the next conversation\'s brief', () async {
    final first = build();
    await first.send('I work nights, so I run before dawn.');
    await first.endConversation();

    // The summary is on disk, not just in the controller that wrote it.
    final stored = await memory.summary();
    expect(stored, isNotNull);
    expect(stored!.text, 'They work shifts and run before dawn.');
    expect(stored.turnsCovered, 2, reason: 'the question and the answer');

    // A brand new controller — a relaunch — briefs the coach with it.
    final second = build(
      brief: (_) async {
        final remembered = await memory.summary();
        return 'a brief\n\n${remembered?.text ?? ''}';
      },
    );
    await second.send('How am I doing?');

    expect(chat.briefs.last, contains('They work shifts and run before dawn.'));
  });

  test('every turn is on disk as it happens, not at the end', () async {
    final controller = build();
    await controller.send('My calf is sore.');

    final id = await memory.openConversationId();
    final turns = await memory.transcript(id!);
    expect(turns.map((t) => t.role).toList(), <CoachRole>[
      CoachRole.user,
      CoachRole.assistant,
    ]);
    expect(turns.first.text, 'My calf is sore.');
    expect(
      summariser.calls,
      0,
      reason: 'summarising per turn would spend the allowance in ten minutes',
    );
  });

  test('the dock reopens on what was already said', () async {
    final first = build();
    await first.send('I am worried about my knee.');

    final second = build();
    expect(second.messages, isEmpty);
    await second.restore();

    expect(second.messages.map((m) => m.text).toList(), <String>[
      'I am worried about my knee.',
      'Noted.',
    ]);
    expect(second.messages.first.isUser, isTrue);
  });

  test(
    'the previous memory is handed to the rewrite, not thrown away',
    () async {
      await memory.replaceSummary('They are training for a first marathon.');

      final controller = build();
      await controller.send('I have signed up for a half instead.');
      await controller.endConversation();

      expect(
        summariser.previous.single,
        'They are training for a first marathon.',
      );
    },
  );

  group('the summary is rewritten only when there is something to rewrite', () {
    test('a conversation with nothing said costs no call', () async {
      final controller = build();
      await controller.endConversation();
      expect(summariser.calls, 0);
    });

    test('ending twice costs one call', () async {
      final controller = build();
      await controller.send('Hello.');
      await controller.endConversation();
      await controller.endConversation();
      expect(summariser.calls, 1);
    });

    test(
      'a second fold is handed only what was said since the first',
      () async {
        final controller = build();
        await controller.send('One.');
        await controller.endConversation();
        await controller.send('Two.');
        await controller.endConversation();

        expect(summariser.calls, 2);
        expect(
          summariser.transcripts.last.map((m) => m.text),
          isNot(contains('One.')),
          reason:
              'a turn already folded into the memory is not folded in twice',
        );
      },
    );
  });

  group('a failed rewrite keeps what is already known', () {
    test('null leaves the existing summary standing', () async {
      await memory.replaceSummary('A knee that complains on hills.');

      final controller = build(summarise: _Summariser(null));
      await controller.send('Bad session today.');
      await controller.endConversation();

      final stored = await memory.summary();
      expect(stored!.text, 'A knee that complains on hills.');
    });

    test('an empty answer is not a reason to forget', () async {
      await memory.replaceSummary('A knee that complains on hills.');

      final controller = build(summarise: _Summariser(''));
      await controller.send('Morning.');
      await controller.endConversation();

      expect((await memory.summary())!.text, 'A knee that complains on hills.');
    });

    test('a rewrite that will not run is retried on the next close', () async {
      final failing = _Summariser(null);
      final controller = build(summarise: failing);
      await controller.send('One.');
      await controller.endConversation();
      expect(failing.calls, 1);

      // Still unsummarised, so closing again tries again rather than deciding
      // the conversation is dealt with.
      await controller.endConversation();
      expect(failing.calls, 2);
    });
  });

  // A conversation nobody had should not leave a row behind.
  test(
    'opening the coach and saying nothing creates no conversation',
    () async {
      build();
      expect(await memory.openConversationId(), isNull);
    },
  );

  // The dock shows what the coach has noticed. Tapping it used to open a blank
  // transcript, so the coach said something interesting and forgot it the
  // moment the runner engaged.
  group('the conversation opens on what the coach said', () {
    test('the observation becomes the first turn, and is kept', () async {
      final controller = build();
      await controller.openWithNote('Longest one yet. Recover properly.');

      expect(controller.entries, hasLength(1));
      expect(controller.entries.single.isUser, isFalse);
      expect(
        controller.entries.single.text,
        'Longest one yet. Recover properly.',
      );

      // Persisted, so a reply next launch is not stranded above the thing it
      // replies to.
      final id = await memory.openConversationId();
      expect((await memory.transcript(id!)).single.text, contains('Longest'));
    });

    test('the coach sees it as its own previous turn', () async {
      final controller = build();
      await controller.openWithNote('Longest one yet.');
      await controller.send('how should I follow that up?');

      expect(chat.briefs, hasLength(1));
      expect(controller.entries.first.text, 'Longest one yet.');
    });

    test('a conversation already under way is not interrupted', () async {
      final controller = build();
      await controller.send('hello');
      await controller.openWithNote('Longest one yet.');

      expect(
        controller.entries.map((e) => e.text),
        isNot(contains('Longest one yet.')),
      );
    });

    test('nor is a restored one', () async {
      final first = build();
      await first.send('I am worried about my knee.');

      final second = build();
      await second.restore();
      await second.openWithNote('Longest one yet.');

      expect(second.entries, hasLength(2));
      expect(
        second.entries.map((e) => e.text),
        isNot(contains('Longest one yet.')),
      );
    });

    test('an empty observation seeds nothing', () async {
      final controller = build();
      await controller.openWithNote('   ');
      expect(controller.entries, isEmpty);
    });
  });
}
