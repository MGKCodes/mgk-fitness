import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_brief.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_builder.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_headline.dart';
import 'package:mgk_run/src/features/coaching/domain/session_effort.dart';
import 'package:mgk_run/src/features/coaching/presentation/session_labels.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_shape.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_validator.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

void main() {
  final now = DateTime(2026, 7, 27); // a Monday

  RunnerProfile block() => RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: DateTime(2026, 11, 16),
    currentWeeklyMeters: 40000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 4, 6, 7},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );

  RunnerProfile horizon() => RunnerProfile(
    goalDistanceMeters: 42195,
    currentWeeklyMeters: 40000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 4, 6, 7},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );

  /// The runner ADR-0011 exists for: parkrun every Saturday, no race, no block.
  RunnerProfile parkrunner() => const RunnerProfile(
    currentWeeklyMeters: 20000,
    longestRecentMeters: 8000,
    daysPerWeek: 3,
    availableWeekdays: <int>{2, 4, 6},
    commitments: <PlanCommitment>[
      PlanCommitment(
        weekday: DateTime.saturday,
        distanceMeters: 5000,
        label: 'parkrun',
        timed: true,
      ),
    ],
  );

  StoredPlan planFor(RunnerProfile profile) => StoredPlan(
    id: 'test',
    profile: profile,
    skeleton: buildSkeleton(profile, now: now),
    startDate: mondayOf(now),
  );

  group('the shape is read off the data', () {
    test('a goal and a date is a block', () {
      expect(shapeOf(block()), PlanShape.block);
    });

    test('a goal with no date is a horizon', () {
      expect(shapeOf(horizon()), PlanShape.horizon);
    });

    test('commitments with no goal are a rhythm', () {
      expect(shapeOf(parkrunner()), PlanShape.rhythm);
    });

    test('nothing stated at all is a log', () {
      const nothing = RunnerProfile(
        currentWeeklyMeters: 0,
        longestRecentMeters: 0,
        daysPerWeek: 0,
        availableWeekdays: <int>{},
      );
      expect(shapeOf(nothing), PlanShape.log);
    });
  });

  group('the skeleton follows the shape', () {
    test('only a block tapers', () {
      final blocked = buildSkeleton(block(), now: now);
      expect(blocked.weeks.last.phase, Phase.taper);

      final open = buildSkeleton(horizon(), now: now);
      expect(
        open.weeks.any((w) => w.phase == Phase.taper),
        isFalse,
        reason: 'a taper without a date is a guess about a race nobody entered',
      );
    });

    test('a horizon still ramps', () {
      final weeks = buildSkeleton(horizon(), now: now).weeks;
      expect(weeks.last.volumeMeters, greaterThan(weeks.first.volumeMeters));
    });

    test('a rhythm holds its level, with no deloads to come back from', () {
      final weeks = buildSkeleton(parkrunner(), now: now).weeks;
      expect(weeks.map((w) => w.volumeMeters).toSet(), hasLength(1));
      expect(weeks.any((w) => w.isDeload), isFalse);
    });
  });

  group('the validator judges each shape by its own rules', () {
    test('every shape validates against its own rule set', () {
      for (final profile in <RunnerProfile>[block(), horizon(), parkrunner()]) {
        final shape = shapeOf(profile);
        final skeleton = buildSkeleton(profile, now: now);
        final result = validateSkeleton(
          skeleton,
          profile,
          rules: PlanRules.forShape(shape),
        );
        expect(
          result.isValid,
          isTrue,
          reason: '${shape.name}: ${result.violations}',
        );
      }
    });

    test('block rules would wrongly reject a rhythm', () {
      // The reason the rule sets are split. Judged as a block, a plan that holds
      // a level has no taper and never deloads — both "violations" of rules
      // about a progression it is not making.
      final profile = parkrunner();
      final result = validateSkeleton(
        buildSkeleton(profile, now: now),
        profile,
      );
      expect(result.has('taper_missing'), isTrue);
    });
  });

  group('a rhythm week is built around what the runner committed to', () {
    test('parkrun stays on Saturday, at 5 km, and is the timed session', () {
      final profile = parkrunner();
      final skeleton = buildSkeleton(profile, now: now);
      final week = buildFallbackWeek(skeleton.weeks[0], profile);

      final saturday = week.runOn(DateTime.saturday);
      expect(saturday, isNotNull);
      expect(saturday!.distanceMeters, 5000);
      expect(
        saturday.kind.isHard,
        isTrue,
        reason: 'timed and repeated is how a rhythm runner measures themselves',
      );
    });

    // The flatness bug, back by a different route: one commitment and two free
    // days gave a parkrun runner 7 km and 7 km. A week has a shape whether or
    // not it is building toward anything.
    test('the free days are not an even split', () {
      final profile = parkrunner();
      final week = buildFallbackWeek(
        buildSkeleton(profile, now: now).weeks[0],
        profile,
      );
      final fillers = week.runs
          .where((s) => s.weekday != DateTime.saturday)
          .map((s) => s.distanceMeters)
          .toList();

      expect(fillers, hasLength(2));
      expect(fillers.toSet(), hasLength(2), reason: '$fillers');
    });

    test('the shorter free run sits nearest the commitment', () {
      // So the runner arrives at the thing they measure themselves by with
      // fresher legs than they left it with.
      final profile = parkrunner();
      final week = buildFallbackWeek(
        buildSkeleton(profile, now: now).weeks[0],
        profile,
      );
      final tuesday = week.runOn(DateTime.tuesday)!;
      final thursday = week.runOn(DateTime.thursday)!;
      expect(thursday.distanceMeters, lessThan(tuesday.distanceMeters));
    });

    test('the rest of the week fills the days they said they run', () {
      final profile = parkrunner();
      final skeleton = buildSkeleton(profile, now: now);
      final week = buildFallbackWeek(skeleton.weeks[0], profile);

      expect(week.runs, hasLength(3));
      for (final s in week.runs) {
        expect(profile.availableWeekdays, contains(s.weekday));
        expect(s.distanceMeters, greaterThan(0));
      }
    });
  });

  group('the headline says the right thing for each shape', () {
    test('a block counts down, a horizon does not', () {
      expect(planHeadline(planFor(block()), now).position, contains('days'));
      final open = planHeadline(planFor(horizon()), now);
      expect(open.goal, contains('Building toward'));
      expect(open.position, contains('no date set'));
    });

    test('a rhythm is named after what the runner calls it', () {
      final headline = planHeadline(planFor(parkrunner()), now);
      expect(headline.goal, contains('parkrun'));
      expect(headline.position, contains('3 runs a week'));
    });

    test('no plan of any shape is headed with a training phase', () {
      // This began as "a phase is only named for a plan that has phases" — the
      // fourth place block vocabulary leaked, and the one on Home. The phase is
      // gone for every shape now: even where it was real it was jargon on the
      // screen a runner opens in a hurry, under a header already saying "week 4
      // of 16" (ADR-0017).
      final rhythm = planFor(parkrunner()).skeleton.weeks.first;
      expect(todayHeading(parkrunner(), rhythm), 'Today');

      final building = planFor(block()).skeleton.weeks.first;
      expect(todayHeading(block(), building), 'Today');
    });

    test('one run a week is a run, not "1 runs"', () {
      // The commonest rhythm there is — one parkrun a week — read "1 runs a
      // week" at the top of the Coach tab.
      final once = const RunnerProfile(
        currentWeeklyMeters: 5000,
        longestRecentMeters: 5000,
        daysPerWeek: 1,
        availableWeekdays: <int>{DateTime.saturday},
        commitments: <PlanCommitment>[
          PlanCommitment(
            weekday: DateTime.saturday,
            distanceMeters: 5000,
            label: 'parkrun',
          ),
        ],
      );

      final headline = planHeadline(planFor(once), now);
      expect(headline.position, contains('1 run a week'));
      expect(headline.position, isNot(contains('1 runs')));
    });
  });

  group('the coach is briefed on the shape it is actually coaching', () {
    String briefFor(RunnerProfile profile) => CoachBrief.write(
      recentRuns: const <RunSummary>[],
      plan: planFor(profile),
      profile: profile,
      now: now,
    ).text;

    test('a rhythm runner is not told about a block they do not have', () {
      final brief = briefFor(parkrunner());
      expect(brief, contains('parkrun'));
      expect(brief, contains('Saturday'));
      // Not "isNot(contains('block'))" — the brief says "there is no race and
      // no block", which is the point. What must be absent is being *placed*
      // in one.
      expect(brief, isNot(contains('week 1 of')));
      expect(brief, isNot(contains('days out from the event')));
      expect(
        brief,
        contains('consistency'),
        reason: 'consistency is what they came for, and the coach is told so',
      );
    });

    test('a horizon runner is told there is no date to plan back from', () {
      final brief = briefFor(horizon());
      expect(brief, contains('no race entered'));
      expect(brief, isNot(contains('days out from the event')));
    });

    test('a block runner still gets the block briefing', () {
      final brief = briefFor(block());
      expect(brief, contains('block'));
      expect(brief, contains('days out from the event'));
    });
  });

  // Everything below was found by auditing the shape system against a real
  // parkrun runner rather than against the tests that were written with it.
  group('audit regressions', () {
    test('a rhythm never expires, and its weeks cycle', () {
      final profile = parkrunner();
      final plan = planFor(profile);
      final farFuture = now.add(const Duration(days: 400));

      expect(
        plan.hasEndedBy(farFuture),
        isFalse,
        reason: 'a habit is not a project that finishes',
      );
      // Week 57 of a 12-week materialisation is not a thing that can happen.
      final index = plan.weekIndexOn(farFuture);
      expect(index, inInclusiveRange(1, plan.skeleton.weeks.length));

      // A block still stops at its last week.
      final blockPlan = planFor(block());
      expect(blockPlan.hasEndedBy(farFuture), isTrue);
    });

    test('turning up is counted over a year, not since the plan row', () {
      // The bug: a parkrun regular of three years saw a count of zero, because
      // the plan row was created this morning.
      final profile = parkrunner();
      final plan = planFor(profile);
      final runs = <RunSummary>[
        for (var i = 1; i <= 10; i++)
          RunSummary(
            // Saturdays, all *before* the plan existed.
            startedAt: now.subtract(Duration(days: 7 * i + 2)),
            duration: const Duration(minutes: 26),
            distanceMeters: 5000,
            avgPaceSecondsPerKm: 312,
          ),
      ];

      expect(turnedUpCount(plan, runs, now: now), 10);
      expect(
        planHeadline(plan, now, completedThisPlan: 10).position,
        contains('10 parkruns'),
      );
    });

    test('only runs on the committed day count as that commitment', () {
      final plan = planFor(parkrunner());
      final runs = <RunSummary>[
        RunSummary(
          startedAt: now.subtract(const Duration(days: 2)), // Saturday
          duration: const Duration(minutes: 26),
          distanceMeters: 5000,
          avgPaceSecondsPerKm: 312,
        ),
        RunSummary(
          startedAt: now.subtract(const Duration(days: 5)), // Tuesday
          duration: const Duration(minutes: 40),
          distanceMeters: 7000,
          avgPaceSecondsPerKm: 343,
        ),
      ];
      expect(turnedUpCount(plan, runs, now: now), 1);
    });

    test('a rhythm is not promised a peak or a taper', () {
      final rhythm = planOutlook(planFor(parkrunner()));
      expect(rhythm.title, isNot(contains('block')));
      expect(rhythm.caption, isNot(contains('taper')));
      expect(rhythm.caption, contains('does not run out'));

      final open = planOutlook(planFor(horizon()));
      expect(open.caption, isNot(contains('then tapers')));

      final blocked = planOutlook(planFor(block()));
      expect(blocked.caption, contains('tapers'));
    });

    test('a timed commitment is a time trial, named as the runner names it', () {
      // Calling a parkrun a threshold session tells the runner to hold an
      // effort they could sustain for an hour, which is not how anyone runs one.
      final profile = parkrunner();
      final week = buildFallbackWeek(
        buildSkeleton(profile, now: now).weeks[0],
        profile,
      );
      final saturday = week.runOn(DateTime.saturday)!;

      expect(saturday.kind, SessionKind.timeTrial);
      expect(sessionLabel(saturday), 'parkrun');
      expect(effortFor(saturday.kind).rpeHigh, 10);
    });

    test('every plan is validated by its own shape, wherever it is built', () {
      // The repository held one rule set, so creating a rhythm plan failed
      // outright — the Coach tab hung on a spinner.
      for (final profile in <RunnerProfile>[block(), horizon(), parkrunner()]) {
        final skeleton = buildSkeleton(profile, now: now);
        expect(
          validateSkeleton(
            skeleton,
            profile,
            rules: PlanRules.forShape(shapeOf(profile)),
          ).isValid,
          isTrue,
          reason: shapeOf(profile).name,
        );
      }
    });
  });
}
