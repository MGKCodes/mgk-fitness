import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_history.dart';
import 'package:mgk_run/src/features/coaching/domain/plan_shape.dart';

/// Every plan Runio ever built is still on disk — `savePlan` supersedes rather
/// than deletes. Nothing read them back, so a runner two marathon blocks in
/// looked exactly like one who had just arrived.
void main() {
  PlanRecord plan({
    String id = 'p',
    required DateTime start,
    int weeks = 16,
    double? goal = 42195,
    DateTime? event,
    DateTime? endedAt,
    bool active = false,
  }) => PlanRecord(
    id: id,
    startDate: start,
    weeks: weeks,
    isActive: active,
    goalDistanceMeters: goal,
    eventDate: event,
    endedAt: endedAt,
  );

  String km(double m) => '${(m / 1000).toStringAsFixed(1)} km';

  group('what became of a plan', () {
    test('the active one is current, whatever its dates say', () {
      final p = plan(
        start: DateTime(2026, 1, 5),
        event: DateTime(2026, 4, 20),
        active: true,
      );
      expect(p.outcome, PlanOutcome.current);
    });

    test('race day inside the plan life means they got there', () {
      // The strongest claim the record can make. It does not know whether they
      // ran it, only that they reached it still on the plan.
      final p = plan(
        start: DateTime(2026, 1, 5),
        event: DateTime(2026, 4, 20),
        endedAt: DateTime(2026, 5, 1),
      );
      expect(p.outcome, PlanOutcome.raced);
      expect(p.wasSeenThrough, isTrue);
    });

    test('replaced before race day means they left it early', () {
      final p = plan(
        start: DateTime(2026, 1, 5),
        event: DateTime(2026, 4, 20),
        endedAt: DateTime(2026, 3, 1),
      );
      expect(p.outcome, PlanOutcome.leftEarly);
    });

    test('a horizon cannot be raced or abandoned', () {
      // No date to arrive at, so neither verdict applies (ADR-0011).
      final p = plan(
        start: DateTime(2026, 1, 5),
        endedAt: DateTime(2026, 3, 1),
      );
      expect(p.shape, PlanShape.horizon);
      expect(p.outcome, PlanOutcome.ended);
    });

    test('a rhythm is a shape, not a missing goal', () {
      final p = plan(start: DateTime(2026, 1, 5), goal: null);
      expect(p.shape, PlanShape.rhythm);
      expect(p.outcome, PlanOutcome.ended);
    });
  });

  group('which week they reached', () {
    test('the week they were in when it was replaced', () {
      // "They stopped a marathon block at week 9 of 16" is the difference
      // between having tried before and having stopped in the same place twice.
      final p = plan(
        start: DateTime(2026, 1, 5),
        event: DateTime(2026, 4, 20),
        endedAt: DateTime(2026, 3, 4), // 8 weeks and change later
      );
      expect(p.weekReached, 9);
    });

    test('week 1 on the day it started', () {
      final p = plan(
        start: DateTime(2026, 1, 5),
        endedAt: DateTime(2026, 1, 5),
      );
      expect(p.weekReached, 1);
    });

    test('never past the end of the arc', () {
      // A plan left running long after its race must not read as week 40 of 16.
      final p = plan(
        start: DateTime(2026, 1, 5),
        weeks: 16,
        endedAt: DateTime(2027, 1, 5),
      );
      expect(p.weekReached, 16);
    });

    test('a plan with no end is assumed seen through', () {
      final p = plan(start: DateTime(2026, 1, 5), weeks: 12);
      expect(p.weekReached, 12);
      expect(p.wasSeenThrough, isTrue);
    });
  });

  group('labels are stable, which is the whole design', () {
    test('a label is fixed the day it is earned', () {
      // Numbered oldest-first. If the newest were "Marathon plan 1" then adding
      // a plan would renumber every older one, and a coach saying "you stopped
      // Marathon plan 2 at week nine" would point somewhere else next month.
      final first = plan(id: 'a', start: DateTime(2025, 1, 6));
      final second = plan(id: 'b', start: DateTime(2026, 1, 5));

      final before = labelPlans(<PlanRecord>[first]);
      expect(before.single.label, 'Marathon plan');

      final after = labelPlans(<PlanRecord>[first, second]);
      expect(after[0].label, 'Marathon plan 1', reason: 'still the first one');
      expect(after[1].label, 'Marathon plan 2');
    });

    test('numbered per distance, because that is how people talk', () {
      final plans = <PlanRecord>[
        plan(id: 'a', start: DateTime(2025, 1, 6)),
        plan(id: 'b', start: DateTime(2025, 6, 2), goal: 21097),
        plan(id: 'c', start: DateTime(2026, 1, 5)),
      ];
      final labelled = labelPlans(plans);

      expect(labelled[0].label, 'Marathon plan 1');
      expect(labelled[1].label, 'Half marathon plan');
      expect(labelled[2].label, 'Marathon plan 2');
    });

    test('no number while it is the only one of its kind', () {
      final labelled = labelPlans(<PlanRecord>[
        plan(start: DateTime(2026, 1, 5), goal: 10000),
      ]);
      expect(labelled.single.label, '10k plan');
    });

    test('a marathon is a marathon however it was entered', () {
      // 42195 and 42200 are the same runner's second marathon, not two firsts.
      final labelled = labelPlans(<PlanRecord>[
        plan(id: 'a', start: DateTime(2025, 1, 6), goal: 42195),
        plan(id: 'b', start: DateTime(2026, 1, 5), goal: 42200),
      ]);
      expect(labelled[0].label, 'Marathon plan 1');
      expect(labelled[1].label, 'Marathon plan 2');
    });

    test('an unnamed distance is said in kilometres', () {
      final labelled = labelPlans(<PlanRecord>[
        plan(start: DateTime(2026, 1, 5), goal: 12400),
      ]);
      expect(labelled.single.label, '12.4k plan');
    });

    test('a rhythm is named, not numbered as a distance', () {
      final labelled = labelPlans(<PlanRecord>[
        plan(start: DateTime(2026, 1, 5), goal: null),
      ]);
      expect(labelled.single.label, 'Keeping a rhythm');
    });
  });

  group('the line the coach reads', () {
    test('no history is no line, not an empty one', () {
      final only = labelPlans(<PlanRecord>[
        plan(start: DateTime(2026, 1, 5), active: true),
      ]);
      expect(planHistoryLine(only, distance: km), isNull);
    });

    test('one finished block is counted and credited', () {
      final history = labelPlans(<PlanRecord>[
        plan(
          id: 'a',
          start: DateTime(2025, 1, 6),
          event: DateTime(2025, 4, 20),
          endedAt: DateTime(2025, 5, 1),
        ),
        plan(id: 'b', start: DateTime(2026, 1, 5), active: true),
      ]);
      final line = planHistoryLine(history, distance: km)!;

      expect(line, contains('one plan before this'));
      expect(line, contains('saw one of them through'));
    });

    test('an unfinished block is named with the week they stopped at', () {
      // The case a coach should actually know about.
      final history = labelPlans(<PlanRecord>[
        plan(
          id: 'a',
          start: DateTime(2025, 1, 6),
          event: DateTime(2025, 4, 20),
          endedAt: DateTime(2025, 3, 5),
        ),
        plan(id: 'b', start: DateTime(2026, 1, 5), active: true),
      ]);
      final line = planHistoryLine(history, distance: km)!;

      expect(line, contains('42.2 km block'));
      expect(line, contains('week 9 of 16'));
      // And told not to open with it, like every other fact in the brief.
      expect(line, contains('Do not bring this up unless'));
    });

    test('the current plan is not counted as history', () {
      final history = labelPlans(<PlanRecord>[
        plan(id: 'a', start: DateTime(2026, 1, 5), active: true),
      ]);
      expect(planHistoryLine(history, distance: km), isNull);
    });

    test('it reads as prose, with no structs to recite', () {
      final history = labelPlans(<PlanRecord>[
        plan(
          id: 'a',
          start: DateTime(2025, 1, 6),
          event: DateTime(2025, 4, 20),
          endedAt: DateTime(2025, 3, 5),
        ),
        plan(id: 'b', start: DateTime(2025, 6, 2), goal: 21097),
        plan(id: 'c', start: DateTime(2026, 1, 5), active: true),
      ]);
      final line = planHistoryLine(history, distance: km)!;

      for (final token in <String>['{', '}', '[', ']', '":', '_']) {
        expect(line, isNot(contains(token)));
      }
      expect(line, contains('2 plans before this'));
    });
  });
}
