import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/preview/fake_coach_service.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_access.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_gate_sheet.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';
import 'package:mgk_run/src/features/coaching/domain/ai_consent.dart';
import 'package:mgk_run/src/features/legal/domain/disclaimer_store.dart';

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
          // Already agreed, and the disclaimer already read: what the coach
          // asks before it sends anything is pinned in
          // the_coach_asks_before_anything_leaves_test.dart.
          aiConsent: InMemoryAiConsentStore.granted(),
          disclaimer: InMemoryDisclaimerStore(acknowledged: true),
          // Pinned, because this drives a coach hand-off and the coach is
          // the paid half (ADR-0030). It ran unpinned -- therefore `free` --
          // until 2026-09-04, when the gate moved into `_askCoach`: five
          // tests were exercising six ungated doors into the paid product,
          // which is how the hole survived review.
          access: CoachAccess.subscribed,
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
          aiConsent: InMemoryAiConsentStore.granted(),
          disclaimer: InMemoryDisclaimerStore(acknowledged: true),
          // Pinned, because this drives a coach hand-off and the coach is
          // the paid half (ADR-0030). It ran unpinned -- therefore `free` --
          // until 2026-09-04, when the gate moved into `_askCoach`: five
          // tests were exercising six ungated doors into the paid product,
          // which is how the hole survived review.
          access: CoachAccess.subscribed,
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
          aiConsent: InMemoryAiConsentStore.granted(),
          disclaimer: InMemoryDisclaimerStore(acknowledged: true),
          // Pinned, because this drives a coach hand-off and the coach is
          // the paid half (ADR-0030). It ran unpinned -- therefore `free` --
          // until 2026-09-04, when the gate moved into `_askCoach`: five
          // tests were exercising six ungated doors into the paid product,
          // which is how the hole survived review.
          access: CoachAccess.subscribed,
          auth: FakeAuthRepository(signedIn: true, email: 'dev@runio.app'),
          historySource: () async => runs(),
          initialTab: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ask about this'), findsNothing);
  });

  /// **The hand-off is the paid half, and for a month it was not gated.**
  ///
  /// `_openCoach` checked the tier. `_askCoach` did not, and six callers
  /// reached it: adjust-this-week, the plan-finish screen, ask-about-this-run
  /// from a finished run and from the log, the missed-session card, the Plan
  /// tab and Profile. A free runner taking any of them opened a conversation
  /// onto an Edge Function 402, rendered as *"The coach hit a problem. Please
  /// try again."* -- untrue, unactionable, and the exact sentence
  /// `CoachGateSheet` exists to replace (ADR-0030).
  ///
  /// It is asserted here rather than at each call site on purpose. Six tests
  /// each pinning their own door would leave the seventh caller unguarded,
  /// which is how this happened; the check now lives in `_askCoach` itself, and
  /// this proves a free runner meets the door instead of the failure.
  testWidgets('a free runner asking from Profile meets the door, not a 402', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final chat = _RecordingChat();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          aiConsent: InMemoryAiConsentStore.granted(),
          disclaimer: InMemoryDisclaimerStore(acknowledged: true),
          access: CoachAccess.free,
          auth: FakeAuthRepository(signedIn: true, email: 'dev@runio.app'),
          historySource: () async => runs(),
          coach: FakeCoachService(),
          chatClient: chat,
          initialTab: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The affordance is offered to a free runner -- `ProfileScreen.onAskCoach`
    // is passed unconditionally -- which is the point: the door has to hold,
    // because the handle is visible.
    expect(find.text('Ask about this'), findsOneWidget);
    await tester.tap(find.text('Ask about this'));
    await tester.pumpAndSettle();

    expect(find.byType(CoachGateSheet), findsOneWidget);
    expect(
      chat.asked,
      isEmpty,
      reason: 'nothing may reach the coach before it has been paid for',
    );
  });
  testWidgets('a free runner asking for a plan meets the door, not a 402', (
    tester,
  ) async {
    // **The second half of D14, and it was never behind `_askCoach` at all.**
    //
    // Building a plan pushes `CoachFlow`, which calls the model — `skeleton`
    // and `week` are the coach as much as `chat` is (ADR-0030). It was gated on
    // having an *account* and left the Edge Function to refuse afterwards, and
    // that 402 renders as "The coach hit a problem": a sentence that describes
    // a fault where the truth is a price.
    //
    // Signed in here, because that is the case the gate is for. A signed-*out*
    // runner meets sign-up first and always did — asserted in
    // `account_when_it_buys_something_test.dart`, and the order is deliberate:
    // naming the price first sounds fairer and dead-ends, because
    // `PurchaseScreen` refuses a signed-out buyer with "Sign in first" and
    // offers no way to do it.
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final chat = _RecordingChat();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          aiConsent: InMemoryAiConsentStore.granted(),
          disclaimer: InMemoryDisclaimerStore(acknowledged: true),
          access: CoachAccess.free,
          auth: FakeAuthRepository(signedIn: true, email: 'dev@runio.app'),
          historySource: () async => runs(),
          coach: FakeCoachService(),
          chatClient: chat,
          initialTab: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Build a plan'), findsOneWidget);
    await tester.tap(find.text('Build a plan'));
    await tester.pumpAndSettle();

    expect(find.byType(CoachGateSheet), findsOneWidget);
    expect(
      find.text('Build a plan'),
      findsOneWidget,
      reason: 'the Plan tab is still behind the door, not replaced by a flow',
    );
  });
}
