import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/data/adaptation_service.dart';
import 'package:mgk_run/src/features/coaching/data/plan_client.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_validator.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/week_progress.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

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

/// A client that can be told what already happened, and records whether it was.
///
/// The point of the pair: the tally must reach a client that offers the richer
/// call, and must not be quietly dropped on one that does not.
class _AwareClient extends _AdaptClient implements WeekAwarePlanClient {
  _AwareClient(super.revised);

  WeekAsRun? sawStanding;
  bool sawPlainCall = false;

  @override
  Future<TrainingWeek?> proposeAdaptation({
    required TrainingWeek week,
    required SkeletonWeek slot,
    required RunnerProfile profile,
    required String request,
  }) async {
    sawPlainCall = true;
    return super.proposeAdaptation(
      week: week,
      slot: slot,
      profile: profile,
      request: request,
    );
  }

  @override
  Future<TrainingWeek?> proposeRefit({
    required TrainingWeek week,
    required SkeletonWeek slot,
    required RunnerProfile profile,
    required String request,
    required WeekAsRun soFar,
  }) async {
    sawStanding = soFar;
    return revised;
  }
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

  // ---- EDGE-17: the date rules, opt-in through weekStart --------------------
  //
  // Before this, propose() never passed weekStart/now into validateWeek at
  // all, so a revision landing a session on race day — the one thing
  // session_on_race_day exists to catch — passed as though nothing was
  // wrong, because the validator had no calendar to check it against.

  test('a revision that lands a session on race day is refused once the '
      'adaptation is given a calendar', () async {
    // 2026-08-02 is the Sunday of `monday`'s (2026-07-27) week.
    final raceProfile = profile.copyWith(eventDate: DateTime(2026, 8, 2));
    final sessions = base.sessions.toList();
    final sundaySlot = sessions.indexWhere((s) => s.weekday == DateTime.sunday);
    sessions[sundaySlot] = PlannedSession(
      weekday: DateTime.sunday,
      kind: SessionKind.long,
      // +1000 m: a genuine change, so this is not a no-op diffWeek would
      // drop before validation ever runs, while still keeping a session
      // on race day either way.
      distanceMeters: sessions[sundaySlot].distanceMeters + 1000,
    );
    final onRaceDay = TrainingWeek(
      skeletonIndex: slot.index,
      sessions: sessions,
    );

    await expectLater(
      AdaptationService(client: _AdaptClient(onRaceDay)).propose(
        week: base,
        slot: slot,
        profile: raceProfile,
        request: 'move Sunday earlier',
        weekStart: DateTime(2026, 7, 27),
        now: DateTime(2026, 7, 27),
      ),
      throwsA(
        isA<AdaptationRefused>().having(
          (e) => e.violations.map((v) => v.code),
          'violations',
          contains('session_on_race_day'),
        ),
      ),
    );
  });

  test('without a calendar the same race-day revision is still accepted — the '
      'gap this closes', () async {
    // The exact pre-fix shape: weekStart/now simply not passed. Pinned so
    // a future change cannot quietly make this opt-in mandatory without
    // the test suite noticing the behaviour it would change.
    final raceProfile = profile.copyWith(eventDate: DateTime(2026, 8, 2));
    final sessions = base.sessions.toList();
    final sundaySlot = sessions.indexWhere((s) => s.weekday == DateTime.sunday);
    sessions[sundaySlot] = PlannedSession(
      weekday: DateTime.sunday,
      kind: SessionKind.long,
      // +1000 m: a genuine change, so this is not a no-op diffWeek would
      // drop before validation ever runs, while still keeping a session
      // on race day either way.
      distanceMeters: sessions[sundaySlot].distanceMeters + 1000,
    );
    final onRaceDay = TrainingWeek(
      skeletonIndex: slot.index,
      sessions: sessions,
    );

    final proposal = await AdaptationService(client: _AdaptClient(onRaceDay))
        .propose(
          week: base,
          slot: slot,
          profile: raceProfile,
          request: 'move Sunday earlier',
        );
    expect(proposal, isNotNull);
  });

  // ---- the week the runner is actually living in ---------------------------
  //
  // "Adjust my week" used to be answered from the plan alone, so a runner who
  // went out on a Wednesday the plan left blank got the same generic reshuffle
  // as a runner who had done nothing at all.

  // 2026-07-27 is a Monday.
  final monday = DateTime(2026, 7, 27);

  RunSummary runAt(DateTime at, {required double meters}) => RunSummary(
    startedAt: at,
    duration: Duration(minutes: (meters / 200).round()),
    distanceMeters: meters,
  );

  WeekAsRun standing(DateTime when, List<RunSummary> runs) => weekAsRun(
    week: base,
    weekStart: monday,
    now: when,
    runs: runs,
    since: monday,
  );

  /// Monday run as prescribed, Tuesday missed, and 12 km on the Wednesday the
  /// plan asked nothing of. The field report's week, on the Thursday.
  WeekAsRun diverged() => standing(addDays(monday, 3), <RunSummary>[
    runAt(monday, meters: 8000),
    runAt(addDays(monday, 2), meters: 12000),
  ]);

  group('what happened reaches the model when the client can take it', () {
    test('a week-aware client is asked the richer question', () async {
      final client = _AwareClient(null);
      final soFar = diverged();

      await AdaptationService(client: client).propose(
        week: base,
        slot: slot,
        profile: profile,
        request: 'rebalance what is left',
        soFar: soFar,
      );

      expect(client.sawStanding, same(soFar));
      expect(client.sawPlainCall, isFalse);
    });

    test(
      'and is asked the plain one when there is nothing to tell it',
      () async {
        // No tally, no richer call: the argument is what the extra question is
        // for, and asking it empty would be paying to say nothing.
        final client = _AwareClient(null);

        await AdaptationService(client: client).propose(
          week: base,
          slot: slot,
          profile: profile,
          request: 'change it',
        );

        expect(client.sawPlainCall, isTrue);
        expect(client.sawStanding, isNull);
      },
    );

    test('a client that cannot take it still works, unchanged', () async {
      // Every fake in the app implements the plain seam and most answer a
      // different method entirely. None of them may break for this.
      final proposal = await AdaptationService(client: _AdaptClient(null))
          .propose(
            week: base,
            slot: slot,
            profile: profile,
            request: 'change it',
            soFar: standing(monday, const <RunSummary>[]),
          );
      expect(proposal, isNull);
    });
  });

  group('a revision may not rewrite what the runner has already run', () {
    test('dropping a completed session is refused, with the reason', () async {
      final soFar = diverged();
      final withoutMonday = TrainingWeek(
        skeletonIndex: base.skeletonIndex,
        sessions: <PlannedSession>[
          for (final s in base.sessions)
            if (s.weekday != DateTime.monday) s,
        ],
      );

      await expectLater(
        AdaptationService(client: _AwareClient(withoutMonday)).propose(
          week: base,
          slot: slot,
          profile: profile,
          request: 'rebalance what is left',
          soFar: soFar,
        ),
        throwsA(
          isA<AdaptationRefused>().having(
            (e) => e.violations.map((v) => v.code),
            'violations',
            contains('session_already_done'),
          ),
        ),
      );
    });

    test('and the refusal says so without validator vocabulary', () {
      const refused = AdaptationRefused(<Violation>[
        Violation('session_already_done', 'weekday 1 was already run'),
      ]);
      expect(refused.message, contains('already run'));
      expect(refused.message, isNot(contains('weekday')));
      expect(refused.message, isNot(contains('session_already_done')));
    });
  });

  group('with no model to hand, Dart still has an answer', () {
    test('a week that has diverged gets a deterministic refit', () async {
      // This used to be a flat null, and null reaches the runner as "try
      // telling me what you want differently" — advice that cannot work when
      // the coach is unreachable rather than confused.
      final soFar = diverged();
      final proposal = await AdaptationService(client: _AdaptClient(null))
          .propose(
            week: base,
            slot: slot,
            profile: profile,
            request: 'rebalance what is left',
            soFar: soFar,
          );

      expect(proposal, isNotNull);
      expect(proposal!.changes, isNotEmpty);
      // What happened is still there, and Wednesday is not claimed.
      expect(
        proposal.week.runOn(DateTime.monday)?.distanceMeters,
        base.runOn(DateTime.monday)?.distanceMeters,
      );
      expect(proposal.week.runOn(DateTime.wednesday), isNull);
      expect(
        validateWeek(
          proposal.week,
          slot,
          profile,
          rules: const PlanRules.adaptation(),
          soFar: soFar,
        ).isValid,
        isTrue,
      );
    });

    test('a week that has not diverged is left alone', () async {
      // The deterministic refit answers a *situation*, not a sentence. It knows
      // nothing about "make Sunday easier", and rearranging an on-track week in
      // reply to it is the generic reshuffle by another door.
      final proposal = await AdaptationService(client: _AdaptClient(null))
          .propose(
            week: base,
            slot: slot,
            profile: profile,
            request: 'make Sunday easier',
            soFar: standing(monday, const <RunSummary>[]),
          );
      expect(proposal, isNull);
    });

    test('and a provider that fell over is the same case', () async {
      final proposal =
          await AdaptationService(
            client: _AdaptClient(null, throwIt: true),
          ).propose(
            week: base,
            slot: slot,
            profile: profile,
            request: 'rebalance what is left',
            soFar: diverged(),
          );
      expect(proposal, isNotNull);
    });
  });
}
