import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/data/adaptation_service.dart';
import 'package:mgk_run/src/features/coaching/data/plan_client.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_validator.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';

/// Returns a fixed revised week (or null / throws) for proposeAdaptation.
class _AdaptClient implements PlanClient {
  _AdaptClient(this.revised, {this.throwIt = false});
  final TrainingWeek? revised;
  final bool throwIt;

  @override
  Future<TrainingWeek?> proposeAdaptation({
    required TrainingWeek week,
    required SkeletonWeek slot,
    required RunnerProfile profile,
    required String request,
  }) async {
    if (throwIt) throw Exception('provider down');
    return revised;
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

void main() {
  final now = DateTime(2026, 7, 25);
  final profile = RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: DateTime(2026, 11, 1),
    currentWeeklyMeters: 45000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 4, 6, 7},
  );
  final slot = buildSkeleton(profile, now: now, weeks: 12).weeks[5];
  final base = buildFallbackWeek(slot, profile);

  Future<AdaptationProposal?> propose(
    TrainingWeek? revised, {
    bool thr = false,
  }) => AdaptationService(
    client: _AdaptClient(revised, throwIt: thr),
  ).propose(week: base, slot: slot, profile: profile, request: 'change it');

  test('a valid revision becomes a proposal carrying the changes', () async {
    // Shift distance between two easy days: total unchanged, still valid.
    final sessions = base.sessions.toList();
    final easy = <int>[
      for (var i = 0; i < sessions.length; i++)
        if (sessions[i].kind == SessionKind.easy) i,
    ];
    sessions[easy[0]] = PlannedSession(
      weekday: sessions[easy[0]].weekday,
      kind: SessionKind.easy,
      distanceMeters: sessions[easy[0]].distanceMeters - 300,
    );
    sessions[easy[1]] = PlannedSession(
      weekday: sessions[easy[1]].weekday,
      kind: SessionKind.easy,
      distanceMeters: sessions[easy[1]].distanceMeters + 300,
    );
    final revised = TrainingWeek(skeletonIndex: slot.index, sessions: sessions);

    final proposal = await propose(revised);

    expect(proposal, isNotNull);
    expect(proposal!.changes.length, 2);
    expect(validateWeek(proposal.week, slot, profile).isValid, isTrue);
  });

  test(
    'a structurally invalid revision is rejected, with its reason',
    () async {
      // Move a run to Wednesday, which isn't available -> unavailable_day.
      final sessions = base.sessions.toList();
      sessions[1] = PlannedSession(
        weekday: DateTime.wednesday,
        kind: sessions[1].kind,
        distanceMeters: sessions[1].distanceMeters,
      );
      final bad = TrainingWeek(skeletonIndex: slot.index, sessions: sessions);

      // Refused, not merely absent. The distinction is what the runner hears:
      // a null gets them "try telling me what you want differently", which is
      // useless advice when the obstacle is a day they told us they were busy.
      await expectLater(
        propose(bad),
        throwsA(
          isA<AdaptationRefused>().having(
            (e) => e.violations.map((v) => v.code),
            'violations',
            contains('unavailable_day'),
          ),
        ),
      );
    },
  );

  test('the refusal is said in the runner\'s terms, not the validator\'s', () {
    const refused = AdaptationRefused(<Violation>[
      Violation('unavailable_day', 'a session falls on weekday 3'),
    ]);
    expect(refused.message, contains("day you said you can't run"));
    // No validator vocabulary leaks through to the conversation.
    expect(refused.message, isNot(contains('weekday')));
    expect(refused.message, isNot(contains('unavailable_day')));
  });

  test('an unrecognised violation still refuses rather than pretending', () {
    // A new invariant added to the validator and not to the phrasebook must
    // not fall through to "here is your change" — it falls back to a plain
    // refusal, because the alternative is offering a week nothing approved.
    const refused = AdaptationRefused(<Violation>[
      Violation('some_future_rule', 'internal'),
    ]);
    expect(refused.message, contains('left it as it was'));
  });

  test('a null revision yields no proposal', () async {
    expect(await propose(null), isNull);
  });

  test('a no-op revision (nothing changed) yields no proposal', () async {
    expect(await propose(base), isNull);
  });

  test('a thrown proposal yields no proposal', () async {
    expect(await propose(base, thr: true), isNull);
  });
}
