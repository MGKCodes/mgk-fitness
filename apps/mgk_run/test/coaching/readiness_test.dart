import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_brief.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_headline.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_shape.dart';
import 'package:mgk_run/src/features/coaching/domain/readiness.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

void main() {
  final now = DateTime(2026, 7, 27);

  RunnerProfile horizon({
    double goal = 42195,
    double weekly = 40000,
    double longest = 18000,
  }) => RunnerProfile(
    goalDistanceMeters: goal,
    currentWeeklyMeters: weekly,
    longestRecentMeters: longest,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 4, 6, 7},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );

  StoredPlan planFor(RunnerProfile profile) => StoredPlan(
    id: 'test',
    profile: profile,
    skeleton: buildSkeleton(profile, now: now),
    startDate: mondayOf(now),
  );

  RunSummary run(double meters, {int daysAgo = 7}) => RunSummary(
    startedAt: now.subtract(Duration(days: daysAgo)),
    duration: Duration(seconds: (meters / 1000 * 330).round()),
    distanceMeters: meters,
    avgPaceSecondsPerKm: 330,
  );

  group('what the goal asks for', () {
    test('a short race wants you to have run the distance', () {
      final r = assessReadiness(
        horizon(goal: 10000),
        const <RunSummary>[],
        now: now,
      )!;
      expect(r.longestNeededMeters, 10000);
    });

    test('a marathon does not', () {
      // Nobody runs a marathon in training. The taper and the day carry the
      // last stretch, and a plan that demanded 42 km would be dangerous advice.
      final r = assessReadiness(horizon(), const <RunSummary>[], now: now)!;
      expect(r.longestNeededMeters, closeTo(31646, 200));
      expect(r.longestNeededMeters / 42195, lessThan(0.8));
    });

    test('the week has to support the long run, not just contain it', () {
      final r = assessReadiness(horizon(), const <RunSummary>[], now: now)!;
      expect(r.weeklyNeededMeters, r.longestNeededMeters * 2);
    });
  });

  group('being ready needs both halves', () {
    test('one heroic run off nothing is not ready', () {
      // The failure this guards: averaging the two signals would call this
      // runner ready, and being wrong in the encouraging direction is how
      // somebody gets hurt.
      final r = assessReadiness(
        horizon(weekly: 20000, longest: 33000),
        const <RunSummary>[],
        now: now,
      )!;
      expect(r.isReady, isFalse);
      expect(r.fraction, lessThan(0.65));
    });

    test('big weeks with no long run is not ready either', () {
      final r = assessReadiness(
        horizon(weekly: 80000, longest: 12000),
        const <RunSummary>[],
        now: now,
      )!;
      expect(r.isReady, isFalse);
    });

    test('both there is ready', () {
      final r = assessReadiness(
        horizon(weekly: 70000, longest: 33000),
        const <RunSummary>[],
        now: now,
      )!;
      expect(r.isReady, isTrue);
      expect(r.summary, 'ready for it now');
    });
  });

  group('the run log outranks the profile', () {
    test('a longer run since intake counts', () {
      // A profile ages. Someone who said 12 km three months ago and has since
      // run 33 km is ready on the evidence, and asking them to re-state it
      // would be the app ignoring what it already knows.
      final profile = horizon(weekly: 70000, longest: 12000);
      expect(
        assessReadiness(profile, const <RunSummary>[], now: now)!.isReady,
        isFalse,
      );
      expect(
        assessReadiness(profile, <RunSummary>[run(33000)], now: now)!.isReady,
        isTrue,
      );
    });

    test('last winter does not count', () {
      final profile = horizon(weekly: 70000, longest: 12000);
      final stale = <RunSummary>[run(33000, daysAgo: 200)];
      expect(assessReadiness(profile, stale, now: now)!.isReady, isFalse);
    });
  });

  group('only a shape with something to reach has a readiness', () {
    test('a rhythm has none', () {
      const parkrunner = RunnerProfile(
        currentWeeklyMeters: 20000,
        longestRecentMeters: 8000,
        daysPerWeek: 3,
        availableWeekdays: <int>{2, 4, 6},
        commitments: <PlanCommitment>[
          PlanCommitment(weekday: DateTime.saturday, distanceMeters: 5000),
        ],
      );
      expect(
        assessReadiness(parkrunner, const <RunSummary>[], now: now),
        isNull,
      );
    });
  });

  group('the moment reaches the runner and the coach', () {
    test('the headline counts readiness, not a week number alone', () {
      final profile = horizon();
      final headline = planHeadline(
        planFor(profile),
        now,
        readiness: assessReadiness(profile, const <RunSummary>[], now: now),
      );
      expect(headline.position, contains('week 1'));
      expect(headline.position, isNot(contains('no date set')));
    });

    test('the card asks the question once they are ready', () {
      final profile = horizon(weekly: 70000, longest: 33000);
      final outlook = planOutlook(
        planFor(profile),
        readiness: assessReadiness(profile, const <RunSummary>[], now: now),
      );
      expect(outlook.caption, contains('could run a marathon now'));
      expect(outlook.caption, contains('enter'));
    });

    test('and says nothing of the sort before then', () {
      final profile = horizon(weekly: 30000, longest: 14000);
      final outlook = planOutlook(
        planFor(profile),
        readiness: assessReadiness(profile, const <RunSummary>[], now: now),
      );
      expect(outlook.caption, isNot(contains('could run')));
      expect(outlook.caption, contains('no end date'));
    });

    test('the coach is given the numbers, not an impression', () {
      final ready = horizon(weekly: 70000, longest: 33000);
      final briefed = CoachBrief.write(
        recentRuns: const <RunSummary>[],
        plan: planFor(ready),
        profile: ready,
        now: now,
      ).text;
      expect(briefed, contains('could cover the distance now'));
      expect(briefed, contains('want to find a race'));

      final notYet = horizon(weekly: 30000, longest: 14000);
      final early = CoachBrief.write(
        recentRuns: const <RunSummary>[],
        plan: planFor(notYet),
        profile: notYet,
        now: now,
      ).text;
      expect(early, contains('Do not tell them they are ready'));
      expect(
        early,
        contains('32 km'),
        reason: 'the target is a number the model cannot get wrong',
      );
    });
  });
}
