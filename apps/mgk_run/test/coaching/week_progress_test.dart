import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/session_status.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/training_plan.dart';
import 'package:mgk_run/src/features/coaching/domain/week_progress.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

/// Completion is **observed, not asserted** (ADR-0017). These pin the rule that
/// replaced a button: a prescribed day is done when a run exists on it, and a
/// day nobody ran is missed once it has passed — never before.
void main() {
  // 2026-07-27 is a Monday.
  final monday = DateTime(2026, 7, 27);

  RunSummary runAt(DateTime at, {double meters = 8000}) => RunSummary(
    startedAt: at,
    duration: const Duration(minutes: 41),
    distanceMeters: meters,
  );

  TrainingWeek weekOf(List<int> weekdays) => TrainingWeek(
    skeletonIndex: 1,
    sessions: <PlannedSession>[
      for (final d in weekdays)
        PlannedSession(
          weekday: d,
          kind: d == 7 ? SessionKind.long : SessionKind.easy,
          distanceMeters: d == 7 ? 17000 : 8000,
        ),
    ],
  );

  group('a day is done when a run exists on it', () {
    test('any run on the day counts, at any distance', () {
      // Deliberately looser than the rhythm turn-up count: telling a runner who
      // covered 8.5 km of a prescribed 9 km that they missed it is being right
      // about a number and wrong about a person.
      expect(
        outcomeOn(
          date: monday,
          now: addDays(monday, 2),
          runs: <RunSummary>[runAt(monday, meters: 2000)],
        ),
        DayOutcome.done,
      );
    });

    test('the time of day does not matter, only the date', () {
      expect(
        outcomeOn(
          date: monday,
          now: addDays(monday, 1),
          runs: <RunSummary>[runAt(DateTime(2026, 7, 27, 23, 40))],
        ),
        DayOutcome.done,
      );
    });

    test('a run on a different day does not complete this one', () {
      expect(
        outcomeOn(
          date: monday,
          now: addDays(monday, 2),
          runs: <RunSummary>[runAt(addDays(monday, 1))],
        ),
        DayOutcome.missed,
      );
    });
  });

  group('today is never missed', () {
    test('an unrun session today is still today, not a failure', () {
      expect(
        outcomeOn(date: monday, now: monday, runs: const <RunSummary>[]),
        DayOutcome.today,
        reason: 'the evening is still theirs',
      );
    });

    test('and the same session is missed tomorrow', () {
      expect(
        outcomeOn(
          date: monday,
          now: addDays(monday, 1),
          runs: const <RunSummary>[],
        ),
        DayOutcome.missed,
      );
    });

    test('a future day is upcoming', () {
      expect(
        outcomeOn(
          date: addDays(monday, 3),
          now: monday,
          runs: const <RunSummary>[],
        ),
        DayOutcome.upcoming,
      );
    });

    test('an explicit skip outranks a miss, but a run outranks both', () {
      expect(
        outcomeOn(
          date: monday,
          now: addDays(monday, 2),
          runs: const <RunSummary>[],
          status: SessionStatus.skipped,
        ),
        DayOutcome.skipped,
      );
      expect(
        outcomeOn(
          date: monday,
          now: addDays(monday, 2),
          runs: <RunSummary>[runAt(monday)],
          status: SessionStatus.skipped,
        ),
        DayOutcome.done,
        reason: 'they said they would skip it and then went anyway',
      );
    });
  });

  group('a week reads as what happened', () {
    test('rest days are absent rather than present and empty', () {
      final outcomes = weekOutcomes(
        week: weekOf(<int>[1, 3, 7]),
        weekStart: monday,
        now: addDays(monday, 3),
        runs: <RunSummary>[runAt(monday)],
      );

      expect(outcomes.keys.toSet(), <int>{1, 3, 7});
      expect(outcomes[1], DayOutcome.done);
      expect(outcomes[3], DayOutcome.missed);
      expect(outcomes[7], DayOutcome.upcoming);
    });
  });

  group('what is worth raising', () {
    MissedPrompt? promptOn(
      DateTime now, {
      List<RunSummary> runs = const <RunSummary>[],
      List<int> weekdays = const <int>[1, 3, 7],
    }) => missedPromptFor(
      week: weekOf(weekdays),
      weekStart: monday,
      now: now,
      runs: runs,
    );

    test('nothing missed, nothing said', () {
      expect(promptOn(monday), isNull);
    });

    test('one easy run that got away is not an incident', () {
      // It reaches the coach through the brief, which is where a pattern would
      // show up. A prompt for every missed Tuesday is a nag, not a coach.
      expect(promptOn(addDays(monday, 1)), isNull);
    });

    test('a missed long run is raised — the block hangs on it', () {
      final prompt = promptOn(
        addDays(monday, 8),
        // Ran Monday and Wednesday, so only Sunday's long run is outstanding.
        runs: <RunSummary>[runAt(monday), runAt(addDays(monday, 2))],
      );

      expect(prompt, isNotNull);
      expect(prompt!.headline, contains('Sunday'));
      expect(prompt.missed.single.isKey, isTrue);
    });

    test('two misses in a week are raised even when neither is key', () {
      final prompt = promptOn(addDays(monday, 4), weekdays: <int>[1, 2, 3]);

      expect(prompt, isNotNull);
      expect(prompt!.missed, hasLength(3));
      expect(prompt.headline, contains('3 sessions missed'));
    });

    test('both answers are sentences for the coach, not writes', () {
      final prompt = promptOn(
        addDays(monday, 8),
        runs: <RunSummary>[runAt(monday), runAt(addDays(monday, 2))],
      )!;

      // The first question a coach asks is whether they actually missed it.
      expect(prompt.logOpener.toLowerCase(), contains('did run'));
      expect(prompt.adjustOpener.toLowerCase(), contains('rebalance'));
    });
  });

  group('a plan cannot be behind on days that predate it', () {
    // Found by building a real plan on a Thursday: Home greeted its brand-new
    // owner with "3 sessions missed this week — Monday, Tuesday, Wednesday",
    // for days the plan did not exist for.
    test('a day before the plan started is never missed', () {
      final wednesday = addDays(monday, 2);
      expect(
        outcomeOn(
          date: monday,
          now: addDays(monday, 3),
          runs: const <RunSummary>[],
          since: wednesday,
        ),
        DayOutcome.upcoming,
        reason: 'the plan was not asking for anything on Monday',
      );
    });

    test('and a day after it still is', () {
      final wednesday = addDays(monday, 2);
      expect(
        outcomeOn(
          date: wednesday,
          now: addDays(monday, 4),
          runs: const <RunSummary>[],
          since: wednesday,
        ),
        DayOutcome.missed,
      );
    });

    // `startDate` is the Monday week 1 aligns to, never the day the runner
    // committed — so passing it straight through was a guard that could not
    // fire, and a plan built on a Thursday still opened by listing Monday,
    // Tuesday and Wednesday as missed. The caller passes today for a first
    // week instead; this pins what that buys.
    test('passing the week Monday guards nothing, which is the trap', () {
      final thursday = addDays(monday, 3);
      final prompt = missedPromptFor(
        week: weekOf(<int>[1, 2, 3, 4, 7]),
        weekStart: monday,
        now: thursday,
        runs: const <RunSummary>[],
        since: monday,
      );
      expect(
        prompt,
        isNotNull,
        reason: 'startDate is always the Monday, so it excludes nothing',
      );
      expect(prompt!.missed, hasLength(3));
    });

    test('a plan made today raises nothing about this week', () {
      final thursday = addDays(monday, 3);
      expect(
        missedPromptFor(
          week: weekOf(<int>[1, 2, 3, 4, 7]),
          weekStart: monday,
          now: thursday,
          runs: const <RunSummary>[],
          since: thursday,
        ),
        isNull,
        reason: 'a new plan accusing its owner is the worst possible opening',
      );
    });
  });
}
