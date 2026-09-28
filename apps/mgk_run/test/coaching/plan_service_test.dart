import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/data/plan_client.dart';
import 'package:mgk_run/src/features/coaching/data/plan_service.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_validator.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';

/// Returns queued proposals in order (null once exhausted), recording the
/// violations passed on each call, and can be made to throw.
class _FakePlanClient implements PlanClient {
  _FakePlanClient({
    List<PlanSkeleton?>? skeletons,
    List<TrainingWeek?>? weeks,
    this.throwEvery = false,
  }) : _skeletons = skeletons ?? const <PlanSkeleton?>[],
       _weeks = weeks ?? const <TrainingWeek?>[];

  final List<PlanSkeleton?> _skeletons;
  final List<TrainingWeek?> _weeks;
  final bool throwEvery;
  final List<List<String>> skeletonViolations = <List<String>>[];
  final List<List<String>> weekViolations = <List<String>>[];
  int _sk = 0;
  int _wk = 0;

  @override
  Future<PlanSkeleton?> proposeSkeleton({
    required RunnerProfile profile,
    List<String> violations = const <String>[],
  }) async {
    skeletonViolations.add(violations);
    if (throwEvery) throw Exception('provider down');
    return _sk < _skeletons.length ? _skeletons[_sk++] : null;
  }

  @override
  Future<TrainingWeek?> proposeWeek({
    required SkeletonWeek slot,
    required RunnerProfile profile,
    List<String> violations = const <String>[],
    int? raceWeekday,
  }) async {
    weekViolations.add(violations);
    if (throwEvery) throw Exception('provider down');
    return _wk < _weeks.length ? _weeks[_wk++] : null;
  }

  @override
  Future<TrainingWeek?> proposeAdaptation({
    required TrainingWeek week,
    required SkeletonWeek slot,
    required RunnerProfile profile,
    required String request,
  }) async => null; // not exercised here
}

void main() {
  final now = DateTime(2026, 7, 25);
  final profile = RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: DateTime(2026, 11, 1),
    currentWeeklyMeters: 40000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 4, 6, 7},
  );
  final skeleton = buildSkeleton(profile, now: now, weeks: 12);
  final slot = skeleton.weeks[5];

  PlanSkeleton badSkeleton() {
    final weeks = skeleton.weeks.toList();
    // Week 1 far from current volume -> week1_volume violation.
    weeks[0] = const SkeletonWeek(
      index: 1,
      phase: Phase.base,
      volumeMeters: 999999,
      longRunMeters: 5000,
    );
    return PlanSkeleton(weeks: weeks);
  }

  // A valid week as the *model* would return it: the deterministic layout is
  // valid, but a model proposal is not provisional (only the fallback is).
  TrainingWeek goodWeek() {
    final base = buildFallbackWeek(slot, profile);
    return TrainingWeek(
      skeletonIndex: base.skeletonIndex,
      sessions: base.sessions,
    );
  }

  TrainingWeek badWeek() {
    final sessions = goodWeek().sessions.toList();
    // Move a session to Wednesday, which is not available -> unavailable_day.
    sessions[1] = PlannedSession(
      weekday: DateTime.wednesday,
      kind: sessions[1].kind,
      distanceMeters: sessions[1].distanceMeters,
    );
    return TrainingWeek(skeletonIndex: slot.index, sessions: sessions);
  }

  PlanService service(_FakePlanClient client) =>
      PlanService(client: client, now: () => now);

  test('a valid skeleton on the first attempt is used', () async {
    final client = _FakePlanClient(skeletons: <PlanSkeleton?>[skeleton]);
    final res = await service(client).generateSkeleton(profile);

    expect(res.source, PlanSource.model);
    expect(res.modelAttempts, 1);
    expect(identical(res.plan, skeleton), isTrue);
    expect(client.skeletonViolations.single, isEmpty);
  });

  test(
    'an invalid skeleton retries with violations fed back, then uses it',
    () async {
      final client = _FakePlanClient(
        skeletons: <PlanSkeleton?>[badSkeleton(), skeleton],
      );
      final res = await service(client).generateSkeleton(profile);

      expect(res.source, PlanSource.model);
      expect(res.modelAttempts, 2);
      expect(client.skeletonViolations.first, isEmpty); // first try, no context
      expect(client.skeletonViolations[1].join(' '), contains('week1_volume'));
    },
  );

  test(
    'two invalid skeletons fall back to a valid deterministic plan',
    () async {
      final client = _FakePlanClient(
        skeletons: <PlanSkeleton?>[badSkeleton(), badSkeleton()],
      );
      final res = await service(client).generateSkeleton(profile);

      expect(res.source, PlanSource.fallback);
      expect(res.isFallback, isTrue);
      expect(validateSkeleton(res.plan, profile).isValid, isTrue);
    },
  );

  test('a thrown proposal falls back rather than failing the runner', () async {
    final client = _FakePlanClient(throwEvery: true);
    final res = await service(client).generateSkeleton(profile);

    expect(res.source, PlanSource.fallback);
    expect(validateSkeleton(res.plan, profile).isValid, isTrue);
  });

  test('a valid week is used and is not provisional', () async {
    final client = _FakePlanClient(weeks: <TrainingWeek?>[goodWeek()]);
    final res = await service(client).generateWeek(slot, profile);

    expect(res.source, PlanSource.model);
    expect(res.plan.provisional, isFalse);
  });

  test('two invalid weeks fall back to a valid provisional week', () async {
    final client = _FakePlanClient(
      weeks: <TrainingWeek?>[badWeek(), badWeek()],
    );
    final res = await service(client).generateWeek(slot, profile);

    expect(res.source, PlanSource.fallback);
    expect(res.plan.provisional, isTrue);
    expect(validateWeek(res.plan, slot, profile).isValid, isTrue);
    expect(client.weekViolations[1].join(' '), contains('unavailable_day'));
  });
}
