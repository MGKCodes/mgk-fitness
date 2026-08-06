import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/core/units/unit_system.dart';
import 'package:mgk_run/src/features/coaching/data/plan_repository.dart';
import 'package:mgk_run/src/features/coaching/data/plan_store.dart';
import 'package:mgk_run/src/features/coaching/domain/coach_brief.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_history.dart';
import 'package:mgk_run/src/features/coaching/domain/runner_profile.dart';
import 'package:mgk_run/src/features/coaching/domain/stored_plan.dart';
import 'package:mgk_run/src/features/recording/domain/run_summary.dart';

RunSummary run({
  required DateTime at,
  required double meters,
  double? paceSecondsPerKm,
  Duration duration = const Duration(minutes: 30),
}) => RunSummary(
  startedAt: at,
  duration: duration,
  distanceMeters: meters,
  avgPaceSecondsPerKm: paceSecondsPerKm,
);

void main() {
  final now = DateTime(2026, 7, 26);

  RunnerProfile profile() => RunnerProfile(
    goalDistanceMeters: 42195,
    eventDate: DateTime(2026, 11, 15),
    currentWeeklyMeters: 45000,
    longestRecentMeters: 18000,
    daysPerWeek: 5,
    availableWeekdays: const <int>{1, 2, 4, 6, 7},
    timeTrialDistanceMeters: 5000,
    timeTrialDuration: const Duration(minutes: 22),
  );

  Future<StoredPlan> plan() => PlanRepository(
    store: InMemoryPlanStore(),
    now: () => now,
  ).create(profile());

  group('it reads as prose, not as a record', () {
    test('no braces, brackets or key-value pairs reach the model', () async {
      final brief = CoachBrief.write(
        recentRuns: <RunSummary>[
          run(at: now.subtract(const Duration(days: 1)), meters: 8200),
        ],
        plan: await plan(),
        now: now,
      );

      // The whole point: a struct in a prompt gets recited back at the runner.
      for (final token in <String>['{', '}', '[', ']', '":', '_']) {
        expect(
          brief.text,
          isNot(contains(token)),
          reason: 'a brief containing "$token" reads as data to be quoted',
        );
      }
    });

    test('dates are relative, because the model does not know today', () async {
      final brief = CoachBrief.write(
        recentRuns: <RunSummary>[
          run(at: now.subtract(const Duration(days: 1)), meters: 8200),
        ],
        plan: await plan(),
        now: now,
      );

      expect(brief.text, contains('yesterday'));
      expect(brief.text, isNot(contains('2026')));
    });
  });

  group('every number is one the app can defend', () {
    test('projections come from Riegel, not from the model', () async {
      final brief = CoachBrief.write(
        recentRuns: const <RunSummary>[],
        profile: profile(),
        now: now,
      );

      // 5 km in 22:00 → a shade over 1:42 for the half by Riegel.
      expect(brief.text, contains('21 km in about 1:4'));
      expect(brief.text, contains('42 km in about'));
    });

    test('a long extrapolation is flagged rather than promised', () async {
      final brief = CoachBrief.write(
        recentRuns: const <RunSummary>[],
        profile: profile(),
        now: now,
      );

      // 5 km → marathon is more than eight times the distance; Riegel is
      // optimistic there and the brief must not present it as a promise.
      expect(brief.text, contains('if the endurance is there'));
    });

    test('the reference distance is not projected back to itself', () async {
      final brief = CoachBrief.write(
        recentRuns: const <RunSummary>[],
        profile: profile(),
        now: now,
      );
      expect(
        '5 km in about'.allMatches(brief.text).length,
        0,
        reason: 'projecting a 5 km time trial to 5 km says nothing',
      );
    });

    test('imperial renders throughout, not just in places', () async {
      final brief = CoachBrief.write(
        recentRuns: <RunSummary>[
          run(at: now.subtract(const Duration(days: 2)), meters: 8200),
        ],
        profile: profile(),
        unit: UnitSystem.imperial,
        now: now,
      );

      expect(brief.text, contains('mi'));
      expect(brief.text, isNot(contains(' km')));
    });
  });

  group('it says what is true and no more', () {
    test('a runner with nothing yet gets an honest opening', () {
      final brief = CoachBrief.write(
        recentRuns: const <RunSummary>[],
        now: now,
      );
      expect(brief.text, contains('not coached this runner before'));
      expect(brief.text, isNot(contains('week')));
    });

    test('no plan is described as training by feel, not as a gap', () {
      final brief = CoachBrief.write(
        recentRuns: const <RunSummary>[],
        profile: profile(),
        now: now,
      );
      expect(brief.text, contains('no plan in place'));
      expect(brief.text, contains('by feel'));
    });

    test('a quiet week is stated, not glossed over', () {
      final brief = CoachBrief.write(
        recentRuns: <RunSummary>[
          run(at: now.subtract(const Duration(days: 20)), meters: 8200),
        ],
        profile: profile(),
        now: now,
      );
      expect(brief.text, contains('not run in the past week'));
    });

    test('the rolling summary is carried through verbatim', () async {
      const summary =
          'Nervous about the distance. Has tried and abandoned two marathon '
          'blocks before, both times around week eight.';
      final brief = CoachBrief.write(
        recentRuns: const <RunSummary>[],
        plan: await plan(),
        rollingSummary: summary,
        now: now,
      );
      expect(brief.text, contains(summary));
    });
  });

  group('the days they cannot run', () {
    // Regression, found live. Asked to move a session to a Friday the runner
    // had ruled out, the coach agreed and returned a week with the session
    // deleted — because nothing in the brief said Friday was out. It could only
    // learn the constraint by breaking it.
    test('both halves are named, not just the days that are free', () {
      final brief = CoachBrief.write(
        recentRuns: const <RunSummary>[],
        profile: profile(), // free on 1, 2, 4, 6, 7
        now: now,
      );
      expect(
        brief.text,
        contains(
          'Monday, Tuesday, Thursday, Saturday and '
          'Sunday',
        ),
      );
      expect(
        brief.text,
        contains('cannot run on Wednesday and Friday'),
        reason: 'the days they ruled out are the ones worth stating',
      );
    });

    test('and it is told not to offer them', () {
      final brief = CoachBrief.write(
        recentRuns: const <RunSummary>[],
        profile: profile(),
        now: now,
      );
      // Answering in the conversation is cheaper and truer than proposing a
      // week the validator will refuse for a reason the runner did not ask
      // about.
      expect(brief.text, contains('do not offer to move a session onto'));
    });

    test('a runner free every day gets no paragraph about it', () {
      final brief = CoachBrief.write(
        recentRuns: const <RunSummary>[],
        profile: RunnerProfile(
          currentWeeklyMeters: 20000,
          longestRecentMeters: 8000,
          daysPerWeek: 4,
          availableWeekdays: const <int>{1, 2, 3, 4, 5, 6, 7},
        ),
        now: now,
      );
      expect(brief.text, isNot(contains('cannot run on')));
    });

    test('one ruled-out day reads as a day, not as days', () {
      final brief = CoachBrief.write(
        recentRuns: const <RunSummary>[],
        profile: RunnerProfile(
          currentWeeklyMeters: 20000,
          longestRecentMeters: 8000,
          daysPerWeek: 4,
          availableWeekdays: const <int>{1, 2, 3, 4, 5, 6},
        ),
        now: now,
      );
      expect(brief.text, contains('cannot run on Sunday'));
      expect(brief.text, contains('onto that day'));
    });
  });

  group('what they have trained for before', () {
    // Every plan Runio built was still on disk and nothing read it back, so the
    // coach met a runner three marathon blocks in as a beginner.
    List<LabelledPlan> history({
      required DateTime start,
      DateTime? event,
      DateTime? endedAt,
      double? goal = 42195,
      int weeks = 16,
    }) => labelPlans(<PlanRecord>[
      PlanRecord(
        id: 'old',
        startDate: start,
        weeks: weeks,
        isActive: false,
        goalDistanceMeters: goal,
        eventDate: event,
        endedAt: endedAt,
      ),
      PlanRecord(
        id: 'now',
        startDate: now,
        weeks: 16,
        isActive: true,
        goalDistanceMeters: 42195,
        eventDate: DateTime(2026, 11, 15),
      ),
    ]);

    test('a finished block is credited', () {
      final brief = CoachBrief.write(
        recentRuns: const <RunSummary>[],
        profile: profile(),
        history: history(
          start: DateTime(2025, 1, 6),
          event: DateTime(2025, 4, 20),
          endedAt: DateTime(2025, 5, 1),
        ),
        now: now,
      );
      expect(brief.text, contains('one plan before this'));
      expect(brief.text, contains('saw one of them through'));
    });

    test('an unfinished one names the week they stopped at', () {
      final brief = CoachBrief.write(
        recentRuns: const <RunSummary>[],
        profile: profile(),
        history: history(
          start: DateTime(2025, 1, 6),
          event: DateTime(2025, 4, 20),
          endedAt: DateTime(2025, 3, 5),
        ),
        now: now,
      );
      expect(brief.text, contains('week 9 of 16'));
      // Not something to open with, like every other fact in the brief.
      expect(brief.text, contains('Do not bring this up unless'));
    });

    test('no history adds no paragraph at all', () {
      final brief = CoachBrief.write(
        recentRuns: const <RunSummary>[],
        profile: profile(),
        now: now,
      );
      expect(brief.text, isNot(contains('before this')));
    });

    test('it stays prose, with nothing to recite', () {
      final brief = CoachBrief.write(
        recentRuns: const <RunSummary>[],
        profile: profile(),
        history: history(
          start: DateTime(2025, 1, 6),
          event: DateTime(2025, 4, 20),
          endedAt: DateTime(2025, 3, 5),
        ),
        unit: UnitSystem.imperial,
        now: now,
      );
      for (final token in <String>['{', '}', '[', ']', '":', '_']) {
        expect(brief.text, isNot(contains(token)));
      }
      // And in the runner's unit, like every other distance in here.
      expect(brief.text, contains('mi block'));
    });
  });
}
