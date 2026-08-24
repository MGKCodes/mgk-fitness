import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_button.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/coaching/data/coach_memory_store.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

/// A coach that answers, remembers the brief, and can rewrite a memory.
///
/// Implements both seams on one object on purpose: [CoachService] does the same,
/// and the shell finds the summariser by asking whether the injected coach is
/// one. A double that split them would not exercise that.
class _RememberingCoach implements CoachChatClient, CoachSummariseClient {
  final List<String> briefs = <String>[];
  int summaries = 0;

  @override
  Future<ChatTurn> chat({
    required String brief,
    required List<ChatMessage> history,
    required String message,
  }) async {
    briefs.add(brief);
    return const ChatTurn(reply: 'Understood.');
  }

  @override
  Future<String?> summarise({
    String? previous,
    required List<ChatMessage> transcript,
  }) async {
    summaries++;
    return 'They run before dawn because of shift work.';
  }
}

void main() {
  /// Mounts the app on the Coach tab against [store], and opens the dock.
  Future<void> pump(
    WidgetTester tester,
    CoachMemoryStore store,
    _RememberingCoach coach,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Torn down first, so the second call is a *relaunch* rather than a
    // rebuild. Pumping the same widget type at the same position reuses its
    // State, which would skip initState and quietly test nothing.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

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

  /// Opens the dock, whether it is inviting a first word or offering to pick a
  /// conversation back up, and says [message].
  Future<void> say(WidgetTester tester, String message) async {
    await tester.tap(find.byType(CoachButton));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), message);
    await tester.tap(find.byIcon(Icons.arrow_upward).last);
    await tester.pumpAndSettle();
  }

  // The wiring test. The controller's own loop is covered in
  // coach_memory_loop_test; this proves the shell actually hands it a memory,
  // which is the part that was missing while every piece existed.
  testWidgets('a conversation survives a relaunch inside the session window', (
    tester,
  ) async {
    final store = InMemoryCoachMemoryStore();

    await pump(tester, store, _RememberingCoach());
    await say(tester, 'I work nights, so I run before dawn.');
    expect(find.text('Understood.'), findsOneWidget);

    // A second shell over the same store is a relaunch — and it happens
    // milliseconds later, so it is a force-quit and a restart rather than a new
    // day. That conversation is still open and is picked back up.
    //
    // The other side of this rule, a relaunch after the window has lapsed, is
    // in coach_sessions_test.
    await pump(tester, store, _RememberingCoach());
    await tester.tap(find.byType(CoachButton));
    await tester.pumpAndSettle();

    expect(
      find.text('I work nights, so I run before dawn.'),
      findsOneWidget,
      reason: 'the transcript is the runner\'s, not the launch\'s',
    );
    expect(find.text('Understood.'), findsOneWidget);
  });

  testWidgets('closing the sheet writes the memory, and it reaches the brief', (
    tester,
  ) async {
    final store = InMemoryCoachMemoryStore();
    final first = _RememberingCoach();

    await pump(tester, store, first);
    await say(tester, 'I work nights.');

    // Closing the sheet is what folds what was said into the rolling summary.
    // It no longer ends the conversation — that is the session window's job.
    await tester.tap(find.byTooltip('Close the conversation'));
    await tester.pumpAndSettle();
    expect(first.summaries, 1);

    final summary = await store.loadSummary();
    expect(summary, isNotNull);
    expect(summary!.text, 'They run before dawn because of shift work.');

    // The next conversation is briefed with it — the loop closed.
    final second = _RememberingCoach();
    await pump(tester, store, second);
    await say(tester, 'How am I doing?');

    expect(
      second.briefs.last,
      contains('They run before dawn because of shift work.'),
      reason: 'the rolling summary is the tier that is always loaded',
    );
  });

  testWidgets('a build with no memory store still talks', (tester) async {
    // The shell falls back to an in-memory store, so a coach with nowhere to
    // remember is a coach that forgets — never one that fails to answer.
    final coach = _RememberingCoach();
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          auth: FakeAuthRepository(signedIn: true, email: 'dev@runio.app'),
          historySource: () async => const <RunSummary>[],
          chatClient: coach,
          initialTab: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await say(tester, 'Hello.');
    expect(find.text('Understood.'), findsOneWidget);
  });
}
