import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/data/coach_client.dart';
import 'package:mgk_run/src/features/coaching/data/coach_service.dart';
import 'package:mgk_run/src/features/coaching/domain/ai_consent.dart';
import 'package:mgk_run/src/features/coaching/domain/intake_slots.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Every body the Edge Function was sent, and one fixed answer.
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
          data: <String, dynamic>{'reply': 'Noted.', 'summary': 'Kept.'},
        ),
      );
    }
    return super.noSuchMethod(invocation);
  }
}

class _Client implements SupabaseClient {
  _Client(this.functions);

  @override
  final FunctionsClient functions;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// **The coach worked out "today" in UTC.** A runner in New York asking at
/// 9pm, or in Sydney at 7am, was answered about the wrong day: a session
/// "tomorrow" that was today, a run "yesterday" that was this morning. The
/// phone is the only party that knows the runner's zone, so every request now
/// says what day it is there, and the offset that made it that day.
void main() {
  late _Functions functions;

  setUp(() => functions = _Functions());

  CoachService serviceAt(DateTime now) => CoachService(
    client: _Client(functions),
    consent: InMemoryAiConsentStore.granted(),
    now: () => now,
  );

  test('a turn of the conversation says what day it is here', () async {
    final evening = DateTime(2026, 9, 29, 21, 30);

    await serviceAt(
      evening,
    ).chat(brief: '', history: const <ChatMessage>[], message: 'Hi');

    expect(functions.bodies.single['local_date'], '2026-09-29');
    expect(
      functions.bodies.single['utc_offset_minutes'],
      evening.timeZoneOffset.inMinutes,
    );
  });

  test('so does every other surface', () async {
    final coach = serviceAt(DateTime(2026, 9, 29, 7));

    await coach.intake(slots: const IntakeSlots(), history: const []);
    await coach.summarise(
      transcript: const <ChatMessage>[ChatMessage.user('My calf is sore')],
    );
    await coach.proposeSkeleton(
      profile: const RunnerProfile(
        currentWeeklyMeters: 30000,
        longestRecentMeters: 12000,
        daysPerWeek: 4,
        availableWeekdays: <int>{1, 3, 5, 7},
      ),
    );

    expect(functions.bodies, hasLength(3));
    for (final body in functions.bodies) {
      expect(body['local_date'], '2026-09-29', reason: '${body['surface']}');
      expect(body['utc_offset_minutes'], isA<int>());
    }
  });

  test('the date is padded, so it reads as ISO', () async {
    await serviceAt(
      DateTime(2026, 1, 5, 0, 15),
    ).chat(brief: '', history: const <ChatMessage>[], message: 'Hi');

    expect(functions.bodies.single['local_date'], '2026-01-05');
  });

  test('the day and the offset come from the same clock', () async {
    // A UTC instant reads as UTC: offset zero, and the UTC date. What matters
    // is that the two fields always describe the same moment in the same zone.
    await serviceAt(
      DateTime.utc(2026, 9, 30, 1),
    ).chat(brief: '', history: const <ChatMessage>[], message: 'Hi');

    expect(functions.bodies.single['local_date'], '2026-09-30');
    expect(functions.bodies.single['utc_offset_minutes'], 0);
  });
}
