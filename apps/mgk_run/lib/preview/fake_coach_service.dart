import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/coaching/domain/intake_conversation.dart';
import 'package:mgk_run/src/features/coaching/domain/intake_slots.dart';

/// A scripted, offline coach for the web preview — drives the onboarding UI
/// (chat, typing delay, progressive slot fill, completion) and the open
/// conversation with no provider key and no network. The extraction is fixed
/// rather than parsed from input; the point is to exercise the flow and
/// animations, not the model.
class FakeCoachService
    implements CoachClient, CoachChatClient, CoachSummariseClient {
  int _step = 0;

  /// A future event date relative to the wall clock, so the intake always
  /// completes regardless of when the preview runs.
  DateTime get _eventDate => DateTime.now().add(const Duration(days: 112));

  /// Stands in for the memory rewrite so the harness can exercise the whole
  /// loop with no key and no network. Deterministic on purpose — the preview
  /// should show the *shape* of a memory, not a different one each reload.
  @override
  Future<String?> summarise({
    String? previous,
    required List<ChatMessage> transcript,
  }) async =>
      'They run before work and would rather not run in the dark. A left calf '
      'that tightens on faster sessions. Training for a first marathon and '
      'more anxious about the distance than the time.';

  @override
  Future<IntakeTurn> intake({
    required IntakeSlots slots,
    required List<IntakeMessage> history,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final step = _step++;
    switch (step) {
      case 0:
        return const IntakeTurn(
          reply:
              "Hi, I'm your Runio coach. What are you training for, and when "
              'is it?',
          extracted: IntakeSlots(),
        );
      case 1:
        return IntakeTurn(
          reply:
              'A marathon this autumn, nice goal. How much are you running in '
              "a typical week right now, and what's your longest run lately?",
          extracted: IntakeSlots(
            goalDistanceMeters: 42195,
            eventDate: _eventDate,
          ),
        );
      case 2:
        return const IntakeTurn(
          reply:
              'Solid base to build on. Which days can you train, and how many '
              'days a week are you aiming for?',
          extracted: IntakeSlots(
            currentWeeklyMeters: 40000,
            longestRecentMeters: 18000,
          ),
        );
      case 3:
        return const IntakeTurn(
          reply:
              'Five days works well. Last thing: a recent race or time trial, '
              'the distance and your time?',
          extracted: IntakeSlots(
            daysPerWeek: 5,
            availableWeekdays: <int>{1, 2, 4, 6, 7},
          ),
        );
      default:
        return const IntakeTurn(
          reply:
              "Perfect, that's everything I need. Take a look at the details "
              'on the next screen and fix anything I got wrong.',
          extracted: IntakeSlots(
            timeTrialDistanceMeters: 5000,
            timeTrialDuration: Duration(minutes: 22),
          ),
        );
    }
  }

  /// A canned conversational turn.
  ///
  /// The reply is chosen by a keyword rather than by a model, so the harness can
  /// reach each of the states worth looking at: an ordinary answer, and one that
  /// comes back wanting to change the week. Anything that sounds like a niggle
  /// or a moved session returns an `adapt_week` intent, which drops the runner
  /// into the real propose → validate → diff → approve path against
  /// `FakePlanClient`.
  @override
  Future<ChatTurn> chat({
    required String brief,
    required List<ChatMessage> history,
    required String message,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 650));
    final asked = message.toLowerCase();

    if (_soundsLikeAChange(asked)) {
      return ChatTurn(
        reply:
            "Let's not push through that. I'll take the edge off this week and "
            'show you what I would change — have a look before it goes in.',
        intent: CoachIntent(kind: CoachIntent.adaptWeek, request: message),
      );
    }
    if (asked.contains('half') || asked.contains('marathon')) {
      return const ChatTurn(
        reply:
            'Off your recent 5k, a half around 1:42 looks right today, and '
            'that comes down as the long runs stack up. The number to watch is '
            'how the last few miles feel, not the split.',
      );
    }
    return const ChatTurn(
      reply:
          'Your last few weeks have been steady, which is the boring part that '
          "actually works. Keep the easy runs easy and you'll be fine.",
    );
  }

  static bool _soundsLikeAChange(String asked) =>
      asked.contains('sore') ||
      asked.contains('hurt') ||
      asked.contains('move') ||
      asked.contains('skip') ||
      asked.contains('swap');
}
