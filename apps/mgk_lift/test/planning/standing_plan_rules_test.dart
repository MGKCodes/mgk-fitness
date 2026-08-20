import 'package:flutter_test/flutter_test.dart';
import 'package:mgk_lift/src/features/planning/domain/standing_plan.dart';
import 'package:mgk_lift/src/features/planning/domain/standing_plan_rules.dart';
import 'package:mgk_lift/src/features/planning/domain/training_split.dart';

MovementSlot slot(String role, {bool main = false}) =>
    MovementSlot(id: role, role: role, movement: role, isMain: main);

StandingPlan plan({
  TrainingSplit split = TrainingSplit.upperLower,
  List<int> weekdays = const <int>[1, 2, 4, 5],
  Map<String, List<MovementSlot>>? slots,
}) => StandingPlan(
  id: 'p',
  split: split,
  weekdays: weekdays,
  slots:
      slots ??
      <String, List<MovementSlot>>{
        'Upper': <MovementSlot>[slot('bench', main: true), slot('row')],
        'Lower': <MovementSlot>[slot('squat', main: true), slot('calf')],
      },
);

void main() {
  test('a well-formed plan has nothing to say about it', () {
    expect(StandingPlanRules.violations(plan()), isEmpty);
    expect(StandingPlanRules.isUsable(plan()), isTrue);
  });

  test('a plan with no training days is caught before anything else', () {
    final v = StandingPlanRules.violations(plan(weekdays: const <int>[]));
    expect(v, hasLength(1));
    expect(v.single, contains('at least one training day'));
  });

  test('the split has to agree with the day count', () {
    // Four days is Upper/Lower. Push/Pull/Legs over four means one of the two
    // was overridden without the other being told.
    final v = StandingPlanRules.violations(
      plan(split: TrainingSplit.pushPullLegs),
    );
    expect(v.join(), contains('4-day week is Upper / Lower'));
  });

  test('a day the week runs must have movements in it', () {
    // An empty day renders perfectly happily as a session with nothing in it.
    final v = StandingPlanRules.violations(
      plan(
        slots: <String, List<MovementSlot>>{
          'Upper': <MovementSlot>[slot('bench', main: true)],
          'Lower': <MovementSlot>[],
        },
      ),
    );
    expect(v.join(), contains('at least one movement in Lower'));
  });

  test('slots for a day the plan never trains are a disagreement', () {
    final v = StandingPlanRules.violations(
      plan(
        slots: <String, List<MovementSlot>>{
          'Upper': <MovementSlot>[slot('bench', main: true)],
          'Lower': <MovementSlot>[slot('squat', main: true)],
          'Legs': <MovementSlot>[slot('leg press')],
        },
      ),
    );
    expect(v.join(), contains('Legs is not part of'));
  });

  test('a plan of nothing but accessories never progresses', () {
    // And never says so, because the stall rule exempts main lifts.
    final v = StandingPlanRules.violations(
      plan(
        slots: <String, List<MovementSlot>>{
          'Upper': <MovementSlot>[slot('lateral raise')],
          'Lower': <MovementSlot>[slot('calf')],
        },
      ),
    );
    expect(v.join(), contains('at least one main lift'));
  });

  test('the same weekday twice is caught', () {
    final v = StandingPlanRules.violations(
      plan(weekdays: const <int>[1, 1, 4, 5]),
    );
    expect(v.join(), contains('different weekday'));
  });

  test('violations read as instructions, not complaints', () {
    // They go straight back to whatever produced the plan, so they have to say
    // what to do rather than what went wrong.
    final v = StandingPlanRules.violations(
      plan(
        slots: <String, List<MovementSlot>>{
          'Upper': <MovementSlot>[slot('bench', main: true)],
          'Lower': <MovementSlot>[],
        },
      ),
    );
    expect(v.single.startsWith('Put '), isTrue);
  });
}
