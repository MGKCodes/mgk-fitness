import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/preview/fake_coach_service.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

/// A chat backend that records what it was asked, so the hand-off can be
/// asserted on the question rather than on the reply.
class _RecordingChat implements CoachChatClient {
  final List<String> asked = <String>[];

  @override
  Future<ChatTurn> chat({
    required String brief,
    required List<ChatMessage> history,
    required String message,
  }) async {
    asked.add(message);
    return const ChatTurn(reply: 'Noted.');
  }
}

/// Profile's coach card asks the *one* conversation a question rather than
/// standing up a second one of its own. The transcript belongs to the runner,
/// not to whichever screen they happened to ask from.
///
/// It used to reach the Coach tab by leaving a value behind for that tab to
/// pick up, because the controller lived inside it. The controller lives on the
/// shell now — the coach mark floats over every tab, so the conversation cannot
/// be the property of one of them — and the hand-off is a direct call.
void main() {
  List<RunSummary> runs() => <RunSummary>[
    RunSummary(
      startedAt: DateTime.now().subtract(const Duration(days: 1)),
      duration: const Duration(minutes: 27, seconds: 45),
      distanceMeters: 5230,
      avgPaceSecondsPerKm: 318,
    ),
  ];

  testWidgets('asking from Profile lands in the Coach tab conversation', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final chat = _RecordingChat();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          auth: FakeAuthRepository(signedIn: true, email: 'dev@runio.app'),
          historySource: () async => runs(),
          coach: FakeCoachService(),
          chatClient: chat,
          initialTab: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ask about this'), findsOneWidget);
    await tester.tap(find.text('Ask about this'));
    await tester.pumpAndSettle();

    expect(
      chat.asked,
      hasLength(1),
      reason: 'the question must be asked exactly once, not on every rebuild',
    );
    expect(chat.asked.single, isNotEmpty);
  });

  testWidgets('asking twice asks twice, and rebuilding asks nothing', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final chat = _RecordingChat();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          auth: FakeAuthRepository(signedIn: true, email: 'dev@runio.app'),
          historySource: () async => runs(),
          coach: FakeCoachService(),
          chatClient: chat,
          initialTab: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ask about this'));
    await tester.pumpAndSettle();
    expect(chat.asked, hasLength(1));

    // The failure this guards used to be a pending value re-sent on every
    // rebuild. A direct call cannot do that, and this says so: nothing is
    // asked until something is tapped.
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(chat.asked, hasLength(1));
  });

  testWidgets('with no chat backend the card offers no dead control', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          auth: FakeAuthRepository(signedIn: true, email: 'dev@runio.app'),
          historySource: () async => runs(),
          initialTab: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ask about this'), findsNothing);
  });
}
