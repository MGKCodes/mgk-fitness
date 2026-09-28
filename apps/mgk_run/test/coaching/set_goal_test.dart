import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/coaching/data/coach_mappers.dart';
import 'package:mgk_run/src/features/coaching/domain/goal_draft.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_shape.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/presentation/chat_controller.dart';
import 'package:mgk_run/src/features/coaching/presentation/chat_entry.dart';

/// A coach that answers with a fixed reply and intent.
class _Coach implements CoachChatClient {
  _Coach({this.intent});

  final CoachIntent? intent;
  int calls = 0;

  @override
  Future<ChatTurn> chat({
    required String brief,
    required List<ChatMessage> history,
    required String message,
  }) async {
    calls++;
    return ChatTurn(reply: 'Right, noted.', intent: intent);
  }
}

void main() {
  final now = DateTime(2026, 7, 29);

  RunnerProfile marathoner() => RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: DateTime(2026, 11, 15),
    currentWeeklyMeters: 40000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 4, 6, 7},
  );

  ChatController controller({
    CoachIntent? intent,
    Future<GoalProposal?> Function(String)? propose,
    Future<bool> Function(GoalProposal)? apply,
  }) => ChatController(
    client: _Coach(intent: intent),
    brief: (_) async => 'a brief',
    onSetGoalRequest: propose,
    onApplyGoal: apply,
    now: () => now,
  );

  group('reading what the runner said', () {
    test('a race gives a distance and a date', () {
      final change = goalChangeFromResponse(<String, dynamic>{
        'goal_distance_meters': 21097.5,
        'event_date': '2026-10-04',
        'clears_goal': false,
      });
      expect(change.goalDistanceMeters, 21097.5);
      expect(change.eventDate, DateTime(2026, 10, 4));
      expect(change.clearsGoal, isFalse);
      expect(change.isSomething, isTrue);
    });

    test('a distance with no date is complete, not partial', () {
      final change = goalChangeFromResponse(<String, dynamic>{
        'goal_distance_meters': 42195,
        'event_date': null,
        'clears_goal': false,
      });
      expect(change.isSomething, isTrue);
      expect(change.onto(const GoalDraft()).shape, PlanShape.horizon);
    });

    test('nothing read is not a proposal', () {
      // A question rather than a decision. Raising a card here would ask the
      // runner to approve a change they never made.
      final change = goalChangeFromResponse(<String, dynamic>{
        'goal_distance_meters': null,
        'event_date': null,
        'clears_goal': false,
      });
      expect(change.isSomething, isFalse);
    });
  });

  group('null means unchanged; clearing is its own answer', () {
    // The load-bearing distinction. Without it "move the race to April" and
    // "I'm done with the marathon" arrive identically, and one wipes a goal.
    test('moving a date keeps the distance', () {
      final change = goalChangeFromResponse(<String, dynamic>{
        'goal_distance_meters': null,
        'event_date': '2026-12-12',
        'clears_goal': false,
      });
      final next = change.onto(GoalDraft.from(marathoner()));

      expect(next.goalDistanceMeters, 42195, reason: 'never restated, so kept');
      expect(next.eventDate, DateTime(2026, 12, 12));
      expect(next.shape, PlanShape.block);
    });

    test('changing a distance keeps the date', () {
      final change = goalChangeFromResponse(<String, dynamic>{
        'goal_distance_meters': 21097,
        'event_date': null,
        'clears_goal': false,
      });
      final next = change.onto(GoalDraft.from(marathoner()));

      expect(next.goalDistanceMeters, 21097);
      expect(next.eventDate, DateTime(2026, 11, 15));
    });

    test('clearing wins over everything and leaves no date behind', () {
      final change = goalChangeFromResponse(<String, dynamic>{
        'goal_distance_meters': 42195,
        'event_date': '2026-11-15',
        'clears_goal': true,
      });
      final next = change.onto(GoalDraft.from(marathoner()));

      expect(next.goalDistanceMeters, isNull);
      expect(next.eventDate, isNull);
      expect(next.shape, PlanShape.rhythm);
    });

    test('clearing is something even with both fields null', () {
      final change = goalChangeFromResponse(<String, dynamic>{
        'goal_distance_meters': null,
        'event_date': null,
        'clears_goal': true,
      });
      expect(change.isSomething, isTrue);
    });
  });

  group('the conversation routes it', () {
    test('a set_goal intent asks for a proposal', () async {
      var asked = '';
      final chat = controller(
        intent: const CoachIntent(
          kind: CoachIntent.setGoal,
          request: 'Manchester on 5 April',
        ),
        propose: (r) async {
          asked = r;
          return const GoalProposal(
            draft: GoalDraft(goalDistanceMeters: 42195),
            shape: PlanShape.horizon,
          );
        },
      );

      await chat.send('I entered Manchester');

      expect(asked, 'Manchester on 5 April');
      expect(chat.entries.last.proposal, isA<GoalProposal>());
    });

    test(
      'a build without the seam ignores the intent rather than half-doing it',
      () async {
        // The safe half to be missing: honouring it supersedes a plan.
        final chat = controller(
          intent: const CoachIntent(
            kind: CoachIntent.setGoal,
            request: 'a marathon',
          ),
        );

        await chat.send('I entered Manchester');

        expect(chat.entries.last.proposal, isNull);
        expect(chat.entries.last.message.text, 'Right, noted.');
      },
    );

    test('a refusal is said, not swallowed', () async {
      // The runner has just told their coach they entered a race. Silence
      // reads as "it worked".
      final chat = controller(
        intent: const CoachIntent(
          kind: CoachIntent.setGoal,
          request: 'the big one',
        ),
        propose: (_) async => null,
      );

      await chat.send('I entered a race');

      expect(
        chat.entries.last.message.text,
        contains("couldn't pin that down"),
      );
    });
  });

  group('applying it', () {
    GoalProposal offered() => const GoalProposal(
      draft: GoalDraft(goalDistanceMeters: 21097),
      shape: PlanShape.horizon,
      supersedes: 4,
    );

    test('a confirmed goal is written and marked applied', () async {
      GoalProposal? applied;
      final chat = controller(
        intent: const CoachIntent(kind: CoachIntent.setGoal, request: 'a half'),
        propose: (_) async => offered(),
        apply: (p) async {
          applied = p;
          return true;
        },
      );

      await chat.send('half marathon now');
      await chat.applyProposal(chat.entries.last);

      expect(applied?.draft.goalDistanceMeters, 21097);
      expect(chat.entries.last.proposal?.state, ProposalState.applied);
    });

    test('a failed write leaves the offer standing', () async {
      // Not "applied". A card that said done over an unchanged plan would
      // leave them training for the wrong race with nothing disagreeing.
      final chat = controller(
        intent: const CoachIntent(kind: CoachIntent.setGoal, request: 'a half'),
        propose: (_) async => offered(),
        apply: (_) async => false,
      );

      await chat.send('half marathon now');
      await chat.applyProposal(chat.entries.last);

      expect(chat.entries.last.proposal?.state, ProposalState.failed);
    });

    test('declining records the decision rather than losing it', () async {
      final chat = controller(
        intent: const CoachIntent(kind: CoachIntent.setGoal, request: 'a half'),
        propose: (_) async => offered(),
        apply: (_) async => true,
      );

      await chat.send('half marathon now');
      chat.declineProposal(chat.entries.last);

      expect(chat.entries.last.proposal?.state, ProposalState.declined);
    });

    test('the cost of accepting travels with the offer', () {
      // "This replaces your plan, including 4 weeks already worked through" is
      // the half of the decision the runner cannot reconstruct for themselves.
      expect(offered().supersedes, 4);
    });
  });
}
