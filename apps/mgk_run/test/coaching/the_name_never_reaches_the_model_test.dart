import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/core/database/app_database.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_access.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_brief.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_button.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_run/src/features/coaching/domain/ai_consent.dart';
import 'package:mgk_run/src/features/legal/domain/disclaimer_store.dart';

/// The published privacy policy makes an unconditional promise:
///
/// > We never send your **name, email, or account identifier**
///
/// It is live at mgkfitness.mgkcodes.com/run/privacy, pinned by CI, and said
/// again to the runner's face in Settings by `legal_copy.dart`. It was also
/// false: `CoachBrief` led with `The runner is called <name>.` and the brief
/// goes into the system prompt verbatim, so every coach turn sent a first name
/// the runner gave at sign-up to OpenRouter and on to a model provider.
///
/// ## Why this test drives the shell rather than calling `CoachBrief.write`
///
/// The parameter is gone, so a unit test cannot pass a name and there is
/// nothing for it to assert. That absence is the real guarantee — but it only
/// holds while nothing *else* carries a name into the brief, and the brief is
/// assembled from six sources in `_writeCoachBrief`.
///
/// So this stands where the argument is actually passed: a signed-in runner
/// **who has a name**, a real conversation opened the way a runner opens it,
/// and the brief captured as the chat client receives it. That is the same
/// lesson four defects in this release taught — a widget cannot test the
/// argument its caller declined to pass, and here we need the opposite: proof
/// that a caller with a name to hand does not pass it.
class _BriefCapturingChat implements CoachChatClient {
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

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  testWidgets('a runner with a name does not send it to the model', (
    tester,
  ) async {
    final chat = _BriefCapturingChat();

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          // Already agreed, and the disclaimer already read: what the coach
          // asks before it sends anything is pinned in
          // the_coach_asks_before_anything_leaves_test.dart.
          aiConsent: InMemoryAiConsentStore.granted(),
          disclaimer: InMemoryDisclaimerStore(acknowledged: true),
          // Subscribed, because the coach is the paid half (ADR-0030) and an
          // unentitled runner never reaches a brief at all.
          access: CoachAccess.subscribed,
          // **The whole point of the fixture.** The runner told the app what to
          // call them, so the name is sitting on the session, one property
          // access away from the brief. That is the state the old code shipped.
          auth: FakeAuthRepository(
            signedIn: true,
            email: 'dev@mgkcodes.com',
            name: 'Sam',
          ),
          chatClient: chat,
          historySource: () async => <RunSummary>[
            RunSummary(
              startedAt: DateTime.now().subtract(const Duration(days: 2)),
              duration: const Duration(minutes: 41, seconds: 8),
              distanceMeters: 7400,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Opened the way a runner opens it. The mark rather than the reveal — see
    // `flows.dart`, which learned the same thing the hard way.
    await tester.tap(find.byType(CoachButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'How am I doing?');
    await tester.tap(find.byIcon(Icons.arrow_upward).last);
    await tester.pumpAndSettle();

    expect(
      chat.briefs,
      isNotEmpty,
      reason:
          'the turn has to actually happen for the assertion to mean '
          'anything — an empty list would pass every check below',
    );

    final brief = chat.briefs.single;
    expect(
      brief,
      isNot(contains('Sam')),
      reason: 'the published policy says we never send the runner name',
    );
    // The old rendering, matched separately so a failure says which half broke:
    // a reworded line carrying the name is the same violation.
    expect(brief.toLowerCase(), isNot(contains('called')));
  });

  test('and the brief has no way to be told one', () {
    // Belt and braces on the structural half. If somebody re-adds a `name`
    // parameter this still compiles — but the widget test above fails, which is
    // the pair working as intended.
    final brief = CoachBrief.write(recentRuns: const <RunSummary>[]).text;
    expect(brief.toLowerCase(), isNot(contains('called')));
  });
}
