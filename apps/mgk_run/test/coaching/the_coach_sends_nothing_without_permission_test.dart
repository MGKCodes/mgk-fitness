import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/coaching/data/coach_service.dart';
import 'package:mgk_run/src/features/coaching/domain/ai_consent.dart';
import 'package:mgk_run/src/features/coaching/domain/intake_slots.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The Edge Function, as far as the client can see it: every body it was
/// sent, and one fixed answer.
class _Functions implements FunctionsClient {
  final List<Map<String, dynamic>> bodies = <Map<String, dynamic>>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #invoke) {
      final body = invocation.namedArguments[#body] as Map<String, dynamic>;
      bodies.add(Map<String, dynamic>.of(body));
      return Future<FunctionResponse>.value(
        FunctionResponse(
          status: 200,
          data: <String, dynamic>{'reply': 'Noted.'},
        ),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

/// A client with nothing behind it but [functions]. Anything else the service
/// reached for would fail the test loudly, which is the point.
class _Client implements SupabaseClient {
  _Client(this.functions);

  @override
  final FunctionsClient functions;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A store that cannot say, as a broken file or a missing plugin would.
class _Unanswerable implements AiConsentStore {
  @override
  Future<bool> isGranted() async => throw StateError('unreadable');

  @override
  Future<void> grant() async {}

  @override
  Future<void> withdraw() async {}
}

/// **Asking at the door is a habit; this is the rule.**
///
/// The screens ask before the coach opens. `CoachService` is the one place
/// every request passes, so it refuses there too, before a body is built:
/// a caller added next month that forgets to ask still cannot send, and
/// neither can the housekeeping calls nobody watches -- a summary written as
/// the sheet closes, a week filled in ahead.
void main() {
  late _Functions functions;

  setUp(() => functions = _Functions());

  CoachService serviceWith(AiConsentStore consent) =>
      CoachService(client: _Client(functions), consent: consent);

  const profile = RunnerProfile(
    currentWeeklyMeters: 30000,
    longestRecentMeters: 12000,
    daysPerWeek: 4,
    availableWeekdays: <int>{1, 3, 5, 7},
  );
  const slot = SkeletonWeek(
    index: 1,
    phase: Phase.base,
    volumeMeters: 30000,
    longRunMeters: 12000,
  );

  final refusal = throwsA(isA<CoachConsentRequiredException>());

  group('without permission nothing leaves, on any surface', () {
    test('a turn of the conversation', () async {
      final coach = serviceWith(InMemoryAiConsentStore());

      await expectLater(
        coach.chat(
          brief: 'Ran 5 km yesterday.',
          history: const <ChatMessage>[],
          message: 'How am I doing?',
        ),
        refusal,
      );
      expect(functions.bodies, isEmpty);
    });

    test('the intake that builds a plan', () async {
      final coach = serviceWith(InMemoryAiConsentStore());

      await expectLater(
        coach.intake(slots: const IntakeSlots(), history: const []),
        refusal,
      );
      expect(functions.bodies, isEmpty);
    });

    test('the calls nobody is watching', () async {
      final coach = serviceWith(InMemoryAiConsentStore());

      await expectLater(
        coach.summarise(
          transcript: const <ChatMessage>[ChatMessage.user('My calf hurts')],
        ),
        refusal,
      );
      await expectLater(coach.logRun('5k this morning'), refusal);
      await expectLater(coach.editRun('that was 6k'), refusal);
      await expectLater(coach.setGoal('a marathon in April'), refusal);
      expect(functions.bodies, isEmpty);
    });

    test('and the plan it generates', () async {
      final coach = serviceWith(InMemoryAiConsentStore());

      await expectLater(coach.proposeSkeleton(profile: profile), refusal);
      await expectLater(
        coach.proposeWeek(slot: slot, profile: profile),
        refusal,
      );
      expect(functions.bodies, isEmpty);
    });
  });

  test('with permission the request goes out', () async {
    final coach = serviceWith(InMemoryAiConsentStore.granted());

    final turn = await coach.chat(
      brief: '',
      history: const <ChatMessage>[],
      message: 'How am I doing?',
    );

    expect(turn.reply, 'Noted.');
    expect(functions.bodies, hasLength(1));
  });

  test('a withdrawal stops the very next request', () async {
    final consent = InMemoryAiConsentStore.granted();
    final coach = serviceWith(consent);
    await coach.chat(brief: '', history: const <ChatMessage>[], message: 'Hi');

    await consent.withdraw();

    await expectLater(
      coach.chat(brief: '', history: const <ChatMessage>[], message: 'Hi'),
      refusal,
    );
    expect(functions.bodies, hasLength(1));
  });

  test('permission is the signed-in account\'s, not the phone\'s', () async {
    String who = 'runner-a';
    final consent = InMemoryAiConsentStore(userId: () => who);
    await consent.grant();
    final coach = serviceWith(consent);

    who = 'runner-b';

    await expectLater(
      coach.chat(brief: '', history: const <ChatMessage>[], message: 'Hi'),
      refusal,
    );
    expect(functions.bodies, isEmpty);
  });

  test('a store that cannot answer is a no', () async {
    final coach = serviceWith(_Unanswerable());

    await expectLater(
      coach.chat(brief: '', history: const <ChatMessage>[], message: 'Hi'),
      refusal,
    );
    expect(functions.bodies, isEmpty);
  });
}
