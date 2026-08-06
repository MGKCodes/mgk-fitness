import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/coaching/data/coach_service.dart';
import 'package:mgk_run/src/features/coaching/domain/intake_conversation.dart';
import 'package:mgk_run/src/features/coaching/domain/intake_slots.dart';
import 'package:mgk_run/src/features/coaching/presentation/onboarding_controller.dart';

/// Returns queued turns in order, repeating the last once exhausted.
class _ScriptedCoach implements CoachClient {
  _ScriptedCoach(this.turns);
  final List<IntakeTurn> turns;
  int i = 0;
  @override
  Future<IntakeTurn> intake({
    required IntakeSlots slots,
    required List<IntakeMessage> history,
  }) async => turns[i < turns.length ? i++ : turns.length - 1];
}

class _ThrowingCoach implements CoachClient {
  @override
  Future<IntakeTurn> intake({
    required IntakeSlots slots,
    required List<IntakeMessage> history,
  }) async => throw const CoachException('the coach hit a problem');
}

void main() {
  final now = DateTime(2026, 7, 25);
  final future = DateTime(2026, 11, 1);

  // A script that fills every required slot over four user turns.
  List<IntakeTurn> completingScript() => <IntakeTurn>[
    const IntakeTurn(
      reply: 'Hi, what are you training for?',
      extracted: IntakeSlots(),
    ),
    IntakeTurn(
      reply: 'A marathon in November. Weekly volume and longest run?',
      extracted: IntakeSlots(goalDistanceMeters: 42195, eventDate: future),
    ),
    const IntakeTurn(
      reply: 'Which days, and how many per week?',
      extracted: IntakeSlots(
        currentWeeklyMeters: 40000,
        longestRecentMeters: 18000,
      ),
    ),
    const IntakeTurn(
      reply: 'A recent time trial?',
      extracted: IntakeSlots(
        daysPerWeek: 5,
        availableWeekdays: <int>{1, 2, 4, 6, 7},
      ),
    ),
    const IntakeTurn(
      reply: "That's everything, review the details next.",
      extracted: IntakeSlots(
        timeTrialDistanceMeters: 5000,
        timeTrialDuration: Duration(minutes: 22),
      ),
    ),
  ];

  test('start greets and fills nothing', () async {
    final c = OnboardingController(
      coach: _ScriptedCoach(completingScript()),
      now: () => now,
    );
    await c.start();

    expect(c.messages, hasLength(1));
    expect(c.messages.single.role, 'assistant');
    expect(c.slots.missingRequired, isNotEmpty);
    expect(c.isBusy, isFalse);
    expect(c.isFinished, isFalse);
    expect(c.canSend, isTrue);
  });

  test('start is a no-op once the transcript has content', () async {
    final c = OnboardingController(
      coach: _ScriptedCoach(completingScript()),
      now: () => now,
    );
    await c.start();
    await c.start(); // second call ignored
    expect(c.messages, hasLength(1));
  });

  test('a full conversation completes and locks the input', () async {
    final c = OnboardingController(
      coach: _ScriptedCoach(completingScript()),
      now: () => now,
    );
    await c.start();
    await c.send('Marathon on November 1st');
    await c.send('40k a week, longest was 18k');
    await c.send('Mon Tue Thu Sat Sun, five days');
    await c.send('5k in 22 minutes');

    expect(c.isComplete, isTrue);
    expect(c.isFinished, isTrue);
    expect(c.canSend, isFalse);
    // Four user turns + five coach turns.
    expect(c.messages.where((m) => m.isUser), hasLength(4));
    expect(c.slots.timeTrialDuration, const Duration(minutes: 22));
  });

  test('empty input and post-finish sends are ignored', () async {
    final c = OnboardingController(
      coach: _ScriptedCoach(<IntakeTurn>[
        const IntakeTurn(reply: 'hi', extracted: IntakeSlots()),
      ]),
      now: () => now,
      turnCap: 1,
    );
    await c.start();
    await c.send('   '); // whitespace ignored
    expect(c.messages.where((m) => m.isUser), isEmpty);

    await c.send('first'); // hits the cap
    expect(c.turnCapReached, isTrue);
    await c.send('second'); // ignored, conversation is finished
    expect(c.messages.where((m) => m.isUser), hasLength(1));
  });

  test('the turn cap ends an incomplete conversation', () async {
    // A coach that never fills a slot.
    final c = OnboardingController(
      coach: _ScriptedCoach(<IntakeTurn>[
        const IntakeTurn(reply: 'and?', extracted: IntakeSlots()),
      ]),
      now: () => now,
      turnCap: 3,
    );
    await c.start();
    await c.send('a');
    await c.send('b');
    await c.send('c');

    expect(c.isComplete, isFalse);
    expect(c.turnCapReached, isTrue);
    expect(c.isFinished, isTrue);
    expect(c.canSend, isFalse);
  });

  test('a coach error surfaces without appending an assistant turn', () async {
    final c = OnboardingController(coach: _ThrowingCoach(), now: () => now);
    await c.start();

    expect(c.error, isNotNull);
    expect(c.isBusy, isFalse);
    expect(c.messages, isEmpty); // nothing partial left behind
  });
}
