import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/preview/fake_auth_repository.dart';
import 'package:mgk_run/src/features/auth/presentation/sign_in_screen.dart';
import 'package:mgk_run/src/features/coaching/data/adaptation_service.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/coaching/data/plan_client.dart';
import 'package:mgk_run/src/features/coaching/domain/ai_consent.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_access.dart';
import 'package:mgk_run/src/features/coaching/domain/intake_conversation.dart';
import 'package:mgk_run/src/features/coaching/domain/intake_slots.dart';
import 'package:mgk_run/src/features/coaching/domain/pace_model.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/presentation/ai_consent_sheet.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_conversation.dart';
import 'package:mgk_run/src/features/coaching/presentation/coach_gate_sheet.dart';
import 'package:mgk_run/src/features/coaching/presentation/week_detail_screen.dart';
import 'package:mgk_run/src/features/home/presentation/home_shell.dart';
import 'package:mgk_run/src/features/legal/domain/disclaimer_store.dart';
import 'package:mgk_run/src/features/legal/presentation/medical_disclaimer_screen.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';
import 'package:mgk_ui/mgk_ui.dart';
import 'package:mgk_units/mgk_units.dart';

/// A coach that records every question it is sent, and every intake turn.
///
/// Both seams on one object, the way `CoachService` has them, so a test can
/// say "nothing was sent" about the whole coach rather than one surface of it.
class _RecordingCoach implements CoachClient, CoachChatClient {
  final List<String> asked = <String>[];
  int intakes = 0;

  int get sent => asked.length + intakes;

  @override
  Future<ChatTurn> chat({
    required String brief,
    required List<ChatMessage> history,
    required String message,
  }) async {
    asked.add(message);
    return const ChatTurn(reply: 'Noted.');
  }

  @override
  Future<IntakeTurn> intake({
    required IntakeSlots slots,
    required List<IntakeMessage> history,
  }) async {
    intakes++;
    return const IntakeTurn(
      reply: 'What are you training for?',
      extracted: IntakeSlots(),
    );
  }
}

/// A plan client that counts what it was asked to adapt.
class _CountingPlanClient implements PlanClient {
  int adaptations = 0;

  @override
  Future<TrainingWeek?> proposeAdaptation({
    required TrainingWeek week,
    required SkeletonWeek slot,
    required RunnerProfile profile,
    required String request,
  }) async {
    adaptations++;
    return null;
  }

  @override
  Future<PlanSkeleton?> proposeSkeleton({
    required RunnerProfile profile,
    List<String> violations = const <String>[],
  }) async => null;

  @override
  Future<TrainingWeek?> proposeWeek({
    required SkeletonWeek slot,
    required RunnerProfile profile,
    List<String> violations = const <String>[],
    int? raceWeekday,
  }) async => null;
}

/// **Nothing reaches the AI provider before the runner has said it may.**
///
/// Every way into the coach sent first and asked nobody: the mark opened the
/// conversation, "Build a plan" started an intake that sends on its first
/// frame, and each "ask the coach" called `chat.ask` with no screen in
/// between, carrying dated runs and paces, the plan and the rolling summary.
/// The privacy policy meanwhile named consent as the lawful basis.
///
/// The order these pin, on every entry: an account, then the permission, then
/// the price, then the coach. The permission sits before the price so nobody
/// pays for a coach and then declines to let it see their training.
void main() {
  List<RunSummary> runs() => <RunSummary>[
    RunSummary(
      startedAt: DateTime.now().subtract(const Duration(days: 1)),
      duration: const Duration(minutes: 27, seconds: 45),
      distanceMeters: 5230,
      avgPaceSecondsPerKm: 318,
    ),
  ];

  late _RecordingCoach coach;
  late FakeAuthRepository auth;
  late InMemoryAiConsentStore consent;
  late InMemoryDisclaimerStore disclaimer;

  setUp(() {
    coach = _RecordingCoach();
    auth = FakeAuthRepository(signedIn: true, email: 'sam@example.com');
    // Keyed on whoever the fake says is signed in, so switching accounts is a
    // real switch.
    consent = InMemoryAiConsentStore(userId: () => auth.currentUserId);
    disclaimer = InMemoryDisclaimerStore(acknowledged: true);
  });

  Future<void> pumpShell(
    WidgetTester tester, {
    CoachAccess access = CoachAccess.subscribed,
    int tab = 0,
    bool withRuns = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(420, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: HomeShell(
          access: access,
          auth: auth,
          historySource: () async => withRuns ? runs() : const <RunSummary>[],
          coach: coach,
          aiConsent: consent,
          disclaimer: disclaimer,
          initialTab: tab,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder sheet() => find.byType(AiConsentSheet);
  Finder conversation() => find.byType(CoachConversationSheet);

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text).last);
    await tester.pumpAndSettle();
  }

  group('the coach mark', () {
    testWidgets('asks before the conversation opens, and "Not now" sends '
        'nothing', (tester) async {
      await pumpShell(tester);

      await tester.tap(find.byType(CoachButton));
      await tester.pumpAndSettle();

      expect(sheet(), findsOneWidget);
      expect(conversation(), findsNothing);

      await tapText(tester, AiConsentSheet.notNowLabel);

      expect(sheet(), findsNothing);
      expect(conversation(), findsNothing);
      expect(await consent.isGranted(), isFalse);
      expect(coach.sent, 0);
    });

    testWidgets('opens once they agree, and does not ask that account again', (
      tester,
    ) async {
      await pumpShell(tester);

      await tester.tap(find.byType(CoachButton));
      await tester.pumpAndSettle();
      await tapText(tester, AiConsentSheet.agreeLabel);

      expect(conversation(), findsOneWidget);
      final kept = consent.answerFor('fake-user');
      expect(kept, isNotNull);
      expect(kept!.version, kAiConsentVersion);

      await tester.tap(find.byTooltip('Close the conversation'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CoachButton));
      await tester.pumpAndSettle();

      expect(sheet(), findsNothing, reason: 'asked once per account');
      expect(conversation(), findsOneWidget);
    });

    testWidgets('asks again for a different account on the same phone', (
      tester,
    ) async {
      consent.seed('fake-user', AiConsent.now(DateTime.now()));
      auth.userId = 'somebody-else';
      await pumpShell(tester);

      await tester.tap(find.byType(CoachButton));
      await tester.pumpAndSettle();

      expect(sheet(), findsOneWidget);
    });

    testWidgets('asks again once the answer has been withdrawn', (
      tester,
    ) async {
      consent.seed('fake-user', AiConsent.now(DateTime.now()));
      await consent.withdraw();
      await pumpShell(tester);

      await tester.tap(find.byType(CoachButton));
      await tester.pumpAndSettle();

      expect(sheet(), findsOneWidget);
    });

    testWidgets(
      'asks a signed-out runner for an account first, not for money',
      (tester) async {
        // The bug this also fixes: the mark checked the tier alone, so a
        // signed-out runner met the paywall, and the paywall refuses a
        // signed-out buyer with "Sign in first" and nothing to sign in with.
        auth = FakeAuthRepository();
        await pumpShell(tester, access: CoachAccess.free);

        await tester.tap(find.byType(CoachButton));
        await tester.pumpAndSettle();

        expect(find.byType(SignInScreen), findsOneWidget);
        expect(find.byType(CoachGateSheet), findsNothing);
        expect(sheet(), findsNothing);
      },
    );

    testWidgets('shows the medical disclaimer the conversation never had', (
      tester,
    ) async {
      disclaimer = InMemoryDisclaimerStore();
      await pumpShell(tester);

      await tester.tap(find.byType(CoachButton));
      await tester.pumpAndSettle();
      await tapText(tester, AiConsentSheet.agreeLabel);

      // Two steps, one after the other: where the data goes, then what the
      // coach is not.
      expect(find.byType(MedicalDisclaimerScreen), findsOneWidget);
      await tapText(tester, 'Not now');
      expect(conversation(), findsNothing);
      expect(coach.sent, 0);

      // The permission stood; only the disclaimer is asked again.
      await tester.tap(find.byType(CoachButton));
      await tester.pumpAndSettle();
      expect(sheet(), findsNothing);
      expect(find.byType(MedicalDisclaimerScreen), findsOneWidget);

      await tapText(tester, 'I understand');
      expect(conversation(), findsOneWidget);
      expect(disclaimer.acknowledgeCount, 1);
    });
  });

  group('every "ask the coach"', () {
    testWidgets('asks before the question is sent, and "Not now" sends '
        'nothing', (tester) async {
      await pumpShell(tester, tab: 2);

      await tester.tap(find.text('Ask about this'));
      await tester.pumpAndSettle();

      expect(sheet(), findsOneWidget);
      expect(coach.asked, isEmpty);

      await tapText(tester, AiConsentSheet.notNowLabel);
      expect(conversation(), findsNothing);
      expect(coach.asked, isEmpty);

      await tester.tap(find.text('Ask about this'));
      await tester.pumpAndSettle();
      await tapText(tester, AiConsentSheet.agreeLabel);

      expect(coach.asked, hasLength(1));
    });

    testWidgets('a suggestion cannot outrun a withdrawn permission', (
      tester,
    ) async {
      consent.seed('fake-user', AiConsent.now(DateTime.now()));
      // No runs, so there is no observation to open on and the suggestions
      // are what the empty conversation offers.
      await pumpShell(tester, withRuns: false);

      await tester.tap(find.byType(CoachButton));
      await tester.pumpAndSettle();
      expect(conversation(), findsOneWidget);

      // Taken back while the sheet was open: the chip is one tap, and the
      // tap must not beat the answer.
      await consent.withdraw();
      await tester.tap(find.text('How has my training been going?'));
      await tester.pumpAndSettle();

      expect(sheet(), findsOneWidget);
      await tapText(tester, AiConsentSheet.notNowLabel);
      expect(coach.asked, isEmpty);
    });
  });

  group('building a plan', () {
    testWidgets('asks before the price, so nobody pays and then declines', (
      tester,
    ) async {
      await pumpShell(tester, access: CoachAccess.free, tab: 1);

      await tapText(tester, 'Build a plan');
      expect(sheet(), findsOneWidget);
      expect(find.byType(CoachGateSheet), findsNothing);

      await tapText(tester, AiConsentSheet.notNowLabel);
      expect(find.byType(CoachGateSheet), findsNothing);
      expect(find.text('Build a plan'), findsOneWidget);

      await tapText(tester, 'Build a plan');
      await tapText(tester, AiConsentSheet.agreeLabel);
      expect(find.byType(CoachGateSheet), findsOneWidget);
      expect(coach.sent, 0);
    });

    testWidgets('starts the intake only after agreeing', (tester) async {
      await pumpShell(tester, tab: 1);

      await tapText(tester, 'Build a plan');
      expect(sheet(), findsOneWidget);
      expect(coach.intakes, 0);

      await tapText(tester, AiConsentSheet.agreeLabel);
      // Past the shape question, whose answer opens the intake. The
      // disclaimer was read before this test, so the flow does not ask it.
      expect(find.byType(MedicalDisclaimerScreen), findsNothing);
      await tapText(tester, 'I have a race coming up');

      expect(coach.intakes, 1);
    });
  });
  group('adjusting a week', () {
    final profile = RunnerProfile(
      goalDistanceMeters: 42195,
      eventDate: DateTime(2026, 11, 1),
      currentWeeklyMeters: 45000,
      longestRecentMeters: 18000,
      daysPerWeek: 5,
      availableWeekdays: const <int>{1, 2, 4, 6, 7},
      timeTrialDistanceMeters: 5000,
      timeTrialDuration: const Duration(minutes: 22),
    );
    final slot = buildSkeleton(
      profile,
      now: DateTime(2026, 7, 25),
      weeks: 12,
    ).weeks[5];

    testWidgets('asks before the sheet whose request goes to the coach', (
      tester,
    ) async {
      final planner = _CountingPlanClient();
      var gateAnswer = false;
      var gateAsked = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: WeekDetailScreen(
            week: buildFallbackWeek(slot, profile),
            slot: slot,
            paces: TrainingPaces.fromRace(
              Distance.meters(5000),
              const Duration(minutes: 22),
            ),
            profile: profile,
            adaptation: AdaptationService(client: planner),
            beforeAdjust: () async {
              gateAsked++;
              return gateAnswer;
            },
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
      expect(gateAsked, 1);
      expect(find.text('Ask the coach'), findsNothing);
      expect(planner.adaptations, 0);

      gateAnswer = true;
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
      expect(find.text('Ask the coach'), findsOneWidget);
    });
  });
}
