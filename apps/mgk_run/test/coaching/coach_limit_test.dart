import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/data/adaptation_service.dart';
import 'package:mgk_run/src/features/coaching/data/coach_errors.dart';
import 'package:mgk_run/src/features/coaching/data/plan_client.dart';
import 'package:mgk_run/src/features/coaching/data/plan_service.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/presentation/week_adjust_sheet.dart';

/// Counts calls and always refuses with a limit.
class _LimitedClient implements PlanClient {
  _LimitedClient({this.spendCapped = false, this.retryAfterSeconds = 300});

  final bool spendCapped;
  final int? retryAfterSeconds;
  int skeletonCalls = 0;
  int weekCalls = 0;
  int adaptCalls = 0;

  CoachLimitException get _limit => CoachLimitException(
    scope: spendCapped ? 'daily_spend' : 'skeleton',
    retryAfterSeconds: retryAfterSeconds,
    spendCapped: spendCapped,
  );

  @override
  Future<PlanSkeleton?> proposeSkeleton({
    required RunnerProfile profile,
    List<String> violations = const <String>[],
  }) async {
    skeletonCalls++;
    throw _limit;
  }

  @override
  Future<TrainingWeek?> proposeWeek({
    required SkeletonWeek slot,
    required RunnerProfile profile,
    List<String> violations = const <String>[],
    int? raceWeekday,
  }) async {
    weekCalls++;
    throw _limit;
  }

  @override
  Future<TrainingWeek?> proposeAdaptation({
    required TrainingWeek week,
    required SkeletonWeek slot,
    required RunnerProfile profile,
    required String request,
  }) async {
    adaptCalls++;
    throw _limit;
  }
}

/// Fails every call with an ordinary error, for contrast.
class _BrokenClient implements PlanClient {
  int skeletonCalls = 0;

  @override
  Future<PlanSkeleton?> proposeSkeleton({
    required RunnerProfile profile,
    List<String> violations = const <String>[],
  }) async {
    skeletonCalls++;
    throw Exception('socket closed');
  }

  @override
  Future<TrainingWeek?> proposeWeek({
    required SkeletonWeek slot,
    required RunnerProfile profile,
    List<String> violations = const <String>[],
    int? raceWeekday,
  }) async => null;

  @override
  Future<TrainingWeek?> proposeAdaptation({
    required TrainingWeek week,
    required SkeletonWeek slot,
    required RunnerProfile profile,
    required String request,
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
  final week = buildFallbackWeek(slot, profile);

  group('the message tells the runner how long to wait', () {
    test('a rate limit rounds the wait up to whole minutes', () {
      const e = CoachLimitException(
        scope: 'skeleton',
        retryAfterSeconds: 200,
        spendCapped: false,
      );
      expect(e.message, contains('4 minutes'));
    });

    test('a short wait stays in seconds, singular minute is not plural', () {
      const seconds = CoachLimitException(
        scope: 'intake',
        retryAfterSeconds: 30,
        spendCapped: false,
      );
      expect(seconds.message, contains('30 seconds'));

      const one = CoachLimitException(
        scope: 'intake',
        retryAfterSeconds: 60,
        spendCapped: false,
      );
      expect(one.message, contains('1 minute'));
      expect(one.message, isNot(contains('1 minutes')));
    });

    test('the spend cap reads as an allowance, not as being too fast', () {
      const e = CoachLimitException(
        scope: 'daily_spend',
        retryAfterSeconds: 7200,
        spendCapped: true,
      );
      expect(e.message, contains('allowance'));
      expect(e.message, contains('2 hours'));
    });

    test('an absent retry hint does not invent one', () {
      const e = CoachLimitException(
        scope: 'week',
        retryAfterSeconds: null,
        spendCapped: false,
      );
      expect(e.message, isNot(contains('null')));
      expect(e.message, contains('shortly'));
    });
  });

  group('PlanService', () {
    // The point of the typed error: a 429 is certain to be refused again until
    // the window clears, so spending the second of two attempts on it wastes
    // the runner's own allowance.
    test(
      'does not retry a refused request, and says why it fell back',
      () async {
        final client = _LimitedClient();
        final service = PlanService(client: client, now: () => now);

        final result = await service.generateSkeleton(profile);

        expect(client.skeletonCalls, 1, reason: 'must not retry a limit');
        expect(result.isFallback, isTrue);
        expect(result.limit, isNotNull);
        expect(result.limit!.spendCapped, isFalse);
      },
    );

    test('still retries an ordinary failure twice', () async {
      final client = _BrokenClient();
      final service = PlanService(client: client, now: () => now);

      final result = await service.generateSkeleton(profile);

      expect(client.skeletonCalls, 2, reason: 'ordinary misses still retry');
      expect(result.isFallback, isTrue);
      expect(result.limit, isNull, reason: 'not a limit — nothing to explain');
    });

    test('a limited week falls back once, flagged', () async {
      final client = _LimitedClient();
      final service = PlanService(client: client, now: () => now);

      final result = await service.generateWeek(slot, profile);

      expect(client.weekCalls, 1);
      expect(result.isFallback, isTrue);
      expect(result.limit, isNotNull);
      expect(result.plan.provisional, isTrue);
    });
  });

  group('AdaptationService', () {
    // There is no deterministic adaptation to fall back on, so this must not be
    // flattened into the same null as "the coach produced nothing usable".
    test('lets a limit through rather than reporting no proposal', () async {
      final service = AdaptationService(client: _LimitedClient());

      await expectLater(
        service.propose(
          week: week,
          slot: slot,
          profile: profile,
          request: 'move tuesday',
        ),
        throwsA(isA<CoachLimitException>()),
      );
    });
  });

  testWidgets('the adjust sheet shows the allowance, not "try rephrasing"', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeekAdjustSheet(
            adaptation: AdaptationService(
              client: _LimitedClient(
                spendCapped: true,
                retryAfterSeconds: 3600,
              ),
            ),
            week: week,
            slot: slot,
            profile: profile,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'skip thursday');
    await tester.tap(find.text('Ask the coach'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();

    expect(find.textContaining('allowance'), findsOneWidget);
    expect(find.textContaining('rephrasing'), findsNothing);
  });
}
