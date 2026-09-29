import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/preview/fake_coach_service.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/coaching/data/entitlement_repository.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_access.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_subscription.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_gate_sheet.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/domain/ai_consent.dart';
import 'package:mgk_run/src/features/legal/domain/disclaimer_store.dart';

/// **D14 on the build 13 sheet, and the door was never the defect.**
///
/// The report was that Profile's *"Ask about this"* reached the coach on a free
/// account. Every door already routes through `_askCoach`, which checks the
/// tier, and `ask_coach_handoff_test.dart` pins exactly that and passes — so
/// the check was not what failed. **The tier it checked was stale.**
///
/// `_access` was resolved once in `initState` and otherwise re-read only after
/// an auth event or a purchase. Nothing re-read it on resume. The test sheet's
/// running order grants an entitlement row, works D1 to D13, deletes the row,
/// and then tries D14 — without relaunching, because nothing on the sheet says
/// to. The shell was still holding `subscribed`, and every door opened.
///
/// That is not only a test-sheet artefact: it is what a lapsed, refunded or
/// revoked subscription looks like to a runner who leaves the app open.
///
/// Asserted on the tier the shell draws with rather than on `_askCoach`, which
/// was already right.
void main() {
  List<RunSummary> runs() => <RunSummary>[
    RunSummary(
      startedAt: DateTime.now().subtract(const Duration(days: 1)),
      duration: const Duration(minutes: 27, seconds: 45),
      distanceMeters: 5230,
      avgPaceSecondsPerKm: 318,
    ),
  ];

  testWidgets('a withdrawn entitlement closes the door on the next resume', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // No `access:` pin — the point is the tier the shell resolves for itself.
    final entitlements = _MutableEntitlements(CoachAccess.subscribed);
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
          auth: FakeAuthRepository(signedIn: true, email: 'sam@example.com'),
          entitlements: entitlements,
          historySource: () async => runs(),
          coach: FakeCoachService(),
          chatClient: chat,
          initialTab: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Paid for: the question reaches the coach.
    await tester.tap(find.text('Ask about this'));
    await tester.pumpAndSettle();
    expect(find.byType(CoachGateSheet), findsNothing);
    expect(chat.asked, isNotEmpty);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // The row is deleted on the server while the app sits in the background.
    entitlements.answer = CoachAccess.free;
    chat.asked.clear();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ask about this'));
    await tester.pumpAndSettle();

    expect(
      find.byType(CoachGateSheet),
      findsOneWidget,
      reason: 'the tier was re-read when the app came back',
    );
    expect(
      chat.asked,
      isEmpty,
      reason: 'nothing may reach the coach once it is no longer paid for',
    );
  });

  testWidgets('a burst of resumes is one read, not one each', (tester) async {
    // The guard on the guard. Android hands `resumed` back for a
    // notification-shade pull, so this fires more often than a person would
    // guess; single-flight is what keeps that from becoming a request storm.
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final entitlements = _MutableEntitlements(CoachAccess.free);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          aiConsent: InMemoryAiConsentStore.granted(),
          disclaimer: InMemoryDisclaimerStore(acknowledged: true),
          auth: FakeAuthRepository(signedIn: true, email: 'sam@example.com'),
          entitlements: entitlements,
          historySource: () async => runs(),
          initialTab: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final int atLaunch = entitlements.reads;

    for (var i = 0; i < 5; i++) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    }
    await tester.pumpAndSettle();

    expect(entitlements.reads - atLaunch, lessThan(5));
  });
}

/// An entitlement the server can withdraw mid-session, which is the whole case.
class _MutableEntitlements implements EntitlementRepository {
  _MutableEntitlements(this.answer);

  CoachAccess answer;
  int reads = 0;

  @override
  Future<CoachAccess> access() async {
    reads++;
    return answer;
  }

  @override
  Future<CoachSubscription> subscription() async => answer.isSubscribed
      ? const CoachSubscription(
          tier: CoachTier.coach,
          standing: SubscriptionStanding.active,
        )
      : CoachSubscription.none;
}

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
