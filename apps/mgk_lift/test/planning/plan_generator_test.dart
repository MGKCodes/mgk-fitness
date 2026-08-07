import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/planning/domain/plan.dart';
import 'package:mgk_lift/src/features/planning/domain/plan_generator.dart';
import 'package:mgk_lift/src/features/planning/domain/plan_proposal.dart';
import 'package:mgk_lift/src/features/tracking/domain/session.dart';

/// A planner whose weeks are scripted, so the generator's own behaviour — the
/// retry, the dates, how far ahead it fills — is what is under test.
class ScriptedPlanner implements CoachPlanner {
  ScriptedPlanner({required this.weeks, this.arc = const <PlanWeek>[]});

  /// One entry per call to [week], in order.
  final List<WeekProposal> weeks;
  final List<PlanWeek> arc;

  final List<List<String>> violationsSeen = <List<String>>[];
  int weekCalls = 0;

  @override
  Future<List<PlanWeek>> skeleton({
    required PlanIntake intake,
    List<String> violations = const <String>[],
  }) async => arc;

  @override
  Future<WeekProposal> week({
    required PlanIntake intake,
    required PlanWeek slot,
    List<String> violations = const <String>[],
  }) async {
    violationsSeen.add(violations);
    final proposal = weeks[weekCalls.clamp(0, weeks.length - 1)];
    weekCalls++;
    return proposal;
  }

  @override
  Future<IntakeTurn> intake({
    required PlanIntake known,
    required List<PlannerTurn> history,
  }) async => IntakeTurn(reply: '', extracted: known);

  @override
  Future<SwapProposal> swap({
    required String message,
    required Session session,
  }) async => const SwapProposal(reply: '');
}

WeekProposal good({int weekdayA = 1, int weekdayB = 4}) => WeekProposal(
  sessions: <ProposedSession>[
    ProposedSession(
      weekday: weekdayA,
      kind: 'push',
      rationale: 'Because your bench has stalled.',
      movements: const <ProposedMovement>[
        ProposedMovement(name: 'Barbell Bench Press', sets: 3, reps: 5),
      ],
    ),
    ProposedSession(
      weekday: weekdayB,
      kind: 'pull',
      rationale: 'Because your back is behind your chest.',
      movements: const <ProposedMovement>[
        ProposedMovement(name: 'Barbell Row', sets: 3, reps: 8),
      ],
    ),
  ],
);

/// A week on a day the lifter said they cannot train.
WeekProposal wrongDay() => good(weekdayB: 3);

const PlanIntake intake = PlanIntake(
  goal: 'Bench past 100',
  daysPerWeek: 2,
  availableWeekdays: <int>[1, 4],
  equipment: 'Full gym',
);

final List<PlanWeek> eightWeekArc = <PlanWeek>[
  for (var i = 1; i <= 8; i++)
    PlanWeek(
      number: i,
      phase: i % 4 == 0 ? PlanPhase.deload : PlanPhase.build,
      intent: 'Week $i',
    ),
];

void main() {
  group('building a block', () {
    test(
      'a rejected week is retried with its violations as the brief',
      () async {
        // The whole reason PlanValidator writes violations as instructions.
        // "Move the Wednesday session: they only train on Monday, Thursday" is a
        // far better correction than asking again and hoping.
        final planner = ScriptedPlanner(
          arc: eightWeekArc,
          weeks: <WeekProposal>[wrongDay(), good()],
        );
        final generator = PlanGenerator(planner: planner);

        final plan = await generator.generate(
          intake: intake,
          log: const <Session>[],
          startDate: DateTime(2026, 8, 10),
        );

        expect(planner.violationsSeen.first, isEmpty);
        expect(
          planner.violationsSeen[1].join(' '),
          contains('Move the Wednesday session'),
        );
        expect(plan.sessions, isNotEmpty);
      },
    );

    test('it gives up rather than paying for a third attempt', () async {
      // A model that cannot honour the rules on the second attempt will not on
      // the fifth, and every attempt is a paid call made while somebody watches
      // a spinner.
      final planner = ScriptedPlanner(
        arc: eightWeekArc,
        weeks: <WeekProposal>[wrongDay(), wrongDay(), good()],
      );
      final generator = PlanGenerator(planner: planner);

      await expectLater(
        generator.generate(
          intake: intake,
          log: const <Session>[],
          startDate: DateTime(2026, 8, 10),
        ),
        throwsA(
          isA<PlanException>().having(
            (e) => e.failure,
            'failure',
            PlanFailure.couldNotAgree,
          ),
        ),
      );
      expect(planner.weekCalls, 2);
    });

    test('only the first weeks are filled in, not the whole block', () async {
      // A block built eight weeks deep on day one is eight weeks of guesses
      // about a lifter nobody has watched train, and every one is a paid call
      // they might never reach.
      final planner = ScriptedPlanner(
        arc: eightWeekArc,
        weeks: List<WeekProposal>.generate(8, (_) => good()),
      );
      final plan = await PlanGenerator(planner: planner).generate(
        intake: intake,
        log: const <Session>[],
        startDate: DateTime(2026, 8, 10),
      );

      expect(plan.weeks, 8, reason: 'the arc still spans the whole block');
      expect(planner.weekCalls, PlanGenerator.weeksGeneratedUpFront);
      expect(plan.sessions.map((s) => s.weekNumber).toSet(), <int>{1, 2});
    });

    test('a draft is what comes out, never an active plan', () async {
      final planner = ScriptedPlanner(
        arc: eightWeekArc,
        weeks: List<WeekProposal>.generate(8, (_) => good()),
      );
      final plan = await PlanGenerator(planner: planner).generate(
        intake: intake,
        log: const <Session>[],
        startDate: DateTime(2026, 8, 10),
      );
      expect(plan.status, PlanStatus.draft);
    });

    test('an empty arc is a failure, not an empty plan', () async {
      final planner = ScriptedPlanner(arc: const <PlanWeek>[], weeks: const []);
      await expectLater(
        PlanGenerator(planner: planner).generate(
          intake: intake,
          log: const <Session>[],
          startDate: DateTime(2026, 8, 10),
        ),
        throwsA(isA<PlanException>()),
      );
    });
  });

  group('when a session actually falls', () {
    test('weeks run from the start date, not from Monday', () async {
      // A block that began on a Wednesday has week 1 running Wednesday to
      // Tuesday, which is what somebody who started midweek experiences.
      // Anchoring to Monday would give them a three-day first week.
      final planner = ScriptedPlanner(
        arc: eightWeekArc,
        weeks: List<WeekProposal>.generate(8, (_) => good()),
      );
      // 2026-08-12 is a Wednesday.
      final plan = await PlanGenerator(planner: planner).generate(
        intake: intake,
        log: const <Session>[],
        startDate: DateTime(2026, 8, 12),
      );

      final firstMonday = plan.sessions.firstWhere(
        (s) => s.weekNumber == 1 && s.weekday == DateTime.monday,
      );
      // The Monday of week 1 is the one AFTER the Wednesday it started on.
      expect(firstMonday.scheduledDate, DateTime(2026, 8, 17));

      final firstThursday = plan.sessions.firstWhere(
        (s) => s.weekNumber == 1 && s.weekday == DateTime.thursday,
      );
      expect(firstThursday.scheduledDate, DateTime(2026, 8, 13));
    });

    test('week two is seven days after week one', () async {
      final planner = ScriptedPlanner(
        arc: eightWeekArc,
        weeks: List<WeekProposal>.generate(8, (_) => good()),
      );
      final plan = await PlanGenerator(planner: planner).generate(
        intake: intake,
        log: const <Session>[],
        startDate: DateTime(2026, 8, 10),
      );

      final w1 = plan.sessions.firstWhere(
        (s) => s.weekNumber == 1 && s.weekday == 1,
      );
      final w2 = plan.sessions.firstWhere(
        (s) => s.weekNumber == 2 && s.weekday == 1,
      );
      expect(w2.scheduledDate.difference(w1.scheduledDate).inDays, 7);
    });
  });

  group('reading the plan', () {
    Future<Plan> build() async {
      final planner = ScriptedPlanner(
        arc: eightWeekArc,
        weeks: List<WeekProposal>.generate(8, (_) => good()),
      );
      return PlanGenerator(planner: planner).generate(
        intake: intake,
        log: const <Session>[],
        // A Monday.
        startDate: DateTime(2026, 8, 10),
      );
    }

    test('today has a session, or honestly does not', () async {
      final plan = await build();
      expect(plan.sessionOn(DateTime(2026, 8, 10))?.weekday, 1);
      // Tuesday is a rest day. Null is the answer, not a gap.
      expect(plan.sessionOn(DateTime(2026, 8, 11)), isNull);
    });

    test('a rest day still knows what is next', () async {
      // "Nothing today, Thursday is pull" is more use than an empty card.
      final plan = await build();
      final next = plan.nextFrom(DateTime(2026, 8, 11));
      expect(next?.scheduledDate, DateTime(2026, 8, 13));
    });

    test('a date outside the block is outside the block', () async {
      final plan = await build();
      expect(plan.weekOf(DateTime(2026, 8, 9)), isNull);
      expect(plan.weekOf(DateTime(2026, 8, 10)), 1);
      expect(plan.weekOf(DateTime(2026, 8, 17)), 2);
      expect(plan.weekOf(DateTime(2027, 1, 1)), isNull);
    });
  });

  group('what the intake still needs', () {
    test('it names what is missing so the next turn can ask for it', () {
      const empty = PlanIntake();
      expect(empty.isComplete, isFalse);
      expect(empty.missing, contains('goal'));
      expect(empty.missing, contains('which weekdays'));
    });

    test('block length and injuries are not required', () {
      // A lifter with no view on block length is normal, and "nothing hurts"
      // is an answer that leaves the field empty.
      const ready = PlanIntake(
        goal: 'Get stronger',
        daysPerWeek: 3,
        availableWeekdays: <int>[1, 3, 5],
        equipment: 'Dumbbells at home',
      );
      expect(ready.isComplete, isTrue);
      expect(ready.weeksOrDefault, PlanIntake.defaultWeeks);
    });

    test('merging keeps what was already known', () {
      // Every intake turn returns every field, and null means "not learned
      // this turn" rather than "forget it".
      const known = PlanIntake(goal: 'Bench 100', daysPerWeek: 4);
      final merged = known.merge(const PlanIntake(equipment: 'Full gym'));
      expect(merged.goal, 'Bench 100');
      expect(merged.daysPerWeek, 4);
      expect(merged.equipment, 'Full gym');
    });
  });
}
